#!/usr/bin/env bash
# Render the three validation verses with the prosody layer, plus a manifest
# recording exactly what produced them.
#
#   Tools/sanskrit-validate.sh --model <kokoro.safetensors> --voices <dir> \
#       [--voice hf_alpha] [--out Artifacts/sanskrit/validation-v2]
#
# Writes bg_01_01.wav, bg_01_01_slow.wav, bg_02_47.wav, bg_04_07.wav and
# manifest.json. Unlike sanskrit-render.sh this synthesizes per pada and joins
# with real silence, because Kokoro's punctuation does not produce a usable
# pause — see docs/SANSKRIT.md and the diagnostics report.

set -euo pipefail
cd "$(dirname "$0")/.."

model=""; voices=""; voice="hf_alpha"; out="Artifacts/sanskrit/validation-v2"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)  model="$2"; shift 2 ;;
    --voices) voices="$2"; shift 2 ;;
    --voice)  voice="$2"; shift 2 ;;
    --out)    out="$2"; shift 2 ;;
    *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
[[ -n "$model" && -n "$voices" ]] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

mkdir -p "$out"
trap 'rm -f Tests/KokoroSwiftTests/ZZValidate.swift' EXIT

cat > Tests/KokoroSwiftTests/ZZValidate.swift <<'SWIFT'
import Foundation
import MLX
import Testing
@testable import KokoroSwift

