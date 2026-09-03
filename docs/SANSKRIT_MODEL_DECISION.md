# Is Kokoro suitable for Sanskrit recitation?

A decision document, answering the ten questions in §30 of the brief from four
passes of measurement. Evidence lives in
`Artifacts/sanskrit/diagnostics/`; nothing below rests on impressions of the
audio.

## Recommendation

> **C — the frontend is sound; a Sanskrit voice fine-tune is required.**

Not A, not B, not D. The reasoning is in §11 below.

## The ten questions

### 1. Is the Sanskrit frontend now linguistically sound?

**Yes.** Four diagnostic passes over 18–22 target words each have found **no
bug** in normalization, akṣara parsing, phonology or Kokoro mapping since the
v2 visarga correction.

- Canonical form agrees with Vāgdhenu on 154 of 172 comparable corpus lines;
  every difference is a documented decision.
- All 33 consonants, all 14 vowels, all five nasals, all three sibilants and
  all ten aspiration contrasts are preserved and asserted.
- No inherent vowel is deleted anywhere; no cluster gains one.
- 120 Sanskrit tests, 258 in the suite.

### 2. Are token mappings round-trip correct?

**Yes.** `SanskritTokenAudit` decodes token ids back to symbols and diffs them
against what was sent. Across every target word, every vowel sign, every
consonant and the Sanskrit-specific forms: **zero unknowns, drops,
substitutions or duplications.** The audit is proven able to fail — feeding it
`ɭ` and `ɦ` produces the expected failure.

Source-to-token alignment is also now exact, not estimated: each akṣara carries
its character range through to a token index range.

### 3. Can current Kokoro represent visarga?

**No.** Tested exhaustively, not inferred.

Every defensible symbol in the vocabulary was measured in coda position: `h`,
`x` (jihvāmūlīya), `ɸ` (upadhmānīya) and `s`. **None produces frication** — all
sit at ZCR 0.02–0.07 against a 0.15 threshold — and `x` and `s` additionally
insert a syllable.

The failure is positional and has a clear cause: the same `h` as an **onset**
measures ZCR 0.122 / HF 0.135, and in Kokoro's nine training languages `h` is
essentially onset-only. A coda fricative is outside the model's experience.

`ACOUSTIC_MODEL_LIMITATION: VISARGA`.

### 4. Can current Kokoro represent vocalic ऋ?

**No.** Two independent reasons:

- Kokoro's vocabulary contains **no syllabic diacritic** — neither U+0329 nor
  U+0325 — so `r̩` cannot be written at all.
- The two tokens that could carry rhotic colour are **untrained**: `ɻ` occurs
  **zero** times across all nine training languages and `ɽ` **once**. Both
  stretch to 580–725 ms where trained options take 400–500 ms.

What remains is `ɾɪ` or `ɾu`, both traditional, both well-trained, neither a
syllabic rhotic. `ACOUSTIC_MODEL_LIMITATION: VOCALIC_R`.

### 5. Can it distinguish Sanskrit nasals?

**At the frontend, yes, definitively** — `ŋ ɲ ɳ n m` are five distinct tokens
and सञ्जय contains no dental `n`.

**Acoustically, unknown.** The `ɲ`/`n` contrast is short and spectral, and
nucleus counting is not sensitive enough to settle it. `REVIEW_REQUIRED:
PALATAL_NASAL` rather than a claim in either direction.

### 6. Can it preserve aspiration in dense clusters?

**In the tokens, yes** — `ʰ` is present and asserted in त्थ, भ्य, र्भ, द्ध.

**In the audio, partly.** Retroflex and palatal support is thin: across the
training languages `ʂ` appears 4 times, `ɖ` 1, `ɳ` 9, `ɟ` 12, `ʈ` 13 — against
`s` 4336 and `t` 4129. Dense clusters compress, and it is not fixable from
here: splitting धर्मक्षेत्रे actually *reduces* articulated nuclei from 6 to 5.

### 7. Can slower speed solve the remaining issues?

**It helps materially, and it does not solve them.**

Measured across three pādas as syllables lost against the true count, 0.80 is
the best rate: BG 2.47's hard pāda loses 1 syllable there against 4 at 0.84 and
8 at 1.00. Recitation now defaults to 0.80.

