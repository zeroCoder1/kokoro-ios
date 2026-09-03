# Is Kokoro suitable for Sanskrit recitation?

A decision document, from five passes of measurement. Evidence lives in
`Artifacts/sanskrit/diagnostics/`; nothing here rests on impressions of the
audio.

Updated after the prosody work, which splits the question in two: Kokoro can
be adequate at **segments** and inadequate at **timing**, or the reverse, and
conflating them produced the wrong answer before.

## Recommendation

> **C — prosody can be handled from the frontend; specific Sanskrit phonemes
> require acoustic fine-tuning.**

Segmental accuracy is where Kokoro fails, and it fails on sounds it was never
trained on. Prosodic accuracy is largely reachable without touching the model,
now that per-token duration control has been found and used.

## Question 1 — segmental accuracy

Can current Kokoro produce the sounds?

| | verdict | evidence |
|---|---|---|
| Sanskrit vowels | **yes** | all 14 distinct at canonical, IPA, token and decoded stages |
| vowel length | **yes** | `ː` is a real token; भु 390 ms → भू 545 ms unprompted (1.40×) |
| vocalic ṛ | **no** | `ɻ` occurs 0 times across the nine training languages, `ɽ` once; no syllabic diacritic exists in the vocabulary |
| five nasal places | **tokens yes, audio unknown** | `ŋ ɲ ɳ n m` are five tokens; acoustic resolution not measurable here |
| dental vs retroflex | **tokens yes, audio thin** | distinct tokens; `ʂ` 4 occurrences, `ɖ` 1, `ɳ` 9, `ʈ` 13 against `s` 4336 |
| aspiration | **tokens yes** | `ʰ` present and asserted in त्थ, भ्य, र्भ, द्ध |
| ś / ṣ / s | **tokens yes** | three distinct tokens, three distinct places in the feature model |
| **visarga** | **no** | every symbol tested in coda — `h`, `x`, `ɸ`, `s` — gives ZCR 0.02–0.07 against a 0.15 threshold |
| dense clusters | **partly** | parse correctly, compress acoustically; splitting makes it worse |

**Two hard failures, and both are training-data absences.** The visarga fails
because Kokoro's `h` is realised only as an onset — measured at ZCR 0.122 in
`haːma` and 0.040 in `maːh` — and in all nine training languages `h` is
essentially onset-only. Vocalic ṛ fails because the tokens that could carry
rhotic colour were never produced by any training language.

Neither is fixable from the frontend, and no voice escapes them: across five
voices, none fricates the visarga.

## Question 2 — prosodic accuracy

Can current Kokoro preserve the timing?

| | verdict | evidence |
|---|---|---|
| guru/laghu tendencies | **yes, controllably** | durations are predicted **per token**; `predictDurations` now accepts a per-token multiplier |
| long-vowel timing | **yes** | the model already gives 1.23–1.93× for a length mark unprompted; weakens to 1.16× inside a cluster, which the scale corrects |
| closed-syllable weight | **yes, derivable** | `SanskritSyllabifier` computes it; the scale expresses it |
| consonant holding | **yes, expressible** | held codas get their own multiplier, with no inserted vowel |
| neutral / non-English stress | **yes** | Sanskrit emits no stress marks at all; the option to add them exists and is off |
| natural phrase rhythm | **mostly** | syllables merge above 0.80; at 0.80 all three pādas are at or within one of their true syllable count |
| daṇḍa / verse pauses | **yes** | supplied by the prosody layer, since the model does not differentiate `।` from `॥` |

**Prosody is in much better shape than segments**, and the reason is a finding
from this pass: duration is predicted per token and only then divided by a
global `speed`. That makes per-phoneme timing directly available without
touching a phoneme, a weight, or the model. See
`docs/SANSKRIT_KOKORO_PROSODY.md`.

### The strongest single piece of evidence

The Gita is anuṣṭubh: four pādas of eight syllables, with the *pathyā* cadence
fixing syllables 5–7 as **L G G** in odd pādas and **L G L** in even ones.

Nothing in this codebase knows that pattern. The syllabifier applies
phonological rules to a phoneme stream. Yet **all twelve pādas across BG 1.1,
2.47 and 4.7 match**, with 16 + 16 syllables per verse and no warnings.

