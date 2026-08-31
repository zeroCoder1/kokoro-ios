#!/usr/bin/env python3
"""Turn the IndicTTS-Hindi HuggingFace dataset into training-ready clips.

The dataset ships as parquet with the audio embedded, one row per utterance,
at 48 kHz. Kokoro fine-tuning wants loose WAV files at 24 kHz mono 16-bit plus
a transcript file, split per speaker. This does that in one pass.

It streams by default, so the 8.2 GB of parquet is never all on disk at once —
which matters on a laptop with 19 GB free. The written clips come to about
1.8 GB for the whole corpus.

Output, per speaker:

    <out>/hi_female/wav/hi_female_00001.wav
    <out>/hi_female/txt.done.data
    <out>/hi_male/wav/...
    <out>/hi_male/txt.done.data

The transcript file is Festival format, which `swift run kokoro-labels` reads.

The dataset is licence-gated. Accept the terms at
https://huggingface.co/datasets/SPRINGLab/IndicTTS-Hindi and run
`huggingface-cli login` first.

    python3 Tools/extract-indictts.py --out /data/indictts
    python3 Tools/extract-indictts.py --out /data/indictts --survey
"""
import argparse
import collections
import os
import sys

TARGET_RATE = 24000
DATASET = "SPRINGLab/IndicTTS-Hindi"


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", required=True, help="output directory")
    p.add_argument("--min-seconds", type=float, default=2.0,
                   help="skip clips shorter than this (default 2.0)")
    p.add_argument("--max-seconds", type=float, default=30.0,
                   help="skip clips longer than this (default 30.0)")
    p.add_argument("--limit", type=int, default=0,
                   help="stop after N rows, for a trial run")
    p.add_argument("--survey", action="store_true",
                   help="report the duration distribution and write nothing")
    p.add_argument("--no-stream", action="store_true",
                   help="download the dataset fully instead of streaming")
    return p.parse_args()


def histogram(durations):
    """Duration spread, so the length thresholds are chosen from the data
    rather than guessed. Short clips are the risk here: the corpus averages
    around three seconds, so a 2 s floor may discard a real share of it."""
    buckets = [(0, 1), (1, 2), (2, 3), (3, 5), (5, 10), (10, 20), (20, 30), (30, 1e9)]
    counts = collections.Counter()
    for d in durations:
        for low, high in buckets:
            if low <= d < high:
                counts[(low, high)] += 1
                break
    total = len(durations) or 1
    lines = ["", "duration        clips      share    cumulative"]
    running = 0
    for low, high in buckets:
        n = counts[(low, high)]
        running += n
        label = f"{low:g}-{high:g}s" if high < 1e9 else f"{low:g}s+"
        lines.append(f"  {label:<12} {n:6d}  {100.0*n/total:7.1f}%  {100.0*running/total:9.1f}%")
    lines.append(f"  {'total':<12} {total:6d}")
    hours = sum(durations) / 3600.0
    lines.append(f"  {'hours':<12} {hours:6.2f}")
    return "\n".join(lines)


def main():
    args = parse_args()
    try:
        import io as _io
        import numpy as np
        import soundfile as sf
        import soxr
        from datasets import Audio, load_dataset
    except ImportError as exc:
        sys.exit(f"missing dependency: {exc}\n"
                 f"  uv pip install datasets soundfile soxr huggingface_hub")

    print(f"opening {DATASET} (streaming={not args.no_stream})")
    try:
        data = load_dataset(DATASET, split="train", streaming=not args.no_stream)
    except Exception as exc:
        sys.exit(f"could not open the dataset: {exc}\n\n"
                 f"This dataset is licence-gated. Accept the terms at\n"
                 f"  https://huggingface.co/datasets/{DATASET}\n"
                 f"then authenticate with `huggingface-cli login`.")

    # Hand back the encoded bytes rather than a decoded array. datasets 5.x
    # decodes audio through torchcodec, which drags in the whole of PyTorch for
    # a job soundfile already does.
    data = data.cast_column("audio", Audio(decode=False))

    counters = collections.Counter()
    durations = []
    transcripts = collections.defaultdict(list)
    per_speaker = collections.Counter()

    for index, row in enumerate(data):
        if args.limit and index >= args.limit:
            break

        encoded = row["audio"]["bytes"]
        try:
            samples, rate = sf.read(_io.BytesIO(encoded), dtype="float32", always_2d=False)
        except Exception:
            counters["unreadable"] += 1
            continue
        if samples.ndim > 1:                      # fold any stereo to mono
            samples = samples.mean(axis=1)
        rate = int(rate)
        seconds = len(samples) / rate if rate else 0.0
        durations.append(seconds)

        text = (row.get("text") or "").strip()
        gender = str(row.get("gender", "")).strip().lower()
        speaker = "hi_male" if gender.startswith("m") or gender == "1" else "hi_female"

        if args.survey:
            counters["surveyed"] += 1
            if index % 2000 == 0 and index:
                print(f"  {index} rows...")
            continue

        if not text:
            counters["no_transcript"] += 1
            continue
        if seconds < args.min_seconds:
            counters["too_short"] += 1
            continue
        if seconds > args.max_seconds:
            counters["too_long"] += 1
            continue

        per_speaker[speaker] += 1
        clip = f"{speaker}_{per_speaker[speaker]:05d}"
        wav_dir = os.path.join(args.out, speaker, "wav")
        os.makedirs(wav_dir, exist_ok=True)

        if rate != TARGET_RATE:
            samples = soxr.resample(samples, rate, TARGET_RATE)
        # PCM_16 is what the trainer expects; float input is scaled on write.
        sf.write(os.path.join(wav_dir, clip + ".wav"), samples, TARGET_RATE, subtype="PCM_16")

        # Festival layout, which kokoro-labels reads. Quotes in the transcript
        # would break the parse, so they are dropped rather than escaped.
        transcripts[speaker].append(f'( {clip} "{text.replace(chr(34), "")}" )')
        counters["written"] += 1
        if counters["written"] % 500 == 0:
            print(f"  {counters['written']} clips written...")

    print(histogram(durations))

    if args.survey:
        print("\nsurvey only, nothing written.")
        print("Choose --min-seconds from the table above before extracting.")
        return

    for speaker, lines in transcripts.items():
        path = os.path.join(args.out, speaker, "txt.done.data")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
        print(f"\n{speaker}: {len(lines)} clips -> {path}")

    print("\nwritten     %d" % counters["written"])
    for reason in ("too_short", "too_long", "no_transcript", "unreadable"):
        if counters[reason]:
            print(f"skipped     {counters[reason]}  ({reason})")
    if counters["written"]:
        print("\nNext: build the manifests with")
        for speaker in sorted(transcripts):
            print(f"  swift run kokoro-labels --transcripts {args.out}/{speaker}/txt.done.data \\\n"
                  f"    --audio-dir {args.out}/{speaker}/wav --speaker {speaker} \\\n"
                  f"    --output {speaker}.txt --rejections {speaker}_rejected.tsv")


if __name__ == "__main__":
    main()
