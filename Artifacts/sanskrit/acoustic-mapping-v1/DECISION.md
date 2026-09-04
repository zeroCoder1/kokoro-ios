# Acoustic mapping experiments — results and decisions

Can any *other* symbol already in Kokoro's vocabulary render a Sanskrit sound
better than the current mapping, without changing canonical Sanskrit?

Method: one canonical phoneme overridden at a time, everything else held —
same voice (`hf_alpha`), speed (0.80), text, pauses and model. The canonical
and phonological layers are asserted unchanged under every profile.

Baseline `3ef6dcc`. Audio and per-file manifests in the subfolders here.

## Candidate search

Every defensible symbol in the 114-entry vocabulary, with its training support
counted from an espeak scan across Kokoro's nine training languages.

| target | candidates in vocabulary | training support |
|---|---|---|
| ए `eː` | `e` `ɛ` `ɜ` `ᵻ` `A` `æ` | 1171 / 1792 / 393 / 338 / **0** / — |
| visarga | `h` `x` `ɸ` `θ` `ç` `χ` | 561 / 11 / **0** / 354 / **1** / 4 |
| ऋ | `ɾ` `ɚ` `ɹ` `ɻ` `ɽ` `ʁ` | 532 / **694** / 3921 / **0** / **1** / 7 |
| ञ | `ɲ` `ɴ` `ʎ` `ʲ` | 7 / 2 / 4 / 1 |
| ष | `ʂ` `ɕ` `ʃ` | 4 / 16 / 989 |
| ङ | `ŋ` `ɴ` | 577 / 2 |
| aspiration | `ʰ` `ʱ` | 162 / **absent** |

The two symbols that would be *phonetically exact* for ऋ — `ɻ` and `ɽ` — have
0 and 1 occurrences. `ɸ`, the exact upadhmānīya, has 0. Accuracy and training
support point in opposite directions almost everywhere.

## 1. Vocalic ऋ — `DEFENSIBLE_APPROXIMATION_IMPROVES_AUDIO`

**Accepted as a candidate; not yet production.**

`ɚ` is an r-coloured mid-central vowel: a single rhotic nucleus, which is the
phonetic category Sanskrit ṛ belongs to. The shipped `ɾɪ` is a flap followed by
a separate vowel — two segments, and the North Indian reading convention rather
than the sound. `ɚ` is also the only rhotic-vowel symbol in the vocabulary with
real training behind it (694, against 0 and 1 for the more accurate symbols).

Measured as total deviation from the correct Sanskrit syllable count across
twelve ṛ words — ṛ is **one light syllable**, so a mapping that produces two is
wrong:

| mapping | Σ \|nuclei − syllables\| |
|---|---|
| `ɾɪ` baseline | **23** |
| **`ɚ`** | **11** |
| `ɾu` | 19 |

Per word, `ɚ` hits the correct count where the baseline does not: हृषीकेश 4 (vs
6), सृजाम्यहम् 5 (vs 9), वृत्ति 2 (vs 3), प्रकृति 5 (vs 7).

Graded `defensibleApproximation`, never exact: `ɚ` is mid-central where ṛ is
retroflex, and no syllabic diacritic exists to write the real thing. Canonical
stays `f`.

**Needs listening before shipping.** The nucleus count is a proxy for
syllabicity, not a judgement of quality.

## 2. Sanskrit ए — `BASELINE_BETTER` (for now)

`ɛː` separates ए from ई measurably better in **all seven** minimal pairs:

| pair | `eː` baseline | `ɛː` candidate |
|---|---|---|
| के / की | 10.2 dB | 14.4 dB |
| ते / ती | 9.3 | 13.7 |
| से / सी | 11.1 | 16.4 |
| क्षेत्रे / क्षेत्री | 2.7 | 4.4 |
| समवेता / समवीता | 4.5 | 7.0 |
| फलेषु / फलीषु | 4.2 | 7.5 |

Consistent, ~40% more separation, and `ɛ` is better trained (1792 vs 1171).

