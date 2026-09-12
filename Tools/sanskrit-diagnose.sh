#!/usr/bin/env bash
# Full pipeline trace plus tokenizer round-trip audit for a list of words.
#
#   Tools/sanskrit-diagnose.sh words.txt > traces.tsv
#   printf 'क्षेत्रे\nरामः\n' | Tools/sanskrit-diagnose.sh - > traces.tsv
#
# One tab-separated row per word, 15 fields:
#
#   input  normalized  canonical  phonological  kokoro_phonemes
#   symbols  token_ids  decoded  round_trip
#   unknown  dropped  substituted  duplicated
#   boundaries  warnings
#
# `decoded` comes from looking each token id back up in the vocabulary, so a
# symbol the tokenizer drops or changes shows up as a diff rather than as a
# mystery in the audio. See SanskritTokenAudit.

set -euo pipefail
cd "$(dirname "$0")/.."

[[ $# -ge 1 ]] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

input="$1"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"; rm -f Tests/KokoroSwiftTests/ZZDiagnose.swift' EXIT
if [[ "$input" == "-" ]]; then cat > "$scratch/words.txt"; else cp "$input" "$scratch/words.txt"; fi

cat > Tests/KokoroSwiftTests/ZZDiagnose.swift <<'SWIFT'
import Foundation
import Testing
@testable import KokoroSwift

@Test func zzDiagnose() throws {
  guard let path = ProcessInfo.processInfo.environment["SA_WORDS"] else { return }
  print("<<<D")
  for line in try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n") {
    let item = String(line).trimmingCharacters(in: .whitespaces)
    if item.isEmpty || item.hasPrefix("#") { continue }
    let result = SanskritPhonemizer.analyze(item)
    let audit = SanskritTokenAudit.audit(phonemes: result.kokoroPhonemes)

    var boundaries: [String] = []
    for unit in result.units {
      if case let .boundary(boundary) = unit { boundaries.append("\(boundary)") }
    }
    var substitutions: [String] = []
    for change in audit.substituted {
      substitutions.append("\(change.position):\(change.intended)->\(change.decoded)")
    }
    var fields: [String] = []
    fields.append(item)
    fields.append(result.normalized)
    fields.append(result.canonical)
    fields.append(result.phonological)
    fields.append(result.kokoroPhonemes)
    fields.append(audit.symbols.joined(separator: " "))
    fields.append(audit.tokenIDs.map(String.init).joined(separator: " "))
    fields.append(audit.decoded.joined(separator: " "))
    fields.append(audit.roundTrips ? "OK" : "FAILED")
    fields.append(audit.unknown.joined(separator: " "))
    fields.append(audit.dropped.joined(separator: " "))
    fields.append(substitutions.joined(separator: " "))
    fields.append(audit.duplicated.joined(separator: " "))
    fields.append(boundaries.joined(separator: " "))
    fields.append(result.warnings.map(\.text).joined(separator: " | "))
    print(fields.joined(separator: "\t"))
  }
  print("D>>>")
}
SWIFT

SA_WORDS="$scratch/words.txt" swift test --filter zzDiagnose 2>/dev/null \
  | sed -n '/<<<D/,/D>>>/p' | sed '1d;$d'
