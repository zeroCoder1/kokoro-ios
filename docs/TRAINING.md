# Fine-tuning Kokoro for better Hindi voices

The bundled Hindi voices are all Grade C, each trained on 10–100 minutes of
audio. The English voices that sound good sit at 10–100 *hours*. That gap is
the reason Hindi sounds the way it does, and no amount of work in this Swift
package closes it — it is a training problem.

This is the path from here to two better Hindi voices, male and female.

**You do not need a GPU of your own.** Option B below needs no GPU at all;
Option A needs one only for the training run, rented and then deleted.

---

## First decide: may English change?

Kokoro shares one set of weights across every language — `bert`,
`bert_encoder`, `predictor`, `text_encoder`, `decoder`. There is no Hindi-only
subnetwork, so fine-tuning on Hindi moves the weights English depends on. That
cannot be avoided, only measured afterwards.

If English must not degrade, that rules out fine-tuning a single shared model,
and leaves two options that guarantee it:

### Option B — a new voice pack, weights untouched

Fit a new Hindi style vector against the existing model. English is unchanged
because the model is unchanged: the same file, byte for byte.

- No GPU. `extract_voicepack.py` is pure inference and takes `--device cpu`
- One model file, no app changes
- Uses only a few hundred clips, so the corpus can be small

The ceiling is lower: it improves the speaker identity and how prosody is
conditioned, not the base model's grasp of Hindi phonemes. But it costs almost
nothing and it answers a question you cannot otherwise answer — how much of the
gap is the voice pack, and how much is the model underneath.

**Start here.**

### Option A — fine-tune, and ship two model files

If B is not enough: fine-tune on Hindi, and keep the original weights for
English. English stays bit-identical because it uses a different file.

The costs are real — roughly double the model payload, and an app change, since
today one `KokoroTTS` serves both languages while two models means two
instances or a reload on language switch.

If you get here, decide by measuring rather than assuming: run a fixed English
set through both checkpoints and compare. Ship one model if English holds, two
if it does not.

Phases 1 and 5 are shared. Phases 2–4 are Option A only.

---

## What this costs

Kokoro's *entire* original training was about 500 GPU-hours, roughly $400. A
single-language fine-tune is a fraction of that. Renting a suitable GPU runs
about $0.20–0.80/hour, so the training itself is likely $10–40.

The real cost is your time on data preparation. Budget days, not hours, and
expect most of it to be checking that transcripts match audio.

---

## The one idea worth understanding first

Kokoro's Hindi was trained on **espeak-ng's** phoneme output. That is why this
package chases espeak rather than being "more correct" — the model only
understands what it was trained on. espeak's Hindi has real defects: it emits
its internal mnemonic `r.` for the retroflex flap in ड़ and ढ़, and it disagrees
with this package's phonemizer on roughly half of common words.

**Fine-tuning inverts that.** You produce the labels, so the model learns *this
package's* phonemes. The espeak defects stop existing rather than being worked
around. That is the main reason to do this beyond simply having more data.

Which is why step 1 uses `kokoro-labels` instead of the recipe's espeak step.

---

## Phase 1 — On your Mac, free

### 1.1 Read the licence first

The corpus is IIT Madras' Indic TTS database. Using it means agreeing to the
**License For Use of Indic TTS** — read it before you build anything you intend
to ship, not after. The terms are the deciding factor for a commercial product,
and no amount of engineering downstream changes them.

