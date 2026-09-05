# What duration control does Kokoro actually offer?

An audit of the synthesis path, done before any prosody mechanism was built,
to answer §O of the brief. The answers come from reading
`KokoroTTS.predictDurations` and `createAlignmentTarget` and then measuring,
not from assumption.

## The mechanism

```swift
let (lstmOutput, _) = predictorLSTM(features)
let durationLogits  = durationProj(lstmOutput)          // one value per token
var durationSigmoid = sigmoid(durationLogits).sum(axis: -1) / speed
let predicted       = clip(durationSigmoid.round(), min: 1).asType(.int32)
```

Then `createAlignmentTarget` repeats each token index `predicted[i]` times to
build the frame-level alignment the decoder consumes.

So duration is **predicted per token**, as an integer frame count, and the only
thing standing between the prediction and the alignment matrix is a divide by
a single global `speed`.

## The eight questions

**1. Can we influence individual phoneme duration?**
Yes, and exactly. Each token gets its own frame count, and a phoneme is one or
two tokens. Multiplying `durationSigmoid` element-wise before the round is a
per-phoneme duration control.

**2. Can we influence individual token duration?**
Yes — this is the same mechanism, at its native granularity.

**3. Is duration fully predicted internally?**
It is predicted internally, but it is not sealed. The prediction is an ordinary
tensor in Swift, before rounding, and the model is not consulted again about it.

**4. Does duplicating tokens cause lengthening or incorrect pronunciation?**
**Incorrect pronunciation, and it must not be used.** A token is a phoneme
identity, not a time slice. Repeating the `a` of `aː` gives the model two
vowels, not one long one; repeating a consonant gives a geminate, which in
Sanskrit is a different word — तत्त्व is not तत्व. Duplication changes the
phoneme sequence, which is precisely what the quality rule forbids. The
per-token scale changes no token at all.

**5. Can punctuation safely create micro-boundaries?**
Only coarsely. Measured at verse length, `,` yields 385 ms against 350 ms for
no punctuation, and `.` 355 ms — the model inserts a gap of its own accord and
barely distinguishes the marks. Punctuation is usable for phrasing and
intonation but not for fine timing, which is why `SanskritProsody` supplies
pause *durations* separately.

**6. Can speed be localized?**
Not as written — `speed` is one scalar for the whole call. It can be localized
two ways: by splitting the utterance, which `SanskritProsody` already does per
pāda, or by the per-token scale, which is finer and does not add joins.

**7. Can duration predictor outputs be adjusted?**
Yes. `predictDurations` now takes an optional `durationScale: [Float]?` and
multiplies the prediction element-wise before rounding. A length mismatch is
ignored with a warning rather than applied partially — a scale sliding one
token out of step would be worse than no scale.

**8. Can we preserve guru/laghu timing without changing the acoustic model?**
**Yes, in principle, and this is the mechanism for it.** Syllable weight is
computed by `SanskritSyllabifier`; `SanskritProsodyPlanner.durationScale`
turns it into a per-token multiplier; the tokens themselves are untouched.
Whether it *sounds* better is a listening question — see
`Artifacts/sanskrit/prosody-experiment/`.

## What the model already does unprompted

Worth stating, because it bounds how much correction is warranted. Kokoro's
duration predictor is not ignorant of length:

| | short | long | ratio |
|---|---|---|---|
| `ke` / `keː` | 126 ms | 156 ms | 1.24× |
| `ko` / `koː` | 132 ms | 162 ms | 1.23× |
| `kɛ` / `kɛː` | 90 ms | 174 ms | 1.93× |
| `bʰu` / `bʰuː` | 390 ms | 545 ms | 1.40× |

It weakens in context — र्भु to र्भू is only 1.16× — which is where a
correction has something to do. The scales in
`SanskritProsodyIntent.recitation` are therefore small: 1.15 on a guru vowel,
0.92 on a laghu one, 1.20 on a held coda. They widen the guru/laghu contrast by
roughly 25% without leaving the range the model already produces on its own.

## Calibrating against a human reciter

Everything above measures Kokoro against itself. It says how much duration
control exists, not what the target is. The Gītā Supersite recordings supply
the target: one reciter, the complete Gītā, chant on a fixed reciting tone
(median F0 182.8 Hz, sd 5.9 Hz across 24 verses from different chapters).

Measured over the **585 anuṣṭubh verses with no speaker tag**, using voiced
time only so inserted pauses cannot flatter either side:

| | ms per syllable |
|---|---|
| reciter | **477** (sd 33, IQR 456–497) |
| ours at `recitation`, speed 0.80 | **195** |

**2.4× slower.** Comparing speech spans rather than voiced time understates it
as 1.7×, which is the mistake to avoid here — the reciter's pauses are a
separate fact from the reciter's pace.

### The rate sweep

Identical phonemes and token ids at every point; only `speed` changes.

| speed | 0.80 | 0.65 | 0.55 | 0.50 | 0.46 | 0.42 | 0.36 | 0.30 | 0.25 |
|---|---|---|---|---|---|---|---|---|---|
| ms/syllable | 195 | 238 | 281 | 305 | 322 | 350 | 403 | **475** | 564 |

