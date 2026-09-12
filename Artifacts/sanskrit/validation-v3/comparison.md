# validation-v3 versus validation-v2

Third-pass renders. v2 is preserved in `../validation-v2/` and nothing here
overwrote it.

| | v2 | v3 |
|---|---|---|
| commit | `8e74575` | `6792784` |
| speed | 1.0 and 0.75 | **0.84 recitation**, 0.75 learning, 1.0 fast |
| pāda / verse pause | 0.50 s / 1.00 s | per mode: 0.70/1.30, 0.50/1.00, 0.40/0.80 |
| phonemes | — | **byte-identical to v2** |
| voice / model | `hf_alpha`, kokoro-v1_0 | unchanged |

**No phoneme changed in this pass.** The diagnosis found no frontend bug: all
fifteen target words are canonically correct and round-trip clean. Everything
below is either a prosody change or an acoustic finding reported rather than
worked around.

Evidence: `../diagnostics/v2-refinement-analysis.md`. Per-file record:
`manifest.json`.

## Issue tracker

| Issue | v2 behaviour | v3 behaviour | Change | Status |
|---|---|---|---|---|
| **ए vs ई** | fixed in v2 | unchanged, now locked by 21 assertions across canonical / IPA / tokens / decoded symbols | regression tests only | **RESOLVED** |
| **visarga** | bare `h`, no echo | identical | none — measurement shows the model gives coda `h` no frication at all (ZCR 0.040 vs 0.043 for no `h`) | **ACOUSTIC_MODEL_LIMITATION** |
| **long vowel before visarga** | length mark correct | identical, asserted in place | none — model shortens `ɾaːmaːh` 90 ms *below* `ɾaːmaː` | **ACOUSTIC_MODEL_LIMITATION** |
| **BG 1.1 opening compound** (धर्मक्षेत्रे कुरुक्षेत्रे) | compressed at 1.0 | 0.84 default; 19 nuclei vs 15 at 1.0 | speed | **IMPROVED** |
| **पाण्डवाश्चैव** | `paːɳɖaʋaːʃcaɪʋa` | identical | none — cluster parse verified correct | **IMPROVED** (speed only) |
| **सञ्जय** | `saɲɟaja` | identical, `ɲ` asserted, no dental `n` | regression test | **IMPROVED** (speed only) |
| **कर्मण्येवाधिकारस्ते** | 24 phonemes, one word | identical | none — needs a sandhi lexicon | **ACOUSTIC_MODEL_LIMITATION** |
| **कर्मफलहेतुर्भूर्मा** | `kaɾmapʰalaheːtuɾbʰuːɾmaː` | identical | none | **IMPROVED** (speed only) |
| **सङ्गोऽस्त्वकर्मणि** | `saŋɡoːstʋakaɾmaɳi` | identical; avagraha silent, not a break, retained as structure | regression test | **IMPROVED** (speed only) |
| **अभ्युत्थानम्** | `abʰjuttʰaːnam` | identical, aspiration asserted | regression test | **IMPROVED** (speed only) |
| **सृजाम्यहम्** | `sɾɪɟaːmjaham` | identical, reported | none | **ACOUSTIC_MODEL_LIMITATION: VOCALIC_R** |
| **daṇḍa pauses** | 0.50 / 1.00 s | 0.70/1.30 learning, 0.50/1.00 recitation | per-mode config | **IMPROVED** |
| **default speed** | 1.0 | **0.84** | `SanskritDelivery.recitation` | **RESOLVED** |
| **ɲ / ʂ acoustic resolution** | unknown | unknown | none | **REVIEW_REQUIRED** |

## Durations

| verse | v2 (1.0) | v3 fast | v3 recitation | v3 learning |
|---|---|---|---|---|
| BG 1.1 | 8.05 s | 7.75 s | **9.63 s** | 11.77 s |
| BG 2.47 | 8.17 s | 7.87 s | **9.65 s** | 11.86 s |
| BG 4.7 | 8.19 s | 7.89 s | **9.83 s** | 12.00 s |

## What to listen for

The phoneme stream is unchanged from v2, so **only pace and pausing differ**.

1. **Compare `bg_01_01_recitation.wav` against v2's `bg_01_01.wav`.** Same
   phonemes, 0.84 vs 1.0. The measurement says syllables stop merging; the
   question is whether that is audible and whether 0.84 is the right value.
2. **Then `bg_01_01_learning.wav`** at 0.75 with longer breaks — is it usable
   for following along, or does it drag?
3. **युयुत्सवः and मामकाः will still sound wrong.** That is expected and
   documented: no voice tested renders a coda `h`, so the visarga has no
   frication in any of them. Confirming it by ear supports the finding rather
   than contradicting it.

## Unresolved, and why nothing was done about them

All four are `ACOUSTIC_MODEL_LIMITATION`. Changing the phonemes to mask any of
them would be the hack §16 forbids, and would poison the labels a Sanskrit
fine-tune depends on.

| | measurement |
|---|---|
| **visarga** | coda `h` ZCR 0.040 against onset `h` at 0.122 — the model realises `h` only word-initially |
| **long vowel + visarga** | `ɾaːmaːh` is 90 ms shorter than `ɾaːmaː` |
| **vocalic ṛ** | no syllabic diacritic exists in the 114-token vocabulary, so `r̩` is unwritable |
| **retroflexes** | `ʂ` 4, `ɖ` 1, `ɳ` 9, `ʈ` 13 occurrences across Kokoro's training languages, against `s` 4336 |

None is voice-specific: all five voices fail the visarga identically.
