#!/usr/bin/env bash
# Controlled A/B for experimental acoustic mappings.
#
#   Tools/sanskrit-acoustic-ab.sh --model <m> --voices <dir> [--out <dir>]
#
# Everything is held constant except the one canonical phoneme a profile
# overrides: same voice, speed, text, pauses and prosody. Writes baseline.wav
# and candidate_NN.wav per word plus a manifest recording both mappings, the
# tokens, the round-trip status and the claimed mapping quality.
#
# Nothing here changes production. The baseline profile carries no overrides,
# so baseline.wav is what the shipped mapper produces.

set -euo pipefail
cd "$(dirname "$0")/.."
model=""; voices=""; voice="hf_alpha"; out="Artifacts/sanskrit/acoustic-mapping-v1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --voices) voices="$2"; shift 2 ;;
    --voice) voice="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
[[ -n "$model" && -n "$voices" ]] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
trap 'rm -f Tests/KokoroSwiftTests/ZZAcousticAB.swift' EXIT

cat > Tests/KokoroSwiftTests/ZZAcousticAB.swift <<'SWIFT'
import Foundation
import MLX
import Testing
@testable import KokoroSwift

@Test func zzAcousticAB() throws {
  let env = ProcessInfo.processInfo.environment
  guard let modelPath = env["SA_MODEL"], let voiceDirectory = env["SA_VOICES"],
        let voiceName = env["SA_VOICE"], let root = env["SA_OUT"],
        let commit = env["SA_COMMIT"] else { return }
  let tts = try KokoroTTS(modelPath: URL(fileURLWithPath: modelPath), g2p: .sanskrit)
  guard let voice = try MLX.loadArrays(
    url: URL(fileURLWithPath: voiceDirectory).appendingPathComponent("\(voiceName).safetensors")
  )["voice"] else { return }
  let sampleRate = Double(KokoroTTS.Constants.samplingRate)
  let speed: Float = 0.80

  // (folder, words, candidate profiles). Baseline is always profile zero.
  let groups: [(String, [String], [SanskritAcousticMappingProfile])] = [
    ("vocalic-r", ["ऋ", "कृ", "कृत", "कृष्ण", "सृ", "सृजति", "सृजाम्यहम्",
                   "हृषीकेश", "वृत्ति", "प्रकृति", "पृथ्वी", "मृत्यु"],
     [.vocalicRAsRhoticVowel, .vocalicRAsRu]),
    ("e-vowel", ["के", "की", "ते", "ती", "मे", "मी", "से", "सी",
                 "क्षेत्रे", "क्षेत्री", "समवेता", "समवीता", "फलेषु", "फलीषु"],
     [.eAsOpenMid]),
    ("visarga", ["कः", "रामः", "योगः", "युयुत्सवः", "मामकाः", "पाण्डवाः", "नमः", "दुःख"],
     [.visargaAsPalatalFricative]),
    ("retroflex-sibilant", ["शक्ति", "शास्त्र", "श्रद्धा", "षट्", "कृष्ण",
                            "क्षेत्र", "फलेषु", "सत्", "सम", "सञ्जय"],
     [.shaAsAlveoloPalatal]),
    ("palatal-nasal", ["सञ्जय", "अञ्जलि", "पञ्च", "चञ्चल", "ज्ञान", "विज्ञान", "यज्ञ"], []),
    ("velar-nasal", ["अङ्ग", "सङ्ग", "गङ्गा", "सङ्गोऽस्तु"], []),
    ("aspirated-clusters", ["अभ्युत्थानम्", "ग्लानिर्भवति", "हेतुर्भूर्मा",
                            "धर्मक्षेत्रे", "भक्त्या", "श्रद्धा"], []),
    ("final-closures", ["अहम्", "भगवान्", "तत्", "कृत्", "ब्रह्मन्", "कदाचित्"], []),
  ]

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

  for (folder, words, candidates) in groups {
    var entries: [String] = []
    let directory = root + "/" + folder
    for word in words {
      let profiles: [(String, SanskritAcousticMappingProfile)] =
        [("baseline", .baseline)]
        + candidates.enumerated().map { (String(format: "candidate_%02d", $0.offset + 1), $0.element) }
      for (tag, profile) in profiles {
        var options = SanskritOptions.default
        options.acousticProfile = profile
        let result = SanskritPhonemizer.analyze(word, options: options)
        let baseline = SanskritPhonemizer.analyze(word)
        let audit = SanskritTokenAudit.audit(phonemes: result.kokoroPhonemes)
        let name = "\(folder)_\(words.firstIndex(of: word)!)_\(tag).wav"
        let audio = try tts.generateAudio(
          voice: voice, phonemes: result.kokoroPhonemes, speed: speed
        )
        try AudioUtils.writeWavFile(samples: audio, sampleRate: sampleRate,
          fileURL: URL(fileURLWithPath: directory).appendingPathComponent(name))
        let quality = profile.quality.values.first.map { "\($0)" } ?? "exact"
        let changed = result.kokoroPhonemes == baseline.kokoroPhonemes
          ? "(none)" : "\(profile.vowels.keys.map { "\($0)" } + profile.consonants.keys.map { "\($0)" })"
        entries.append("""
            {
              "source": \(quote(word)),
              "profile": \(quote(profile.name)),
              "canonical": \(quote(result.canonical)),
              "canonical_matches_baseline": \(result.canonical == baseline.canonical),
              "baseline_mapping": \(quote(baseline.kokoroPhonemes)),
              "candidate_mapping": \(quote(result.kokoroPhonemes)),
              "changed_phoneme_only": \(quote(changed)),
              "token_ids": [\(audit.tokenIDs.map(String.init).joined(separator: ", "))],
              "decoded_tokens": [\(audit.decoded.map { quote($0) }.joined(separator: ", "))],
              "round_trip_ok": \(audit.roundTrips),
              "mapping_quality": \(quote(quality)),
              "warnings": [\(result.warnings.map { quote($0.text) }.joined(separator: ", "))],
              "voice": \(quote(voiceName)),
              "speed": \(speed),
              "model": "kokoro-v1_0 (hexgrad/Kokoro-82M)",
              "duration_seconds": \(String(format: "%.3f", Double(audio.count) / sampleRate)),
              "commit": \(quote(commit)),
              "output_path": \(quote(folder + "/" + name))
            }
          """)
      }
    }
    try ("{\n  \"entries\": [\n" + entries.joined(separator: ",\n") + "\n  ]\n}\n")
      .write(toFile: directory + "/manifest.json", atomically: true, encoding: .utf8)
    print("GROUP \(folder): \(entries.count) files")
  }
}
SWIFT

SA_MODEL="$model" SA_VOICES="$voices" SA_VOICE="$voice" SA_OUT="$out" \
SA_COMMIT="$(git rev-parse HEAD)" \
  swift test --filter zzAcousticAB 2>&1 | grep -E "^GROUP|error:"
