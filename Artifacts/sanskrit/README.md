# Sanskrit listening samples

Bhagavad Gita 1.1, 2.47 and 4.7 through the current Kokoro voices, for **Gate 3
review**: whether the existing voices can render correct Sanskrit acceptably.

**The audio is not in git.** It is ~27 MB of regenerable output, so
`Artifacts/` is ignored and this note is what is tracked. Regenerate with:

```bash
Tools/sanskrit-render.sh --model <kokoro.safetensors> --voices <voices-dir>
```

`Tools/sanskrit-render.sh` documents how to produce those two inputs from a
stock `kokoro-v1_0.pth` and any Kokoro `[510, 1, 256]` voicepack.

## What gets written

| File | What it is |
|---|---|
| `bg_01_01.wav`, `bg_02_47.wav`, `bg_04_07.wav` | the primary voice (`hf_alpha` by default) |
| `bg_NN_NN_<voice>.wav` | the same verse in each available voice, for comparison |
| `bg_NN_NN_<voice>_slow.wav` | the same, at `speed: 0.7` |

The slow files are ~1.4× longer than the normal ones because `speed` divides
the predicted phoneme durations *before* the decoder runs. The model
articulates slowly; nothing is a slowed-down render of a normal one.

## How to listen

**No voice here has ever heard Sanskrit.** They are English and Hindi packs.
The Hindi ones (`hf_*`, `hm_*`) are the closest match, since retroflexes and
aspirates are sounds they were actually trained on.

Judge the **phoneme sequence**, not the voice quality. `Tools/sanskrit-inspect.sh`
prints what was sent to the model for any line, so a suspect word can be traced
to the layer that produced it.

If a verse is linguistically right but sounds wrong, the finding is
`PHONEMIZER VALID — ACOUSTIC MODEL / VOICE TRAINING REQUIRED`. Do not misspell
Sanskrit to flatter an untrained voice: it would poison exactly the labels a
future fine-tune depends on. See `docs/SANSKRIT.md`.