But speed changes timing, not phonetics. At every rate the visarga still has no
frication and ऋ is still not a syllabic rhotic. Speed buys articulation, not
the missing sounds.

### 8. Are failures voice-specific?

**No.** Eight words × five voices, everything else identical: **no voice
fricates the visarga**, all between ZCR 0.021 and 0.088. `hf_alpha` and
`af_heart` tie for best cluster clarity at 4 of 8; `hm_psi` and `hm_omega`
manage 1. `hf_alpha` is kept for its Indic coverage, but it does not escape
either limitation.

### 9. Is a Sanskrit-trained Kokoro voice required?

**Yes**, for expert-reviewable recitation. Each remaining defect is the model
never having heard the relevant sound in the relevant position:

| defect | what training would supply |
|---|---|
| visarga | coda fricatives, which no training language provides |
| vocalic ṛ | a trained `ɻ`/`ɽ`, or a vocabulary with a syllabic diacritic |
| retroflexes | more than 4 examples of `ʂ` |
| dense clusters | Sanskrit conjunct sequences at Sanskrit density |

`HindiTrainingLabels` is the precedent, and the reason the phonemes were kept
correct through four passes: labelling with this phonemizer rather than eSpeak
is what makes a fine-tune learn what inference will actually send it.

### 10. Is Kokoro fundamentally unsuitable without fine-tuning?

**No — and this is why the answer is C rather than D.**

The output is already intelligible, and the gaps are *absences in the training
distribution*, not architectural limits. Kokoro's vocabulary can already spell
all 33 consonants, 10 of 14 vowels faithfully, every aspiration contrast, all
five nasals and all three sibilants. Two sounds are unspellable (`r̩`, `ɭ`) and
one is unrealisable in position (coda visarga). That is a data problem.

Vāgdhenu reached ~4.6 MOS with IndicF5 after five hours of chanted Sanskrit —
evidence that the gap is closable with modest data rather than a different
architecture.

## 11. Why C, not A, B or D

**Not A** — "current Kokoro is sufficient". It is not. The visarga has no
frication under any mapping, in any voice; ऋ is an acknowledged approximation.
For sacred text under expert review, that is not sufficient.

**Not B** — "sufficient only at learning speed". Slower speed genuinely helps
articulation and merging, and 0.80 should ship. But it changes timing only:
the visarga and ऋ are equally wrong at 0.72 and at 1.00. B would misdescribe a
timing improvement as a fix.

**Not D** — "Kokoro is unsuitable; use another model". D would discard a
frontend that is measurably correct and a vocabulary that covers most of
Sanskrit, on the basis of gaps that are training-data absences. It would also
mean rebuilding the iOS on-device path, which currently works.

**C** — the frontend is done and proven; the acoustic model is what falls
short, and it falls short in ways training addresses.

## 12. What to do next

1. **Ship 0.80 recitation** now. It is a measured improvement available today.
2. **Settle the two REVIEW_REQUIRED items by ear**: ऋ as `ɾɪ` vs `ɾu` (regional
   preference — `ɾu` measures as more consistently monosyllabic), and whether
   the voice resolves `ɲ` from `n`.
3. **Fine-tune a Sanskrit voice.** Label the training data with
   `SanskritPhonemizer`, not eSpeak. A `SanskritTrainingLabels` alongside
   `HindiTrainingLabels` is the entry point, with the same hard vocabulary
   check: never train on a phoneme with no token.
4. **Consider extending the vocabulary** if fine-tuning happens anyway.
   IndicVoice added 37 tokens to Kokoro-82M; adding a syllabic diacritic would
   make ऋ exact rather than approximate.

## 13. What must not be done

Recorded because every pass has been tempted by it and none has done it:

> A linguistically wrong phoneme sequence is not an acceptable workaround.

Not visarga → हा. Not ऋ → री because it is clearer. Not ञ → न, not ष → श, not
dropping aspiration, not inserting vowels into clusters, not splitting
compounds, not altering the Gita text.

Beyond being wrong, each would **poison the labels the fine-tune depends on**.
The frontend's correctness is the asset that makes step 3 possible.