A single wrong vowel length, or one misplaced syllable boundary, would break
it. That is independent confirmation that the akṣara parser, the phonology, the
vowel-length model and the syllabifier are jointly correct —
`Artifacts/sanskrit/diagnostics/gita-meter-analysis.md`.

### What the prosody experiment actually showed

Honest, and mixed. Same phonemes, same tokens, only the per-token duration
multiplier differs:

| verse | total (current → prosody) | nuclei | spread (std/mean) |
|---|---|---|---|
| BG 1.1 | 9080 → 9080 ms | 27 → 27 | 0.773 → 0.782 |
| **BG 2.47** | 9160 → 9160 ms | **26 → 29** | **0.686 → 0.763** |
| BG 4.7 | 9465 → 9440 ms | 10 → 9 | 0.610 → 0.549 |

It **redistributes** time rather than adding it — the totals are unchanged,
which is the success criterion §Y sets out. It measurably helps the verse that
needed it most (BG 2.47, the one with the 24-phoneme compound): three more
articulated nuclei and an 11% wider spread. It is neutral on BG 1.1 and
slightly negative by this metric on BG 4.7.

So the mechanism works and the effect is real but small and not uniform. It
stays **off by default** pending listening.

## The ten original questions

1. **Frontend linguistically sound?** Yes. Five passes, no bug found since v2.
2. **Token mappings round-trip?** Yes. Zero drops, substitutions, duplications.
3. **Visarga representable?** No — exhaustively tested.
4. **Vocalic ṛ representable?** No — both candidate tokens untrained.
5. **Nasals distinguishable?** In tokens yes; acoustically unmeasured.
6. **Aspiration in dense clusters?** In tokens yes; audio compresses.
7. **Does slower speed solve it?** It helps timing (0.80 is measurably best)
   and does nothing for the missing sounds.
8. **Voice-specific?** No. All five voices fail identically.
9. **Sanskrit voice fine-tune required?** Yes, for the segments.
10. **Kokoro fundamentally unsuitable?** No — the gaps are absences in the
    training distribution, not architectural limits.

## Why C, not A, B, D or E

**Not A** ("frontend + prosody is enough"). The prosody half is nearly true
now, but the visarga has no frication under any mapping in any voice, and ऋ is
an acknowledged approximation. For sacred text under expert review that is not
enough.

**Not B** ("segments fine, prosody needs training"). This has it backwards.
Prosody turned out to be the tractable half: per-token duration control exists
and works. Segments are where the model is missing sounds.

**Not D** ("both need fine-tuning"). Prosody demonstrably does not — syllable
weight, holding and pause structure are all computable from the text and
expressible through the existing duration predictor.

**Not E** ("fundamentally unsuitable"). The vocabulary already spells all 33
consonants, every aspiration contrast, all five nasals and all three sibilants;
the metre validates end to end; the output is intelligible. Vāgdhenu reached
~4.6 MOS after five hours of chanted Sanskrit, so the gap is closable with
modest data.

**C** — the frontend and the prosody layer are done and proven. Two specific
sounds need a model that has heard them.

## Next steps

1. **Ship 0.80 recitation.** Measured, available today.
2. **Listen to the prosody experiment** and decide whether
   `SanskritProsodyIntent.recitation` should become the default.
3. **Settle the REVIEW_REQUIRED items**: ऋ as `ɾɪ` vs `ɾu`, and whether the
   voice resolves `ɲ` from `n`.
4. **Fine-tune a Sanskrit voice**, labelling with `SanskritPhonemizer` rather
   than eSpeak. The syllable and mātrā metadata is now available as training
   signal too.
5. **Consider extending the vocabulary** if fine-tuning happens anyway — a
   syllabic diacritic would make ऋ exact rather than approximate.

## What must not be done

> A linguistically wrong phoneme sequence is not an acceptable workaround.

Not visarga → हा. Not ऋ → री because it is clearer. Not ञ → न, not ष → श, not
dropping aspiration, not inserting vowels into clusters, not splitting
compounds, not altering the Gita text. **Not token repetition for duration** —
repeating the `a` of `aː` gives two vowels, not one long one, and repeating a
consonant gives a geminate, which in Sanskrit is a different word.

Beyond being wrong, each would poison the labels the fine-tune depends on. The
frontend's correctness is the asset that makes the next step possible.
