#!/usr/bin/env bash
# Inspect one Hindi word or line: our phonemes, espeak's, and where they differ.
#
# espeak is a DEVELOPMENT reference only. It is never a runtime dependency of
# the package, and it is not the target either — see the note at the bottom.
#
#   Tools/hindi-inspect.sh मित्र
#   Tools/hindi-inspect.sh "संसद में संविधान संशोधन पर चर्चा हुई।"
#   Tools/hindi-inspect.sh --alternatives मित्र

set -euo pipefail
cd "$(dirname "$0")/.."

alternatives=false
if [[ "${1:-}" == "--alternatives" ]]; then alternatives=true; shift; fi
[[ $# -ge 1 ]] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
input="$*"

scratch=$(mktemp -d); trap 'rm -rf "$scratch"; rm -f Tests/KokoroSwiftTests/ZZInspect.swift' EXIT

cat > Tests/KokoroSwiftTests/ZZInspect.swift <<SWIFT
import Testing
@testable import KokoroSwift
@Test func zzInspect() throws {
  let input = #"${input}"#
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)
  print("<<<REPORT")
  print(try processor.report(input))
  print("REPORT>>>")
  print("<<<ALTS")
  for word in input.split(whereSeparator: \.isWhitespace) {
    let options = HindiG2PProcessor.alternatives(for: String(word))
    if options.count > 1 {
      print(String(word) + "\t" + options.map { "\(\$0.label)=\(\$0.phonemes)" }.joined(separator: "\t"))
    }
  }
  print("ALTS>>>")
}
SWIFT

swift test --filter zzInspect 2>/dev/null | sed -n '/<<<REPORT/,/REPORT>>>/p' | sed '1d;$d'

echo
echo "ESPEAK REFERENCE (development only)"
for word in $input; do
  printf "  %-20s %s\n" "$word" "$(espeak-ng -v hi -q --ipa "$word" 2>/dev/null | tr -d '\n' | sed 's/^ *//')"
done

if $alternatives; then
  echo
  echo "ALTERNATIVES — synthesize both and listen"
  swift test --filter zzInspect 2>/dev/null | sed -n '/<<<ALTS/,/ALTS>>>/p' | sed '1d;$d' | sed 's/^/  /'
fi

cat <<'NOTE'

  espeak agreement is a diagnostic, not a target. Kokoro's Hindi voices were
  trained on espeak's output, so agreement is evidence about what the model
  has heard — but a change that lowers agreement and sounds better through the
  current voice is still the right change. Decide by listening; use this to
  understand what changed and why.
NOTE