**0.30 lands on the reciter**: 473, 474 and 478 across BG 1.1, 2.47 and 4.7,
against a target of 477. That is `SanskritDelivery.traditional`.

### Why the metric that chose 0.80 cannot argue against 0.30

`recitation`'s 0.80 was picked by counting energy nuclei against the syllables
a pāda actually has, and taking the rate that lost fewest. Run that same count
on the human recordings and it scores them **worse than any synthesis here**:

| | nuclei against 32 |
|---|---|
| reciter, BG 1.1 / 2.47 / 4.7 | +15 / +10 / +7 |
| ours at 0.80 | +1 / −1 / −3 |
| ours at 0.30 | +29 / +28 / +32 |

The metric rewards fast, smooth, evenly-peaked delivery and penalises held
chant, so over-counting is not evidence of damage. What it *can* legitimately
detect is syllables **merging**, and there the sweep is unambiguous: at 0.80
BG 4.7 loses three and BG 2.47 one, and from 0.50 down nothing merges at all.

### The degradation check it cannot provide

A stretched acoustic model warbles before anything else goes wrong, so F0
stability is the check that matters. Frame-to-frame pitch movement:

| | median jump | jumps > 2 semitones |
|---|---|---|
| reciter | 0.33–0.39 st | 24.7–28.8 % |
| ours at 0.80 | 0.53–0.67 st | 28.2–30.2 % |
| ours at 0.30 | 0.47–0.49 st | 27.7–27.8 % |

**Nothing degrades.** The slow render is marginally steadier than the fast one
and sits inside the reciter's own range. Kokoro stretches cleanly to 0.25.

### The pause inverts

Kokoro's own gap at the daṇḍa is not constant — it grows as the model slows:

| speed | 0.80 | 0.55 | 0.46 | 0.36 | 0.30 |
|---|---|---|---|---|---|
| model's own gap | 390–460 ms | 500–610 | 560–700 | 440–910 | 550–1150 |

So the original rule — configure a pause *above* the model's natural ~350 ms
or splitting makes things worse — holds only at fast rates. At `traditional`'s
pace the model **over**-pauses, and the split path is what reins it in: it
trims the decoder's own edge silence and inserts exactly the configured value
divided by speed. The reciter's half-verse break measures 410 ms (median over
the 292 anuṣṭubh verses that take one), so `padaPause` is 0.12 and 0.12 ÷ 0.30
≈ 400 ms.

`versePause` is uncalibrated and says so: the reference recordings are trimmed
at the end, median 50 ms of trailing silence, so they carry no evidence about
the rest between verses.

### The gap that remains: Kokoro inserts silence a reciter does not

Matching syllable duration does not produce a verse of the reciter's length.
Internal silence as a share of the speech span, at a 2% energy gate:

| | silence |
|---|---|
| reciter | **0.0 %** (0.0% at a 4% gate, 3.3% at 6%) |
| ours at 0.80 | 20.8 % |
| ours at 0.50 | 22.9 % |
| ours at 0.30 | 29.1 % |

The reciter chants continuously. Kokoro does not, and the share grows as it
slows. BG 2.47 therefore comes out around 27 s at `traditional` against the
reciter's 15.7 s — for the same voiced time.

That silence is **inside a single `generateAudio` call**, so no pause setting
reaches it. It leaves two targets that cannot both be met:

- match the reciter's **syllable duration** → speed 0.30, verse ~1.7× too long
- match the reciter's **verse length** → speed ~0.46, syllables a third short

`traditional` takes the first. The second is a one-line change for anyone who
prefers it, and the choice is a listening question, not a measurement one.

This asymmetry is also why the 0.30 figure carries a range. Only our side has
internal silence to gate out, so the voiced/total split moves with the gate
while the reciter's does not:

| energy gate | 2 % | 6 % | 10 % |
|---|---|---|---|
| reciter | 488 ms | 471 | 414 |
| ours at 0.30 | 542 ms | 474 | 434 |

Read honestly that is 0.30–0.33, not an exact 0.30.

### What this does not fix

Pace is not pronunciation. The visarga, vocalic ṛ and final nasal closure are
exactly as they were. The reference corpus cannot help with those either — it
is 16 kHz at 16 kbps, brick-walled at 4.4 kHz with 0.00% of its energy above
5 kHz, so the fricative band those sounds live in is not in the recording.
See `docs/SANSKRIT_SOURCES.md`.

## Design consequences

**Prosodic intent is separate from prosodic realization.** The syllable layer
produces mātrās and holding flags — linguistic facts, true whatever synthesizes
them. `SanskritProsodyPlanner` turns those into a duration scale only when
asked, and returns `nil` for the neutral intent, so the default path is byte
identical to having no prosody layer at all.

**Timing is not encoded in phonemes.** Nothing here writes a phoneme to get a
duration. That separation is what keeps the canonical Sanskrit usable as
training labels later.

**Not "make Sanskrit slower".** A global slowdown lengthens guru and laghu
equally and preserves no contrast. The point is to keep the contrasts: long
vowels long, closed syllables heavy, conjunct codas held, light syllables
comparatively light — and the phrase still flowing.