- Dataset: [SPRINGLab/IndicTTS-Hindi](https://huggingface.co/datasets/SPRINGLab/IndicTTS-Hindi)
  (the Hindi monolingual portion, ~10 h, one male and one female speaker)
- Original: [IIT Madras Indic TTS database](https://www.iitm.ac.in/donlab/indictts/database)

### 1.2 Extract and convert in one pass

The HuggingFace copy is parquet with the audio embedded at 48 kHz. This streams
it, resamples to 24 kHz mono 16-bit, splits by speaker, and writes the Festival
transcript file that `kokoro-labels` reads:

```bash
uv venv .venv --python 3.11
VIRTUAL_ENV=.venv uv pip install datasets soundfile soxr huggingface_hub

# Look before you leap: duration spread, nothing written.
.venv/bin/python Tools/extract-indictts.py --out /data/indictts --survey --limit 400

.venv/bin/python Tools/extract-indictts.py --out /data/indictts
```

Streaming means the 8.2 GB of parquet is never all on disk; the written clips
come to roughly 4 GB. Clips outside 2–30 s are skipped — on this corpus that is
about 0.2%, because the clips average around eight seconds.

`Tools/prepare-audio.sh` does the same conversion for a corpus that is already
loose WAV files, if you take the original IIT Madras download instead.

### 1.3 Build the manifests

```bash
swift run kokoro-labels \
  --transcripts /data/indictts/hi_female/txt.done.data \
  --audio-dir /data/indictts/hi_female/wav \
  --speaker hi_female \
  --output female.txt --rejections female_rejected.tsv

swift run kokoro-labels \
  --transcripts /data/indictts/hi_male/txt.done.data \
  --audio-dir /data/indictts/hi_male/wav \
  --speaker hi_male \
  --output male.txt --rejections male_rejected.tsv

cat female.txt male.txt > filelist.txt
```

**Read the rejections file.** A handful is normal. Hundreds means something is
wrong — most likely a transcript encoding problem — and it is far cheaper to
find that now than after a training run.

Split `filelist.txt` into train and validation lists (roughly 95/5).

---

## Phase 1b — Option B: extract a voice pack

No GPU, no training, nothing about the model changes.

`extract_voicepack.py` runs each clip through two style encoders — one for
timbre, one for prosody — and averages the result into a `[510, 1, 256]`
tensor. It samples about 200 clips by default, so **you do not need the whole
corpus here**; a few hundred per speaker is the whole job. If disk is tight,
keep a subset and delete the rest.

Those encoders are not in this Swift package, which holds only the inference
path, so this step needs PyTorch. CPU is fine — it is inference.

```bash
VIRTUAL_ENV=.venv uv pip install torch          # CPU build, ~2-3 GB

git clone --recurse-submodules https://github.com/semidark/kikiri-tts
# Fetch kokoro-v1_0.pth and convert it to StyleTTS2 layout — see the upstream
# TRAINING_GUIDE.md for the exact conversion snippet.

python scripts/extract_voicepack.py --device cpu \
  --model kokoro_base.pth \
  --audio-dir /data/indictts/hi_female/wav \
  --output voices/hf_indic.pt
```

Then convert it into something this package loads:

```bash
.venv/bin/python Tools/voicepack-to-mlx.py \
  --input voices/hf_indic.pt --output voices/hf_indic.npz
```

That step also checks the layout, because a wrong voice pack does not fail
loudly — it synthesizes something that merely sounds off. `KokoroTTS` reads
dimensions 0–127 as the acoustic half and 128–255 as the prosodic half, so a
pack with a swapped or short layout is rejected there rather than at synthesis.

Load the `.npz` with `MLX.loadArrays(url:)` and pass the array as `voice`.
Listen. If it is enough, you are done and English never moved.

---

## Phase 2 — Rent a GPU (Option A only)

### 2.1 Pick a provider

**RunPod** is the gentlest starting point: pick a PyTorch template, get a
browser terminal, attach a persistent volume so nothing is lost if the pod
stops. Vast.ai is cheaper and fiddlier. Lambda Labs is simpler and pricier.

You need **12 GB VRAM** for `batch_size=4`. An RTX 4090 or A10 is plenty.

### 2.2 Get the data onto the box

Download Indic-TTS **directly on the pod** rather than uploading from your Mac
— you only have ~21 GB free locally. Copy up just `filelist.txt` and your
converted audio, or redo the conversion there.

### 2.3 Set up

```bash
git clone --recurse-submodules https://github.com/semidark/kikiri-tts
cd kikiri-tts
uv sync
```

Forgetting `--recurse-submodules` leaves empty directories and confusing
errors. If you did, run `git submodule update --init --recursive`.

You also need the base Kokoro checkpoint converted to StyleTTS2 layout, the
StyleTTS2 utility models (`Utils/JDC`, `Utils/ASR`, `Utils/PLBERT`), and the
monotonic alignment extension built. The upstream `docs/TRAINING_GUIDE.md` has
the exact commands — follow it rather than this file for those, since it
changes.

---

## Phase 3 — Smoke test before spending money

**Do not skip this.** The dangerous failures here are silent: they do not
crash, they just train a broken model for hours.

Run two training steps and stop. Then check:

| check | healthy | broken |
|---|---|---|
| symbol map length | `178` | anything else |
| Mel Loss, step 1 | 0.8–1.5 | **NaN → symbol mapping is wrong** |
| Gen Loss | 3–6 | — |
| Disc Loss | 4–6 | — |
| Stage 2 Mel Loss at start | **~0.43** | ~7.5–8.0 → pretrained weights did not load |

That Stage 2 number is the single most useful check in the whole process. 0.43
means you are fine-tuning. 7.5 means you are training from scratch and wasting
every hour that follows.

---

## Phase 4 — Train

```bash
cd StyleTTS2
accelerate launch train_first.py  --config_path ../configs/config_hindi_ft.yml
accelerate launch train_second.py --config_path ../configs/config_hindi_ft.yml
```

Healthy progression: Stage 1 Mel Loss 0.8 → 0.25 over ~10 epochs. Stage 2 Mel
0.43 → 0.25, Dur 1.3 → 0.9, F0 4.1 → 1.8.

If Stage 1 Mel plateaus above 0.4, stop and look at data quality or the phoneme
mapping rather than training longer.

**Config gotcha that costs people days:** `train_first.py` reads `batch_size`,
`epochs_1st`, `save_freq`, `pretrained_model` and `load_only_params` from the
**top level** of the YAML. Nest them under `training:` and they are silently
ignored.

Save checkpoints to the persistent volume. Pods can stop.

---

## Phase 5 — Extract voices and ship them here

```bash
python scripts/extract_voicepack.py --model <checkpoint> \
  --audio-dir /data/hi_female/wav --output voices/hf_indic.pt
python scripts/extract_voicepack.py --model <checkpoint> \
  --audio-dir /data/hi_male/wav   --output voices/hm_indic.pt
```

You now have fine-tuned weights **and** two voice packs. `KokoroTTS(modelPath:)`
already takes a path, so this package needs no changes to load them.

---

## Decide these before you train

**Do not change the vocabulary.** Keep the 178-slot embedding and the 114
symbols exactly as they are, or this package stops loading the result.

**Latin text.** `kokoro-labels` sets those clips aside rather than guessing. If
the rejection count is large, decide whether to transliterate or drop them.

---

## A realistic target

Only two voices in all of Kokoro are graded A or A−, and **no non-English voice
exceeds C** except French at B−. Reaching **B** for Hindi would make it the best
non-English voice in the model. Aim there, not at A.

Be calibrated about what this corpus buys. It holds roughly five hours per
speaker, against the 10–100 minutes the current Hindi voices were trained on —
a large step up, and still short of the 10–100 hours behind the A− and B−
English voices. Studio quality and accurate transcripts help the other two
components of the grade. A move from C to somewhere around C+/B− is the
sensible expectation; treat better than that as a bonus.
