#!/usr/bin/env python3
"""Diff this package's Hindi phonemizer against espeak-ng.

Kokoro's Hindi voices were trained on espeak-ng's output, so espeak is the
target distribution regardless of what is more phonetically correct. This
reports where we diverge from it, grouped by kind, so the divergences worth
fixing can be picked out from the ones that are espeak artifacts.

Usage:
    swift test --filter dumpHindiPhonemesForEspeakDiff   # writes ours.tsv
    python3 Tools/espeak-diff.py ours.tsv
"""
import subprocess
import sys
import unicodedata
from collections import Counter

STRESS = "ˈˌ"  # primary, secondary


def espeak(word):
    out = subprocess.run(
        ["espeak-ng", "-v", "hi", "-q", "--ipa", word],
        capture_output=True, text=True,
    )
    return out.stdout.strip().replace("\n", "")


def strip_stress(s):
    return "".join(c for c in s if c not in STRESS)


def stress_shape(s):
    """Positions of stress marks relative to the stress-free string."""
    shape, offset = [], 0
    for c in s:
        if c in STRESS:
            shape.append((offset, c))
        else:
            offset += 1
    return tuple(shape)


def classify(word, ours, theirs):
    if ours == theirs:
        return "identical"
    if "r." in theirs:
        # espeak's IPA table has no mapping for the retroflex flap and leaks
        # its internal mnemonic. Not a divergence we would want to copy.
        return "espeak-flap-artifact"
    if strip_stress(ours) == strip_stress(theirs):
        return "stress-only"
    if strip_stress(ours).replace("ː", "") == strip_stress(theirs).replace("ː", ""):
        return "vowel-length-only"
    return "segmental"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    rows = []
    with open(sys.argv[1], encoding="utf-8") as fh:
        for line in fh:
            if "\t" not in line:
                continue
            word, ours = line.rstrip("\n").split("\t", 1)
            rows.append((word, ours, espeak(word)))

    counts = Counter(classify(w, o, t) for w, o, t in rows)
    total = len(rows)
    print(f"corpus: {total} words\n")
    for kind, n in counts.most_common():
        print(f"  {kind:24s} {n:4d}  {100.0 * n / total:5.1f}%")

    print("\n--- stress-only divergences ---")
    shown = 0
    for w, o, t in rows:
        if classify(w, o, t) == "stress-only":
            print(f"  {w:20s} ours={o:28s} espeak={t}")
            shown += 1
            if shown >= 25:
                print("  ...")
                break

    print("\n--- segmental divergences ---")
    shown = 0
    for w, o, t in rows:
        if classify(w, o, t) == "segmental":
            print(f"  {w:20s} ours={o:28s} espeak={t}")
            shown += 1
            if shown >= 30:
                print("  ...")
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
