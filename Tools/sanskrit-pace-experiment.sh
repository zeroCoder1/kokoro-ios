#!/usr/bin/env bash
# Sweep the speaking rate against a recorded human reciter.
#
#   Tools/sanskrit-pace-experiment.sh --model <m> --voices <dir> [--voice hf_alpha]
#       [--out Artifacts/sanskrit/pace-v1]
#
# `recitation` at 0.80 was chosen as the slowest rate at which Kokoro still
# articulates every syllable — a constraint of the model, not a description of
# how the Gita is chanted. The Gita Supersite recordings put a human reciter at
# 482 ms per syllable against our 283 ms, so this sweeps the gap between them.
#
# Two renders per speed:
#
#   whole_*    one generateAudio call, no inserted pause. Gives the raw phoneme
#              rate and, separately, the gap the model puts at the danda on its
#              own — which is what an inserted pause has to beat to be worth
#              inserting at all.
#   split_*    the shipped path: one call per half-verse, rejoined with real
#              silence.
#
# Phonemes and token ids are identical at every speed; only timing changes.
set -euo pipefail
cd "$(dirname "$0")/.."
model=""; voices=""; voice="hf_alpha"; out="Artifacts/sanskrit/pace-v1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)  model="$2"; shift 2 ;;
    --voices) voices="$2"; shift 2 ;;
    --voice)  voice="$2"; shift 2 ;;
    --out)    out="$2"; shift 2 ;;
    *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
[[ -n "$model" && -n "$voices" ]] || { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

mkdir -p "$out"
trap 'rm -f Tests/KokoroSwiftTests/ZZPace.swift' EXIT

cat > Tests/KokoroSwiftTests/ZZPace.swift <<'SWIFT'
import Foundation
import MLX
import Testing
@testable import KokoroSwift

@Test func zzPace() throws {
  let env = ProcessInfo.processInfo.environment
  guard let modelPath = env["SA_MODEL"], let voiceDirectory = env["SA_VOICES"],
        let voiceName = env["SA_VOICE"], let root = env["SA_OUT"] else { return }
  let tts = try KokoroTTS(modelPath: URL(fileURLWithPath: modelPath), g2p: .sanskrit)
  guard let voice = try MLX.loadArrays(
    url: URL(fileURLWithPath: voiceDirectory).appendingPathComponent("\(voiceName).safetensors")
  )["voice"] else { return }
  let sampleRate = Double(KokoroTTS.Constants.samplingRate)

  let verses: [(String, String, Int)] = [
    ("bg_01_01", """
      धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।
      मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥
      """, 32),
    ("bg_02_47", """
      कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।
      मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥
      """, 32),
    ("bg_04_07", """
      यदा यदा हि धर्मस्य ग्लानिर्भवति भारत ।
      अभ्युत्थानमधर्मस्य तदात्मानं सृजाम्यहम् ॥
      """, 32),
  ]
  // The shell exports these unconditionally, so an unset variable arrives as
  // "" rather than absent. Empty means "use the default", or the sweep would
  // silently render nothing and still write a manifest.
  func setting(_ key: String, default fallback: String) -> [String] {
    let raw = env[key].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
  }
  // compactMap would drop a typo and keep going, and Float alone accepts 0,
  // negatives and infinities — all of which reach `Int(pause * sampleRate)`
  // and the duration arithmetic. Reject the whole setting instead.
  var speeds: [Float] = []
  for value in setting("SA_SPEEDS", default: "0.80,0.65,0.55,0.50,0.46,0.42") {
    guard let speed = Float(value), speed.isFinite, speed > 0 else {
      Issue.record("error: bad SA_SPEEDS value '\(value)'; "
                   + "expected finite numbers greater than zero")
      return
    }
    speeds.append(speed)
  }
  let modes = setting("SA_MODES", default: "whole,split")
  guard !speeds.isEmpty else {
    Issue.record("no usable speeds in SA_SPEEDS='\(env["SA_SPEEDS"] ?? "")'")
    return
  }
  guard modes.contains("whole") || modes.contains("split") else {
    Issue.record("no usable modes in SA_MODES='\(env["SA_MODES"] ?? "")'")
    return
  }

  var rows: [String] = []
  func record(_ name: String, _ audio: [Float], _ fields: String) throws {
    try AudioUtils.writeWavFile(
      samples: audio, sampleRate: sampleRate,
      fileURL: URL(fileURLWithPath: root).appendingPathComponent("\(name).wav")
    )
    rows.append("""
        {"file": "\(name).wav", \(fields), "seconds": \
      \(String(format: "%.3f", Double(audio.count) / sampleRate))}
      """)
    print("WROTE \(name) \(String(format: "%.2f", Double(audio.count) / sampleRate))s")
  }

  for (id, text, syllables) in verses {
    for speed in speeds {
      let tag = String(format: "%.2f", speed).replacingOccurrences(of: ".", with: "")

      // 1. One call, no inserted pause: the model's own pacing and its own gap.
      if modes.contains("whole") {
      let whole = SanskritProsody.segments(for: text, configuration: .none)
      var wholeAudio: [Float] = []
      for segment in whole {
        let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
          segment.phonemes,
          visargaTokenIndices: segment.visargaTokenIndices,
          intent: SanskritDelivery.recitation.intent
        )
        wholeAudio += try tts.generateAudio(
          voice: voice, phonemes: segment.phonemes, speed: speed, durationScale: scale
        )
      }
      try record("whole_\(id)_\(tag)", wholeAudio,
                 "\"verse\": \"\(id)\", \"speed\": \(speed), \"syllables\": \(syllables), \"pada_pause_at_speed_1\": 0, \"pada_pause_rendered\": 0, \"mode\": \"whole\"")
      }

      // 2. The shipped split path, at the pause the recitation delivery uses.
      if modes.contains("split") {
      let configuration = SanskritProsodyConfiguration(padaPause: 0.50, versePause: 1.00)
      let split = SanskritProsody.segments(for: text, configuration: configuration)
      var splitAudio: [Float] = []
      for segment in split {
        let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
          segment.phonemes,
          visargaTokenIndices: segment.visargaTokenIndices,
          intent: SanskritDelivery.recitation.intent
        )
        let piece = try tts.generateAudio(
          voice: voice, phonemes: segment.phonemes, speed: speed, durationScale: scale
        )
        splitAudio += AudioSegments.trimmingEdgeSilence(piece, sampleRate: sampleRate)
        let pause = segment.pauseAfter / Double(speed)
        splitAudio += [Float](repeating: 0, count: Int(pause * sampleRate))
      }
      try record("split_\(id)_\(tag)", splitAudio,
                 "\"verse\": \"\(id)\", \"speed\": \(speed), \"syllables\": \(syllables), \"pada_pause_at_speed_1\": 0.50, \"pada_pause_rendered\": \(0.50 / Double(speed)), \"mode\": \"split\"")
      }
    }
  }

  guard !rows.isEmpty else {
    Issue.record("sweep rendered nothing; manifest not written")
    return
  }
  let json = "{\n  \"renders\": [\n" + rows.joined(separator: ",\n") + "\n  ]\n}\n"
  try json.write(toFile: root + "/manifest.json", atomically: true, encoding: .utf8)
  print("MANIFEST \(root)/manifest.json")
}
SWIFT

SA_MODEL="$model" SA_VOICES="$voices" SA_VOICE="$voice" SA_OUT="$out" \
SA_SPEEDS="${SA_SPEEDS:-}" SA_MODES="${SA_MODES:-}" \
  swift test --filter zzPace 2>&1 | grep -E "^WROTE|^MANIFEST|error:"
