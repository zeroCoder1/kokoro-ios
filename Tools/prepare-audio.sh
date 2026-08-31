#!/usr/bin/env bash
# Converts a corpus to the audio format Kokoro fine-tuning requires, and
# reports anything the trainer would choke on.
#
# The recipe wants WAV, mono, 24 kHz, 16-bit, clips of 2-30 seconds. Indic-TTS
# ships 48 kHz studio recordings, so everything needs resampling. Clips outside
# the duration window are reported rather than converted: a clip that is too
# long wastes context, and one that is too short is usually a bad segmentation
# that will hurt alignment.
#
# Usage:
#   Tools/prepare-audio.sh <source-dir> <output-dir>
#
# Reads every .wav under <source-dir>, writes converted files to <output-dir>,
# and leaves a report at <output-dir>/../prepare-audio-report.tsv

set -euo pipefail

if [[ $# -lt 2 ]]; then
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

source_dir="${1%/}"
output_dir="${2%/}"
report="$(dirname "$output_dir")/prepare-audio-report.tsv"

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "ffprobe not found (brew install ffmpeg)" >&2; exit 1; }
[[ -d "$source_dir" ]] || { echo "no such directory: $source_dir" >&2; exit 1; }

mkdir -p "$output_dir"
printf 'clip\tstatus\tdetail\n' > "$report"

min_seconds=2
max_seconds=30
converted=0; too_short=0; too_long=0; unreadable=0

while IFS= read -r input; do
  clip="$(basename "${input%.*}")"

  duration="$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$input" 2>/dev/null || true)"
  if [[ -z "$duration" || "$duration" == "N/A" ]]; then
    printf '%s\tunreadable\t\n' "$clip" >> "$report"
    unreadable=$((unreadable + 1))
    continue
  fi

  # Duration gates. Reported, not converted, so the manifest never points at
  # a clip the trainer will reject or that will drag alignment down.
  if awk "BEGIN{exit !($duration < $min_seconds)}"; then
    printf '%s\ttoo_short\t%ss\n' "$clip" "$duration" >> "$report"
    too_short=$((too_short + 1))
    continue
  fi
  if awk "BEGIN{exit !($duration > $max_seconds)}"; then
    printf '%s\ttoo_long\t%ss\n' "$clip" "$duration" >> "$report"
    too_long=$((too_long + 1))
    continue
  fi

  # -ac 1 mono, -ar 24000 resample, pcm_s16le 16-bit.
  ffmpeg -nostdin -v error -y -i "$input" \
    -ac 1 -ar 24000 -c:a pcm_s16le "$output_dir/$clip.wav"
  printf '%s\tok\t%ss\n' "$clip" "$duration" >> "$report"
  converted=$((converted + 1))
done < <(find "$source_dir" -type f -name '*.wav' | sort)

total=$((converted + too_short + too_long + unreadable))
cat <<SUMMARY

read       $total
converted  $converted  -> $output_dir
too_short  $too_short  (under ${min_seconds}s)
too_long   $too_long  (over ${max_seconds}s)
unreadable $unreadable

report     $report
SUMMARY

if [[ $converted -eq 0 ]]; then
  echo "Nothing was converted. Check that $source_dir contains .wav files." >&2
  exit 1
fi