**Rejected for production anyway.** Sanskrit ए is **close-mid**; `ɛ` is
open-mid. Adopting it would trade phonetic accuracy for separation on a
spectral proxy, across every ए in the language — the widest blast radius of any
candidate tested. The measurement is real and recorded; the decision needs an
ear, not a metric.

## 3. Visarga — `NO_SUPPORTED_KOKORO_MAPPING`

`ç` was the only untried candidate with a defensible place of articulation.
Tail zero-crossing rate, where frication needs > 0.15:

| word | `h` baseline | `ç` candidate |
|---|---|---|
| कः | 0.035 | 0.079 |
| रामः | 0.091 | **0.025** |
| योगः | 0.110 | **0.041** |
| पाण्डवाः | 0.019 | 0.135 |
| नमः | 0.082 | 0.148 |

Inconsistent — better on two words, markedly worse on two others — and nothing
reaches threshold. With `ç` at one training occurrence, this is noise rather
than signal. `h` remains, with `KOKORO_APPROXIMATED_VISARGA` on every use.

**`ACOUSTIC_MODEL_LIMITATION: VISARGA`** stands, now tested over `h`, `x`,
`ɸ`, `s` and `ç` across five voices.

## 4–7. Sounds where the baseline is already the best available

| target | finding |
|---|---|
| **ञ** | `ɲ` is the only genuine palatal nasal in the vocabulary. `ɴ` (2) and `ʎ` (4) are worse on both accuracy and training. `BASELINE_BETTER`. |
| **ष** | `ʂ` is correct and thinly trained (4). `ɕ` is श's proper value, not ष's; `ʃ` would collapse the ś/ṣ contrast. `BASELINE_BETTER`. |
| **ङ** | `ŋ` is exact and well trained (577). `EXACT_MAPPING_FOUND` — nothing to change. |
| **aspirated clusters** | `ʰ` is the only aspiration modifier present; `ʱ`, which the voiced aspirates properly want, is absent. `NO_SUPPORTED_KOKORO_MAPPING` for the voiced series; the contrast survives regardless. |

One candidate was accepted at `exact` quality but not adopted: `ɕ` for **श**
is the phonetically correct alveolo-palatal, and it is better trained than `ʂ`
(16 vs 4). It is left out of production because changing श while ष stays `ʂ`
alters one side of a three-way contrast on a proxy metric. Available as
`shaAsAlveoloPalatal`.

## 8. Dense clusters and final closure — no mapping question

Every cluster round-trips clean under **every** profile, gains no vowel, drops
no consonant. Final stops close correctly (तत् / तत ratio 3.36). Final nasals
do not, in any of five voices (~1.0).

`ACOUSTIC_MODEL_LIMITATION: FINAL_NASAL_CLOSURE`, with
`FINAL_STOP_CLOSURE_SUPPORTED` recorded separately as the brief asks — these
are not one rule.

## A correction carried over from the previous pass

The previous build shipped a `finalShortVowelScale` of 0.80 applied to **every**
word-final short vowel, on by default. सञ्जय, कदाचन and भारत all end in a
perfectly valid short a, and a blanket rule that shortens all of them is a
guess dressed as a repair.

It changed duration only — never a phoneme, never a token — but it is now
**experimental and 1.0 in every shipped delivery**. The visarga repair remains
shipped: it is scoped to one phonological environment and distinguishes a long
vowel there from a short one.

## Overall: **B — a few sounds improve through mapping, but fine-tuning is still required**

Not A: only one candidate improves anything, and the two hardest sounds — the
visarga and final nasal closure — have no mapping at all.

Not C: C would say mapping cannot help. It can, for ऋ, measurably.

Not D: the vocabulary is not too constrained in general. It spells all 33
consonants, every aspiration contrast, all five nasals and all three sibilants,
and the metre validates end to end. It is short of two specific things.

**B**, and the next step is listening — `ɚ` for ऋ is the one change with
evidence behind it, and the ए candidate is worth an ear even though the metric
alone should not decide it.