@Test func zzValidate() throws {
  let environment = ProcessInfo.processInfo.environment
  guard let modelPath = environment["SA_MODEL"],
        let voiceDirectory = environment["SA_VOICES"],
        let voiceName = environment["SA_VOICE"],
        let outputDirectory = environment["SA_OUT"],
        let commit = environment["SA_COMMIT"]
  else { return }

  let modes: [(name: String, delivery: SanskritDelivery)] = [
    ("learning", .learning), ("recitation", .recitation), ("fast", .fast),
  ]

  let verses: [(id: String, text: String)] = [
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

  let modelURL = URL(fileURLWithPath: modelPath)
  let voiceURL = URL(fileURLWithPath: voiceDirectory)
    .appendingPathComponent("\(voiceName).safetensors")
  let tts = try KokoroTTS(modelPath: modelURL, g2p: .sanskrit)
  guard let voice = try MLX.loadArrays(url: voiceURL)["voice"] else {
    print("error: no 'voice' array in \(voiceURL.path)"); return
  }

  let sampleRate = Double(KokoroTTS.Constants.samplingRate)
  var entries: [String] = []

  /// Synthesizes each pada separately and joins them with the silence the
  /// configuration asks for. Kokoro's punctuation cannot supply a real pause.
  func render(
    _ text: String, delivery: SanskritDelivery
  ) throws -> ([Float], [SanskritProsody.Segment]) {
    let speed = delivery.speed
    let segments = SanskritProsody.segments(for: text, configuration: delivery.prosody)
    var audio: [Float] = []
    for segment in segments {
      let piece = try tts.generateAudio(voice: voice, phonemes: segment.phonemes, speed: speed)
      audio += AudioSegments.trimmingEdgeSilence(piece, sampleRate: sampleRate)
      // Slower recitation wants proportionally longer pauses.
      let pause = segment.pauseAfter / Double(speed)
      audio += [Float](repeating: 0, count: Int(pause * sampleRate))
    }
    return (audio, segments)
  }

  func quote(_ s: String) -> String {
    var out = ""
    for c in s.unicodeScalars {
      switch c {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      default: out.unicodeScalars.append(c)
      }
    }
    return "\"\(out)\""
  }

  // Isolated targets: one word each, at the recitation delivery, so a single
  // problem can be listened to without hunting for it inside a verse.
  let targets: [(id: String, text: String)] = [
    ("visarga_yuyutsavah", "युयुत्सवः"),
    ("visarga_mamakah", "मामकाः"),
    ("nasal_sanjaya", "सञ्जय"),
    ("cluster_pandavashchaiva", "पाण्डवाश्चैव"),
    ("cluster_rbhurma", "कर्मफलहेतुर्भूर्मा"),
    ("cluster_sangostvakarmani", "सङ्गोऽस्त्वकर्मणि"),
    ("cluster_abhyutthanam", "अभ्युत्थानम्"),
    ("vocalic_r_srijamyaham", "सृजाम्यहम्"),
    ("vocalic_r_krishna", "कृष्ण"),
    ("vocalic_r_hrishikesha", "हृषीकेश"),
  ]

  for verse in verses {
    for mode in modes {
      let speed = mode.delivery.speed
      let (audio, segments) = try render(verse.text, delivery: mode.delivery)
      let name = "\(verse.id)_\(mode.name).wav"
      try AudioUtils.writeWavFile(
        samples: audio, sampleRate: sampleRate,
        fileURL: URL(fileURLWithPath: outputDirectory).appendingPathComponent(name)
      )
      let analysis = SanskritPhonemizer.analyze(verse.text)
      let audit = SanskritTokenAudit.audit(phonemes: analysis.kokoroPhonemes)
      let seconds = Double(audio.count) / sampleRate
      let phonemeList = segments.map { quote($0.phonemes) }.joined(separator: ", ")
      let pauseList = segments.map { String($0.pauseAfter) }.joined(separator: ", ")
      let warningList = analysis.warnings.map { quote($0.text) }.joined(separator: ", ")

      entries.append("""
          {
            "verse_id": \(quote(verse.id)),
            "file": \(quote(name)),
            "source_text": \(quote(verse.text)),
            "canonical": \(quote(analysis.canonical)),
            "phonological": \(quote(analysis.phonological)),
            "kokoro_phonemes": \(quote(analysis.kokoroPhonemes)),
            "segment_phonemes": [\(phonemeList)],
            "segment_pauses_seconds": [\(pauseList)],
            "decoded_tokens": [\(audit.decoded.map { quote($0) }.joined(separator: ", "))],
            "token_ids": [\(audit.tokenIDs.map(String.init).joined(separator: ", "))],
            "token_count": \(audit.tokenIDs.count),
            "round_trip_ok": \(audit.roundTrips),
            "voice": \(quote(voiceName)),
            "mode": \(quote(mode.name)),
            "speed": \(speed),
            "prosody": {
              "word_boundary": \(mode.delivery.prosody.wordBoundary),
              "pada_pause": \(mode.delivery.prosody.padaPause),
              "verse_pause": \(mode.delivery.prosody.versePause)
            },
            "boundaries": [\(segments.map { quote("\($0.boundary.map(String.init(describing:)) ?? "end")") }.joined(separator: ", "))],
            "approximations": [\(analysis.warnings.filter { $0.text.contains("APPROXIM") || $0.text.contains("UNSUPPORTED") }.map { quote($0.text) }.joined(separator: ", "))],
            "source_edition": "Bhagavad Gita, standard Devanagari text",
            "normalized": \(quote(analysis.normalized)),
            "duration_seconds": \(String(format: "%.3f", seconds)),
            "warnings": [\(warningList)],
            "commit": \(quote(commit)),
            "model": "kokoro-v1_0 (hexgrad/Kokoro-82M)",
            "voice_id": \(quote(voiceName))
          }
        """)
      print("WROTE \(name)  \(String(format: "%.2f", seconds))s")
    }
  }

  for target in targets {
    let delivery = SanskritDelivery.recitation
    let (audio, segments) = try render(target.text, delivery: delivery)
    let name = "\(target.id).wav"
    try AudioUtils.writeWavFile(
      samples: audio, sampleRate: sampleRate,
      fileURL: URL(fileURLWithPath: outputDirectory).appendingPathComponent(name)
    )
    let analysis = SanskritPhonemizer.analyze(target.text)
    let audit = SanskritTokenAudit.audit(phonemes: analysis.kokoroPhonemes)
    let seconds = Double(audio.count) / sampleRate
    let limitation: String
    if target.id.hasPrefix("visarga") { limitation = "ACOUSTIC_MODEL_LIMITATION: VISARGA" }
    else if target.id.hasPrefix("vocalic_r") { limitation = "ACOUSTIC_MODEL_LIMITATION: VOCALIC_R" }
    else if target.id.hasPrefix("nasal") { limitation = "REVIEW_REQUIRED: PALATAL_NASAL" }
    else { limitation = "ACOUSTIC_MODEL_LIMITATION: CLUSTER" }
    entries.append("""
        {
          "verse_id": \(quote(target.id)),
          "file": \(quote(name)),
          "source_text": \(quote(target.text)),
          "source_edition": "isolated diagnostic target",
          "normalized": \(quote(analysis.normalized)),
          "canonical": \(quote(analysis.canonical)),
          "phonological": \(quote(analysis.phonological)),
          "kokoro_phonemes": \(quote(analysis.kokoroPhonemes)),
          "decoded_tokens": [\(audit.decoded.map { quote($0) }.joined(separator: ", "))],
          "token_ids": [\(audit.tokenIDs.map(String.init).joined(separator: ", "))],
          "token_count": \(audit.tokenIDs.count),
          "round_trip_ok": \(audit.roundTrips),
          "alignment": [\(analysis.alignment.map { entry in
            "{\"source\": [\(entry.sourceOffsets.lowerBound), \(entry.sourceOffsets.upperBound)], "
              + "\"canonical\": \(quote(entry.canonical)), "
              + "\"phonemes\": \(quote(entry.phonemes)), "
              + "\"tokens\": [\(entry.tokenIndices.lowerBound), \(entry.tokenIndices.upperBound)]}"
          }.joined(separator: ", "))],
          "boundaries": [\(segments.map { quote("\($0.boundary.map(String.init(describing:)) ?? "end")") }.joined(separator: ", "))],
          "voice": \(quote(voiceName)),
          "mode": "recitation",
          "speed": \(delivery.speed),
          "prosody": {
            "word_boundary": \(delivery.prosody.wordBoundary),
            "pada_pause": \(delivery.prosody.padaPause),
            "verse_pause": \(delivery.prosody.versePause)
          },
          "warnings": [\(analysis.warnings.map { quote($0.text) }.joined(separator: ", "))],
          "approximations": [\(analysis.warnings.filter { $0.text.contains("APPROXIM") || $0.text.contains("UNSUPPORTED") }.map { quote($0.text) }.joined(separator: ", "))],
          "predicted_limitation": \(quote(limitation)),
          "commit": \(quote(commit)),
          "model": "kokoro-v1_0 (hexgrad/Kokoro-82M)",
          "voice_id": \(quote(voiceName)),
          "duration_seconds": \(String(format: "%.3f", seconds))
        }
      """)
    print("WROTE \(name)  \(String(format: "%.2f", seconds))s")
  }

  let json = "{\n  \"entries\": [\n" + entries.joined(separator: ",\n") + "\n  ]\n}\n"
  try json.write(toFile: outputDirectory + "/manifest.json",
                 atomically: true, encoding: .utf8)
  print("MANIFEST \(outputDirectory)/manifest.json")
}
SWIFT

SA_MODEL="$model" SA_VOICES="$voices" SA_VOICE="$voice" SA_OUT="$out" \
SA_COMMIT="$(git rev-parse HEAD)" \
  swift test --filter zzValidate 2>&1 | grep -E "^WROTE|^MANIFEST|^error:|error:"
