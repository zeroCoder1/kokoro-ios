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

### Option B — a new voice pack with no training at all: **not possible**

The obvious cheap path would be to fit a new style vector against the released
model and never touch the weights. It cannot be done, and it is worth knowing
why before anyone tries.

`extract_voicepack.py` runs two style encoders over the audio, and requires
`net["style_encoder"]` in the checkpoint. Kokoro's release does not have it:

```
$ python -c "import torch; print(list(torch.load('kokoro-v1_0.pth').keys()))"
['bert', 'bert_encoder', 'predictor', 'decoder', 'text_encoder']
```

`kokoro-v1_0.pth` is the only checkpoint published; everything else in the repo
is the 54 precomputed voice packs. What was released is **inference weights**.
The encoders that *produce* style vectors live only in StyleTTS2 training
checkpoints, which is why every example in the upstream recipe points at
`StyleTTS2/logs/.../epoch_1st_*.pth` rather than at the base model.

So a voice pack cannot be made without training something first.

### Option B2 — train to get an encoder, then ship the original weights

A middle path that still guarantees English. Run **Stage 1 only** on the Hindi
data, which trains the style encoder alongside everything else. Extract the
voice pack from that checkpoint. Then **discard the trained weights** and ship
the original model with the new pack.

English is untouched because the shipped weights are the released ones.

The risk is real and unverified: the style encoder drifted along with the model
during Stage 1, so a pack extracted from it is fitted to slightly different
weights than the ones it will be used with. After a short Stage 1 the drift
should be small, but nobody has measured it. Listen before trusting it.

This still needs a GPU, though only for a short Stage 1 rather than the full
two-stage run.

### Option A — fine-tune, and ship two model files

If B is not enough: fine-tune on Hindi, and keep the original weights for
English. English stays bit-identical because it uses a different file.

The costs are real — roughly double the model payload, and an app change, since
today one `KokoroTTS` serves both languages while two models means two
instances or a reload on language switch.

If you get here, decide by measuring rather than assuming: run a fixed English
set through both checkpoints and compare. Ship one model if English holds, two
if it does not.

Phase 1 is shared by every path. Phases 2–4 need a GPU.

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

## Phase 5 — Extract the voice packs and bring them back

Once you have a checkpoint that contains a trained `style_encoder` — from a
full fine-tune (Option A) or a Stage 1 run (Option B2) — extraction itself is
pure inference and runs on CPU:

```bash
python scripts/extract_voicepack.py --device cpu \
  --model StyleTTS2/logs/<run>/epoch_1st_00002.pth \
  --audio-dir /data/indictts/hi_female/wav \
  --output voices/hf_indic.pt
```

It samples about 200 clips by default, so the whole corpus is not needed here.

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

## Phase 1c — Option B2 local prep (done on the Mac, verified)

Everything below runs without a GPU and was checked on an M1 before renting
anything. `training/config_hindi_ft.yml` in this repo is the result.

```bash
VIRTUAL_ENV=.venv uv pip install torch torchaudio librosa munch pyyaml \
  transformers einops einops_exts monotonic_align pytest
git clone --recurse-submodules --depth 1 https://github.com/semidark/kikiri-tts
```

The StyleTTS2 utility models (`Utils/ASR`, `Utils/JDC`, `Utils/PLBERT`) ship
inside that clone, so there is nothing else to download for them.

**Convert the base checkpoint** to StyleTTS2 layout — five components, no style
encoder, which is the whole reason B2 needs a training run:

```python
raw = torch.load("kokoro-v1_0.pth", map_location="cpu", weights_only=False)
strip = lambda sd: {k.replace("module.", ""): v for k, v in sd.items()}
net = {k: strip(raw[k]) for k in
       ("bert", "bert_encoder", "predictor", "text_encoder", "decoder")}
torch.save({"net": net}, "prep/kokoro_base.pth")
```

**Build the file lists** with relative audio paths, so they still resolve on
the rented box, and set `root_path` to the audio root:

```bash
swift run kokoro-labels --transcripts <data>/hi_female/txt.done.data \
  --audio-dir "hi_female/wav" --speaker hi_female --output prep/hi_female.txt
```

Shuffle both speakers together into `train_list.txt` and `val_list.txt`, and
write an `OOD_texts.txt` — Stage 1 still constructs the dataset that reads it.

### Three checks worth doing before you pay for anything

**1. Every phoneme maps.** The guide warns that a symbol mismatch does not
error, it silently corrupts embeddings and shows up later as NaN Mel Loss.

```python
from kokoro_symbols import symbols, dicts
assert len(symbols) == 178 and dicts["ç"] == 78
# then check every phoneme column in the manifests against `dicts`
```

On this corpus: **0 unmapped characters in 11,626 lines.** German needed a
remap for `ʏ`; Hindi needs none, because `kokoro-labels` already validates
against the same vocabulary.

**2. The released weights fit the model your config builds.** Build the model
and load each component with `strict=False`, then count what did not match:

```
  bert           ok
  bert_encoder   ok
  predictor      ok
  text_encoder   ok
  decoder        ok
```

Zero missing, zero unexpected. This is also what catches `multispeaker`:
Kokoro's own config.json says `true` and this corpus has two speakers, so the
German config's `false` would build an architecture the weights do not fit —
and `strict=False` would hide it rather than report it.

**3. Note what trains from scratch.** `style_encoder`, `predictor_encoder`,
`text_aligner`, `pitch_extractor`, `mpd`, `msd`, `wd`, `diffusion`. The first
of those is the one B2 exists to obtain.

### A gotcha on torch 2.6+

`torch.load` now defaults to `weights_only=True`, and the StyleTTS2 utility
checkpoints do not load under it. Anything reading them needs
`weights_only=False` explicitly.

### Then, on the rented GPU

```bash
cd StyleTTS2
accelerate launch train_first.py --config_path ../prep/config_hindi_ft.yml
```

`save_freq: 1` keeps every epoch. That is deliberate: for B2 more training
gives a better style encoder but drifts it further from the weights the pack
will be used with, so extract packs from several epochs and pick by ear rather
than assuming the last one is best.

Then Phase 5 to extract and convert.

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
