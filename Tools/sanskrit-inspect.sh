#!/usr/bin/env bash
# Inspect one Sanskrit word, line or whole verse: every stage of the pipeline,
# and the warnings for anything Kokoro cannot say faithfully.
#
#   Tools/sanskrit-inspect.sh "धर्मक्षेत्रे कुरुक्षेत्रे"
#   Tools/sanskrit-inspect.sh "$(cat verse.txt)"
#
# Prints INPUT, NORMALIZED, AKSHARAS, CANONICAL SANSKRIT, PHONOLOGICAL OUTPUT,
# KOKORO PHONEMES, TOKENS and WARNINGS.
#
# To compare against Vagdhenu, EdgeSanskrit and eSpeak, use
# Tools/sanskrit-reference-compare.py — those are development references and
# are deliberately not part of this tool or of the package.

set -euo pipefail
cd "$(dirname "$0")/.."

[[ $# -ge 1 ]] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

trap 'rm -f Tests/KokoroSwiftTests/ZZSanskritInspect.swift' EXIT

# The text goes through the environment rather than into the generated source.
# A verse spans two lines and may contain quotes; neither survives being pasted
# into a Swift string literal.
cat > Tests/KokoroSwiftTests/ZZSanskritInspect.swift <<'SWIFT'
import Foundation
import Testing
@testable import KokoroSwift

@Test func zzSanskritInspect() throws {
  guard let input = ProcessInfo.processInfo.environment["SA_INPUT"] else { return }
  print("<<<REPORT")
  print(SanskritPhonemizer.inspect(text: input))
  print("REPORT>>>")
}
SWIFT

SA_INPUT="$*" swift test --filter zzSanskritInspect 2>/dev/null \
  | sed -n '/<<<REPORT/,/REPORT>>>/p' | sed '1d;$d'
