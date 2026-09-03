#!/usr/bin/env bash
# Synthesize controlled minimal pairs and phoneme-isolation contexts, so a
# claim about what the acoustic model does with a phoneme can be measured
# instead of asserted.
#
#   Tools/sanskrit-minimal-pairs.sh --model <kokoro.safetensors> --voices <dir> \
#       --spec <spec.tsv> --out <dir> [--voice-filter hf_alpha] [--speeds "1.0 0.75"]
#
# The spec is a TSV of:  id <tab> kind <tab> value
#   kind = deva      value is Devanagari, run through the full Sanskrit G2P
#   kind = phonemes  value is an IPA string sent straight to the model
#
# The `phonemes` kind exists because comparing two phoneme sequences fairly —
# `keː` against `kiː`, or the same sequence with and without a stress mark —
# needs everything except the phonemes held identical, which text input cannot
# give you. It uses a diagnostic entry point on KokoroTTS and is not part of
# the synthesis path.
#
# Writes one wav per (id, voice, speed) plus manifest.tsv.

set -euo pipefail
cd "$(dirname "$0")/.."

model=""; voices=""; spec=""; out=""; filter=""; speeds="1.0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)        model="$2"; shift 2 ;;
    --voices)       voices="$2"; shift 2 ;;
    --spec)         spec="$2"; shift 2 ;;
    --out)          out="$2"; shift 2 ;;
    --voice-filter) filter="$2"; shift 2 ;;
    --speeds)       speeds="$2"; shift 2 ;;
    *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
[[ -n "$model" && -n "$voices" && -n "$spec" && -n "$out" ]] || {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

mkdir -p "$out"
trap 'rm -f Tests/KokoroSwiftTests/ZZMinimalPairs.swift' EXIT

cat > Tests/KokoroSwiftTests/ZZMinimalPairs.swift <<'SWIFT'
import Foundation
import MLX
import Testing
@testable import KokoroSwift

@Test func zzMinimalPairs() throws {
  let environment = ProcessInfo.processInfo.environment
  guard let modelPath = environment["SA_MODEL"],
        let voiceDirectory = environment["SA_VOICES"],
        let specPath = environment["SA_SPEC"],
        let outputDirectory = environment["SA_OUT"]
  else { return }
  let filter = environment["SA_VOICE_FILTER"] ?? ""
  let speeds = (environment["SA_SPEEDS"] ?? "1.0")
    .split(whereSeparator: \.isWhitespace).compactMap { Float($0) }

  let tts = try KokoroTTS(modelPath: URL(fileURLWithPath: modelPath), g2p: .sanskrit)
  var voices: [(String, MLXArray)] = []
  for file in try FileManager.default.contentsOfDirectory(atPath: voiceDirectory).sorted()
  where file.hasSuffix(".safetensors") {
    let name = String(file.dropLast(".safetensors".count))
    if !filter.isEmpty, !filter.split(separator: ",").contains(where: { name == $0 }) { continue }
    let url = URL(fileURLWithPath: voiceDirectory).appendingPathComponent(file)
    if let voice = try MLX.loadArrays(url: url)["voice"] { voices.append((name, voice)) }
  }

  var rows = ["filename\tid\tinput\tcanonical\tdesired_ipa\tkokoro_phonemes\ttoken_ids\tvoice\tspeed\twarnings"]

  for line in try String(contentsOfFile: specPath, encoding: .utf8).split(separator: "\n") {
    let columns = line.components(separatedBy: "\t")
    guard columns.count >= 3, !columns[0].hasPrefix("#") else { continue }
    let (identifier, kind, value) = (columns[0], columns[1], columns[2])

    let phonemes: String
    let canonical: String
    let warnings: String
    if kind == "deva" {
      let result = SanskritPhonemizer.analyze(value)
      phonemes = result.kokoroPhonemes
      canonical = result.canonical
      warnings = result.warnings.map(\.text).joined(separator: " | ")
    } else {
      phonemes = value
      canonical = "(raw phonemes)"
      warnings = ""
    }
    let audit = SanskritTokenAudit.audit(phonemes: phonemes)
    let tokens = audit.tokenIDs.map(String.init).joined(separator: " ")

    for (voiceName, voice) in voices {
      for speed in speeds {
        let speedTag = speed == 1.0 ? "" : String(format: "_s%.2f", speed)
        let name = "\(identifier)_\(voiceName)\(speedTag).wav"
        let samples = try tts.generateAudio(voice: voice, phonemes: phonemes, speed: speed)
        try AudioUtils.writeWavFile(
          samples: samples,
          sampleRate: Double(KokoroTTS.Constants.samplingRate),
          fileURL: URL(fileURLWithPath: outputDirectory).appendingPathComponent(name)
        )
        rows.append([name, identifier, value, canonical, phonemes, phonemes, tokens,
                     voiceName, String(speed), warnings].joined(separator: "\t"))
        print("WROTE \(name)")
      }
    }
  }

  try rows.joined(separator: "\n").write(
    toFile: outputDirectory + "/manifest.tsv", atomically: true, encoding: .utf8
  )
  print("MANIFEST \(outputDirectory)/manifest.tsv")
}
SWIFT

SA_MODEL="$model" SA_VOICES="$voices" SA_SPEC="$spec" SA_OUT="$out" \
SA_VOICE_FILTER="$filter" SA_SPEEDS="$speeds" \
  swift test --filter zzMinimalPairs 2>&1 | grep -E "^WROTE|^MANIFEST|error:"
