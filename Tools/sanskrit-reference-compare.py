#!/usr/bin/env python3
"""Compare our Sanskrit front end against the reference implementations.

DEVELOPMENT ONLY. Nothing in the Swift package imports this, and none of the
references is a runtime dependency. The tool exists so a disagreement can be
looked at rather than guessed at.

The references are not vendored — they are cloned locally and pointed at, so
this repository carries no third-party source. See docs/SANSKRIT_SOURCES.md.

    # one-time setup
    python3 -m venv /tmp/refvenv && /tmp/refvenv/bin/pip install indic_transliteration
    git clone https://github.com/prathoshap/vagdhenu          /tmp/refs/vagdhenu
    git clone https://github.com/Hariprajwal/EdgeSanskrit-TTS /tmp/refs/EdgeSanskrit-TTS

    # run
    Tools/sanskrit-reference-compare.py --refs /tmp/refs "धर्मक्षेत्रे कुरुक्षेत्रे"
    Tools/sanskrit-reference-compare.py --refs /tmp/refs --corpus Tools/sanskrit-listening-corpus.txt
    Tools/sanskrit-reference-compare.py --refs /tmp/refs --corpus ... --tsv > refs.tsv

Columns, when a reference is available:

    vagdhenu_norm   Vagdhenu's normalized Devanagari  (tts_normalize.normalize)
    vagdhenu_slp1   Vagdhenu's canonical SLP1         (tts_g2p.to_slp1)
    edge_ipa        EdgeSanskrit's IPA                (devanagari_to_ipa)
    espeak_hi       espeak-ng Hindi IPA               — a PROXY, see below

espeak-ng 1.52 has NO Sanskrit voice. `-v sa` errors out; the Indic voices are
hi, mr, ne, sd, and the rest. Hindi is printed as the nearest available
reference, and it applies Hindi schwa deletion, so it is expected to differ
from correct Sanskrit on almost every word. It is a coverage check, not a
target.
"""
import argparse
import subprocess
import sys
from pathlib import Path


def load_vagdhenu(refs: Path):
    """tts_normalize.normalize and tts_g2p.to_slp1, or (None, None)."""
    src = refs / "vagdhenu" / "src"
    if not src.is_dir():
        return None, None
    sys.path.insert(0, str(src))
    try:
        from tts_normalize import normalize
        from tts_g2p import to_slp1
        return normalize, to_slp1
    except ImportError as error:
        print(f"# vagdhenu unavailable: {error}", file=sys.stderr)
        return None, None


def load_edge(refs: Path):
    """EdgeSanskrit's devanagari_to_ipa, or None."""
    root = refs / "EdgeSanskrit-TTS"
    if not root.is_dir():
        return None
    sys.path.insert(0, str(root))
    try:
        from sanskrit_phonemizer import devanagari_to_ipa
        return devanagari_to_ipa
    except ImportError as error:
        print(f"# EdgeSanskrit unavailable: {error}", file=sys.stderr)
        return None


def espeak_hindi(text: str) -> str:
    """espeak-ng Hindi IPA. A proxy: there is no Sanskrit voice."""
    try:
        out = subprocess.run(
            ["espeak-ng", "-v", "hi", "-q", "--ipa", text],
            capture_output=True, text=True, timeout=20,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""
    return " ".join(out.stdout.split())


def corpus_lines(path: Path):
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            yield line


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("text", nargs="*", help="Devanagari to compare")
    parser.add_argument("--refs", type=Path, default=Path("/tmp/refs"),
                        help="directory holding the reference clones")
    parser.add_argument("--corpus", type=Path, help="read items from a corpus file")
    parser.add_argument("--tsv", action="store_true", help="tab-separated instead of blocks")
    arguments = parser.parse_args()

    if arguments.corpus:
        items = list(corpus_lines(arguments.corpus))
    elif arguments.text:
        items = [" ".join(arguments.text)]
    else:
        parser.error("give text or --corpus")

    normalize, to_slp1 = load_vagdhenu(arguments.refs)
    edge = load_edge(arguments.refs)

    if arguments.tsv:
        print("\t".join(["input", "vagdhenu_norm", "vagdhenu_slp1", "edge_ipa", "espeak_hi"]))

    for item in items:
        normalized = normalize(item) if normalize else ""
        slp1 = to_slp1(normalized) if to_slp1 and normalized else ""
        edge_ipa = edge(item) if edge else ""
        espeak = espeak_hindi(item)

        if arguments.tsv:
            print("\t".join([item, normalized, slp1, edge_ipa, espeak]))
            continue

        print(f"INPUT           {item}")
        if normalized:
            print(f"  vagdhenu_norm {normalized}")
            print(f"  vagdhenu_slp1 {slp1}")
        if edge_ipa:
            print(f"  edge_ipa      {edge_ipa}")
        if espeak:
            print(f"  espeak_hi     {espeak}   (PROXY — no Sanskrit voice exists)")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
