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
