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

## Calibrating against a human reciter — and why it failed

Everything above measures Kokoro against itself. The Gītā Supersite recordings
supply an external target: one reciter, the complete Gītā, chant on a fixed
reciting tone (median F0 182.8 Hz, sd 5.9 Hz).

**The conclusion of this section is negative.** A delivery built to match that
target was rejected on listening as unintelligible, and the acoustic checks
that cleared it were measuring the wrong thing. What follows is kept because
the pace gap is real and the failure is informative, not because the delivery
survived.

### The pace gap is real

Measured over the **585 anuṣṭubh verses with no speaker tag**, using voiced
time only so inserted pauses cannot flatter either side:

| | ms per syllable |
|---|---|
| reciter | **477** (sd 33, IQR 456–497) |
| ours at `recitation`, speed 0.80 | **195** |

**2.4× slower.** Comparing speech spans rather than voiced time understates it
as 1.7×; the reciter's pauses are a separate fact from the reciter's pace.

### The rate sweep

Identical phonemes and token ids at every point; only `speed` changes.

| speed | 0.80 | 0.65 | 0.55 | 0.50 | 0.46 | 0.42 | 0.36 | 0.30 | 0.25 |
|---|---|---|---|---|---|---|---|---|---|
| ms/syllable | 195 | 238 | 281 | 305 | 322 | 350 | 403 | **475** | 564 |

0.30 lands on the reciter numerically: 473, 474 and 478 across BG 1.1, 2.47 and
4.7 against a target of 477.

### It is unintelligible there

**Rendered at 0.30 and listened to, the verse cannot be understood.** That is
the finding, and it overrides everything below it.

Slowing to 0.30 divides the predicted durations by 0.30 rather than 0.80, so
every phoneme is stretched about 2.7× past what the decoder normally produces.
Pitch survives that. Consonant articulation does not.

### Why the acoustic checks missed it

Three proxies were run before listening, and all three cleared 0.30:

| check | said | was measuring |
|---|---|---|
| ms per syllable | matches the reciter | duration, not clarity |
| syllable merging | none below 0.50 | *missing* syllables, not smeared ones |
| F0 stability | 0.47 st median jump at 0.30 against 0.67 at 0.80 | **pitch only** |

The F0 check was the one trusted to catch degradation, on the reasoning that a
stretched acoustic model warbles first. It does not follow that a model which
*isn't* warbling is fine: pitch is carried by the excitation and articulation
by the filter, and stretching damaged the second while leaving the first clean.

**There is no intelligibility measure in this repository**, and none of the
spectral proxies used across these passes is a substitute for one. Where a
change alters how a phoneme is realised rather than which phoneme is sent, the
ear is the instrument.

The syllable-nucleus count deserves a separate warning. Applied to the human
recordings it scores them worse than any synthesis here (+7 to +15 against 32),
because it rewards fast even delivery and penalises held chant. It can detect
syllables *merging* and nothing else. It was right to reject it as a quality
judge; it was wrong to conclude from that rejection that nothing else was
needed.

### Kokoro also inserts silence a reciter does not

Independent of the above, and still true. Internal silence as a share of the
speech span, at a 2% energy gate:

| | silence |
|---|---|
| reciter | **0.0 %** (0.0% at a 4% gate, 3.3% at 6%) |
| ours at 0.80 | 20.8 % |
| ours at 0.50 | 22.9 % |
| ours at 0.30 | 29.1 % |

The reciter chants continuously; Kokoro does not, and the share grows as it
slows. That silence sits **inside a single `generateAudio` call**, so no pause
setting reaches it.

### What this leaves

`recitation` at 0.80 remains the default. The pace gap it leaves is real,
measured, and **not closable from the frontend** — slowing the model far enough
to close it destroys articulation before it arrives.

That makes chant tempo a fine-tuning requirement rather than a settings
question, and it belongs with the segmental gaps in
`docs/SANSKRIT_FINE_TUNING_REQUIREMENTS.md`: a Sanskrit voice needs to have
*heard* syllables held for 480 ms, not have 190 ms syllables stretched to fit.

`Tools/sanskrit-pace-experiment.sh` and `Tools/sanskrit-pace-render.sh` are
kept so the sweep can be re-run against any future model.

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
