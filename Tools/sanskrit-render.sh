#!/usr/bin/env bash
# Synthesize the three Bhagavad Gita verses, once per voice, for listening.
#
#   Tools/sanskrit-render.sh --model <kokoro.safetensors> --voices <dir> [--out Artifacts/sanskrit]
#
# These files are for human review of Gate 3 — whether the current voices can
# render correct Sanskrit phonemes acceptably. None of the voices has ever
# heard Sanskrit, so a poor result is evidence about the acoustic model, not a
# reason to change the phonemizer. See docs/SANSKRIT.md.
#
# Preparing the inputs, if you do not have them as safetensors already:
#
#   # model: hexgrad/Kokoro-82M kokoro-v1_0.pth -> safetensors, keys flattened
#   python3 - <<'PY'
#   import torch; from safetensors.torch import save_file
#   d = torch.load("kokoro-v1_0.pth", map_location="cpu", weights_only=True)
#   save_file({f"{c}.{k.removeprefix('module.')}": t.contiguous().float()
#              for c, sub in d.items() for k, t in sub.items()}, "kokoro.safetensors")
#   PY
#
#   # voices: any Kokoro [510, 1, 256] voicepack
#   python3 Tools/voicepack-to-mlx.py --input hf_alpha.pt --output voices/hf_alpha.safetensors

set -euo pipefail
cd "$(dirname "$0")/.."

model=""; voices=""; out="Artifacts/sanskrit"
# The voice also written under the plain bg_NN_NN.wav names. hf_alpha is the
# default because the Hindi packs are the closest match to Sanskrit's phoneme
# inventory — retroflexes and aspirates are the ones they actually heard in
# training. That is a starting point for listening, not a verdict.
primary="hf_alpha"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)   model="$2"; shift 2 ;;
    --voices)  voices="$2"; shift 2 ;;
    --out)     out="$2"; shift 2 ;;
    --primary) primary="$2"; shift 2 ;;
    *) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
[[ -n "$model" && -n "$voices" ]] || { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

mkdir -p "$out"
trap 'rm -f Tests/KokoroSwiftTests/ZZSanskritRender.swift' EXIT

cat > Tests/KokoroSwiftTests/ZZSanskritRender.swift <<'SWIFT'
import Foundation
import MLX
import Testing
@testable import KokoroSwift

@Test func zzSanskritRender() throws {
  let environment = ProcessInfo.processInfo.environment
  guard let modelPath = environment["SA_MODEL"],
        let voiceDirectory = environment["SA_VOICES"],
        let outputDirectory = environment["SA_OUT"]
  else { return }

  // The three verses from §36 of the brief. Each is one shloka, which fits
  // Kokoro's context, so no verse is split mid-line.
  let verses: [(name: String, text: String)] = [
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

  let tts = try KokoroTTS(modelPath: URL(fileURLWithPath: modelPath), g2p: .sanskrit)
  let voiceFiles = try FileManager.default
    .contentsOfDirectory(atPath: voiceDirectory)
    .filter { $0.hasSuffix(".safetensors") }
    .sorted()

  for file in voiceFiles {
    let name = String(file.dropLast(".safetensors".count))
    let url = URL(fileURLWithPath: voiceDirectory).appendingPathComponent(file)
    guard let voice = try MLX.loadArrays(url: url)["voice"] else {
      print("SKIP \(name): no 'voice' array")
      continue
    }
    for verse in verses {
      // Recitation pace. The speed divides the predicted durations before the
      // decoder runs, so the model genuinely articulates slowly — this is not
      // a slowed-down render of a normal one.
      for (suffix, speed) in [("", Float(1.0)), ("_slow", Float(0.7))] {
        let (samples, _) = try tts.generateAudio(
          voice: voice, language: .sa, text: verse.text, speed: speed
        )
        let output = URL(fileURLWithPath: outputDirectory)
          .appendingPathComponent("\(verse.name)_\(name)\(suffix).wav")
        try AudioUtils.writeWavFile(
          samples: samples,
          sampleRate: Double(KokoroTTS.Constants.samplingRate),
          fileURL: output
        )
        let seconds = Double(samples.count) / Double(KokoroTTS.Constants.samplingRate)
        print(String(format: "WROTE %@  %.2fs", output.lastPathComponent, seconds))
      }
    }
  }
}
SWIFT

SA_MODEL="$model" SA_VOICES="$voices" SA_OUT="$out" \
  swift test --filter zzSanskritRender 2>&1 | grep -E "^WROTE|^SKIP|error:"

# The three names §36 of the brief asks for, from the primary voice. The
# per-voice files stay alongside them for comparison.
for verse in bg_01_01 bg_02_47 bg_04_07; do
  source_file="$out/${verse}_${primary}.wav"
  if [[ -f "$source_file" ]]; then
    cp "$source_file" "$out/$verse.wav"
    echo "PRIMARY $verse.wav  <- $primary"
  else
    echo "MISSING $source_file — no primary copy for $verse" >&2
  fi
done
