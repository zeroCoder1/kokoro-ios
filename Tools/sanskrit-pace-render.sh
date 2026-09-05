#!/usr/bin/env bash
# Render the validation verses at one delivery, for listening.
#
#   Tools/sanskrit-pace-render.sh --model <m> --voices <dir> [--voice hf_alpha]
#       [--delivery traditional|recitation|learning] [--out <dir>]
#
# Used to put the shipped deliveries side by side against the human reciter
# recordings the pace was calibrated from.
set -euo pipefail
cd "$(dirname "$0")/.."
model=""; voices=""; voice="hf_alpha"; delivery="traditional"; out="Artifacts/sanskrit/pace-v1/render"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)    model="$2"; shift 2 ;;
    --voices)   voices="$2"; shift 2 ;;
    --voice)    voice="$2"; shift 2 ;;
    --delivery) delivery="$2"; shift 2 ;;
    --out)      out="$2"; shift 2 ;;
    *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
[[ -n "$model" && -n "$voices" ]] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

mkdir -p "$out"
trap 'rm -f Tests/KokoroSwiftTests/ZZPaceRender.swift' EXIT

cat > Tests/KokoroSwiftTests/ZZPaceRender.swift <<'SWIFT'
import Foundation
import MLX
import Testing
@testable import KokoroSwift

@Test func zzPaceRender() throws {
  let env = ProcessInfo.processInfo.environment
  guard let modelPath = env["SA_MODEL"], let voiceDirectory = env["SA_VOICES"],
        let voiceName = env["SA_VOICE"], let root = env["SA_OUT"],
        let deliveryName = env["SA_DELIVERY"] else { return }
  let delivery: SanskritDelivery = switch deliveryName {
  case "traditional": .traditional
  case "recitation":  .recitation
  case "learning":    .learning
  default:            .recitation
  }
  let tts = try KokoroTTS(modelPath: URL(fileURLWithPath: modelPath), g2p: .sanskrit)
  guard let voice = try MLX.loadArrays(
    url: URL(fileURLWithPath: voiceDirectory).appendingPathComponent("\(voiceName).safetensors")
  )["voice"] else { return }
  let sampleRate = Double(KokoroTTS.Constants.samplingRate)

  let verses: [(String, String)] = [
    ("bg_01_01", """
      धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।
      मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥
      """),
    ("bg_02_47", """
      कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।
      मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥
      """),
    ("bg_04_07", """
      यदा यदा हि धर्मस्य ग्लानिर्भवति भारत ।
      अभ्युत्थानमधर्मस्य तदात्मानं सृजाम्यहम् ॥
      """),
  ]

  for (id, text) in verses {
    let segments = SanskritProsody.segments(for: text, configuration: delivery.prosody)
    var audio: [Float] = []
    for segment in segments {
      let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
        segment.phonemes, intent: delivery.intent
      )
      let piece = try tts.generateAudio(
        voice: voice, phonemes: segment.phonemes, speed: delivery.speed, durationScale: scale
      )
      audio += AudioSegments.trimmingEdgeSilence(piece, sampleRate: sampleRate)
      audio += [Float](repeating: 0, count: Int(segment.pauseAfter / Double(delivery.speed) * sampleRate))
    }
    let name = "\(id)_\(deliveryName)"
    try AudioUtils.writeWavFile(
      samples: audio, sampleRate: sampleRate,
      fileURL: URL(fileURLWithPath: root).appendingPathComponent("\(name).wav")
    )
    print("WROTE \(name) \(String(format: "%.2f", Double(audio.count) / sampleRate))s")
  }
}
SWIFT

SA_MODEL="$model" SA_VOICES="$voices" SA_VOICE="$voice" SA_OUT="$out" \
SA_DELIVERY="$delivery" \
  swift test --filter zzPaceRender 2>&1 | grep -E "^WROTE|error:"
