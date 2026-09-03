#!/usr/bin/env bash
# Three renders of each verse, so the prosody layer can be judged against what
# it is meant to improve on.
#
#   Tools/sanskrit-prosody-experiment.sh --model <kokoro.safetensors> --voices <dir>
#
#   *_current.wav   recitation delivery, no duration intent  (today's default)
#   *_slow.wav      learning delivery, no duration intent    (slower, uniformly)
#   *_prosody.wav   recitation speed + Sanskrit duration intent
#
# The prosody version uses the SAME phonemes and the SAME token ids as
# _current. Only the per-token duration multiplier differs: guru vowels get
# more time, laghu vowels slightly less, conjunct codas are held, aspiration
# gets its release. That is the point of the comparison — _slow shows what a
# uniform slowdown buys, _prosody what preserving the contrasts buys.

set -euo pipefail
cd "$(dirname "$0")/.."

model=""; voices=""; voice="hf_alpha"; out="Artifacts/sanskrit/prosody-experiment"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --voices) voices="$2"; shift 2 ;;
    --voice) voice="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    *) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
[[ -n "$model" && -n "$voices" ]] || { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

mkdir -p "$out"
trap 'rm -f Tests/KokoroSwiftTests/ZZProsodyExp.swift' EXIT

cat > Tests/KokoroSwiftTests/ZZProsodyExp.swift <<'SWIFT'
import Foundation
import MLX
import Testing
@testable import KokoroSwift

@Test func zzProsodyExp() throws {
  let environment = ProcessInfo.processInfo.environment
  guard let modelPath = environment["SA_MODEL"],
        let voiceDirectory = environment["SA_VOICES"],
        let voiceName = environment["SA_VOICE"],
        let outputDirectory = environment["SA_OUT"]
  else { return }

  let verses: [(id: String, text: String)] = [
    ("bg_01_01", "धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।\nमामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥"),
    ("bg_02_47", "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।\nमा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥"),
    ("bg_04_07", "यदा यदा हि धर्मस्य ग्लानिर्भवति भारत ।\nअभ्युत्थानमधर्मस्य तदात्मानं सृजाम्यहम् ॥"),
  ]

  let tts = try KokoroTTS(modelPath: URL(fileURLWithPath: modelPath), g2p: .sanskrit)
  let voiceURL = URL(fileURLWithPath: voiceDirectory).appendingPathComponent("\(voiceName).safetensors")
  guard let voice = try MLX.loadArrays(url: voiceURL)["voice"] else { return }
  let sampleRate = Double(KokoroTTS.Constants.samplingRate)

  var rows = ["file\ttext\tsyllables\tguru_laghu\tmatras\tholding_points"
    + "\tphonemes\ttokens\tduration_changes\tvoice\tspeed\twarnings"]

  func render(
    _ text: String, delivery: SanskritDelivery, intent: SanskritProsodyIntent
  ) throws -> [Float] {
    var audio: [Float] = []
    for segment in SanskritProsody.segments(for: text, configuration: delivery.prosody) {
      // The scale is derived per segment so it lines up with that segment's
      // own tokens; nil intent means the model's prediction stands.
      let scale = intent == .neutral ? nil
        : SanskritProsodyPlanner.durationScaleForPhonemes(segment.phonemes, intent: intent)
      let piece = try tts.generateAudio(
        voice: voice, phonemes: segment.phonemes,
        speed: delivery.speed, durationScale: scale
      )
      audio += AudioSegments.trimmingEdgeSilence(piece, sampleRate: sampleRate)
      audio += [Float](repeating: 0, count: Int(segment.pauseAfter / Double(delivery.speed) * sampleRate))
    }
    return audio
  }

  for verse in verses {
    let plan = SanskritProsodyPlanner.plan(for: verse.text, intent: .recitation)
    let analysis = SanskritPhonemizer.analyze(verse.text)
    let audit = SanskritTokenAudit.audit(phonemes: analysis.kokoroPhonemes)
    let holding = plan.units.filter(\.holdCoda).map { $0.syllable.slp1 }

    for variant in [("current", SanskritDelivery.recitation, SanskritProsodyIntent.neutral),
                    ("slow", SanskritDelivery.learning, SanskritProsodyIntent.neutral),
                    ("prosody", SanskritDelivery.recitation, SanskritProsodyIntent.recitation)] {
      let (name, delivery, intent) = variant
      let audio = try render(verse.text, delivery: delivery, intent: intent)
      let file = "\(verse.id)_\(name).wav"
      try AudioUtils.writeWavFile(
        samples: audio, sampleRate: sampleRate,
        fileURL: URL(fileURLWithPath: outputDirectory).appendingPathComponent(file)
      )
      let changes = intent == .neutral ? "none (model prediction stands)"
        : "guru vowel ×\(intent.guruVowelScale), laghu ×\(intent.laghuVowelScale), "
          + "held coda ×\(intent.heldCodaScale), aspiration ×\(intent.aspirationScale)"
      rows.append([
        file, verse.text.replacingOccurrences(of: "\n", with: " "),
        String(plan.units.count), plan.weightPattern, String(plan.totalMatras),
        holding.joined(separator: " "), analysis.kokoroPhonemes,
        audit.tokenIDs.map(String.init).joined(separator: " "),
        changes, voiceName, String(delivery.speed),
        analysis.warnings.map(\.text).joined(separator: " | "),
      ].joined(separator: "\t"))
      print("WROTE \(file)  \(String(format: "%.2f", Double(audio.count)/sampleRate))s")
    }
  }

  try rows.joined(separator: "\n").write(
    toFile: outputDirectory + "/manifest.tsv", atomically: true, encoding: .utf8)
  print("MANIFEST \(outputDirectory)/manifest.tsv")
}
SWIFT

SA_MODEL="$model" SA_VOICES="$voices" SA_VOICE="$voice" SA_OUT="$out" \
  swift test --filter zzProsodyExp 2>&1 | grep -E "^WROTE|^MANIFEST|error:"
