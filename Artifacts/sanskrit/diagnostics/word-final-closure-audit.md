# Word-final closure audit

Where do the reported final vowels come from? The answer, for every word
tested: **not the frontend.**

Method: pipeline trace for exact claims, acoustic measurement for the rest.
Baseline `0f6fb3c`, voice `hf_alpha`, 0.80.

## 1. No final vowel exists before synthesis

Canonical form, Kokoro IPA and the symbols decoded back from the token ids.
`decoded` is the ground truth for "what reached the model".

| input | canonical | Kokoro IPA | decoded tokens | round trip |
|---|---|---|---|---|
| सञ्जय | `saYjaya` | `saɲɟaja` | `s a ɲ ɟ a j a` | clean |
| सञ्जया | `saYjayA` | `saɲɟajaː` | `s a ɲ ɟ a j a ː` | clean |
| कदाचन | `kadAcana` | `kadaːcana` | `k a d a ː c a n a` | clean |
| कदाचना | `kadAcanA` | `kadaːcanaː` | `k a d a ː c a n a ː` | clean |
| **अहम्** | `aham` | `aham` | `a h a m` | clean |
| अहम | `ahama` | `ahama` | `a h a m a` | clean |
| **भगवान्** | `BagavAn` | `bʰaɡaʋaːn` | `b ʰ a ɡ a ʋ a ː n` | clean |
| भगवान | `BagavAna` | `bʰaɡaʋaːna` | `b ʰ a ɡ a ʋ a ː n a` | clean |
| **कर्मणि** | `karmaRi` | `kaɾmaɳi` | `k a ɾ m a ɳ i` | clean |
| कर्मणी | `karmaRI` | `kaɾmaɳiː` | `k a ɾ m a ɳ i ː` | clean |
| योगः | `yogaH` | `joːɡah` | `j o ː ɡ a h` | clean |
| **मामकाः** | `mAmakAH` | `maːmakaːh` | `m a ː m a k a ː h` | clean |
| **युयुत्सवः** | `yuyutsavaH` | `jujutsaʋah` | `j u j u t s a ʋ a h` | clean |
| **तत्** | `tat` | `tat` | `t a t` | clean |
| तत | `tata` | `tata` | `t a t a` | clean |
| **कृत्** | `kft` | `kɾɪt` | `k ɾ ɪ t` | clean |
| अर्जुनः | `arjunaH` | `aɾɟunah` | `a ɾ ɟ u n a h` | clean |
| रामः | `rAmaH` | `ɾaːmah` | `ɾ a ː m a h` | clean |

Every closed form ends on a consonant. Every open form ends on its inherent
vowel. Every short/long pair differs. Round trip is clean throughout — nothing
dropped, substituted or duplicated.

```
NORMALIZATION_ERROR   none
AKSHARA_PARSE_ERROR   none
INHERENT_VOWEL_ERROR  none
VIRAMA_ERROR          none
PHONOLOGY_ERROR       none
KOKORO_MAPPING_ERROR  none
TOKENIZER_ERROR       none
```

## 2. What the model does with them

Final-syllable duration, closed form against the open form it must not become.
A ratio near 1.0 means the model does not distinguish them.

| pair | closed / short | open / long | ratio | verdict |
|---|---|---|---|---|
| **तत् / तत** | 110 ms | 370 ms | **3.36** | preserved |
| **कृत् / कृत** | 110 ms | 490 ms | **4.45** | preserved |
| भगवान् / भगवान | 720 ms | 730 ms | 1.01 | **collapsed** |
| कर्मणि / कर्मणी | 950 ms | 970 ms | 1.02 | **collapsed** |
| भवति / भवती | 390 ms | 420 ms | 1.08 | **collapsed** |
| कदाचन / कदाचना | 630 ms | 580 ms | 0.92 | **collapsed** |

A clean split. **Final stops close properly** — तत् is a third the length of
तत. **Final nasals and final short vowels do not.**

```
final stop closure          FRONTEND_CORRECT, acoustically preserved
final nasal closure         ACOUSTIC_EPENTHESIS
final short vowel length    ACOUSTIC_MODEL_LIMITATION: FINAL_I_LENGTH
```

## 3. A regression this pass introduced and fixed

Two of the reported errors — युयुत्सवः as *युयुत्सवाह* and मामकाः as
*मामकाहा* — were **caused by the visarga length repair added in `8651da0`**.

That repair lengthened the vowel before a visarga by 1.3× unconditionally:

```
मामकाः     maːmak[a×1.3][ː×1.3][h×1.3]     ← ā is long: correct repair
युयुत्सवः   jujutsaʋ[a×1.3][h×1.3]          ← a is SHORT: वः became वाः
रामः       ɾaːm[a×1.3][h×1.3]              ← same fault
```

A visarga-final syllable is guru either way, but *why* decides what may move.
In मामकाः the ā is genuinely long and the model under-realises it, so restoring
its duration is a repair. In युयुत्सवः the a is genuinely short, and
lengthening it changes the vowel — which §22 forbids outright.

**Fixed:** the vowel is scaled only when it already carries a length mark. The
visarga's own duration is still scaled in both cases.

```
युयुत्सवः   jujutsaʋa[h×1.30]                 ← short a untouched
मामकाः     maːmak[a×1.30][ː×1.30][h×1.30]    ← long ā still repaired
```

## 4. The second repair: final short vowels

The model applies utterance-final lengthening — an English habit — to Sanskrit
finals that must stay laghu. Scaling them down restores the contrast:

| word | ×1.00 | ×0.85 | ×0.70 | ×0.55 |
|---|---|---|---|---|
| कर्मणि | 950 ms | 880 | 820 | 770 |
| भवति | 370 ms | 300 | 250 | 210 |
| कदाचन | 630 ms | 550 | 500 | 430 |

Against कर्मणी's 970 ms, कर्मणि goes from a ratio of 1.02 (collapsed) to 0.79.
Shipped at **0.80**, which is moderate and monotonic.

A final **long** vowel is never touched — कर्मणी, समवेता, शरीरा, भूर्मा all
scale at 1.0 — and neither is a closed syllable.

## 5. Per-item verdicts

| item | frontend | acoustic | category |
|---|---|---|---|
| सञ्जय → संजया | correct `saɲɟaja` | final short a lengthened | `ACOUSTIC_EPENTHESIS` → repaired ×0.80 |
| कदाचन → कदाचना | correct `kadaːcana` | same | `ACOUSTIC_EPENTHESIS` → repaired ×0.80 |
| कर्मणि → कर्मणी | correct, short `i` | ratio 1.02 | `ACOUSTIC_MODEL_LIMITATION: FINAL_I_LENGTH` → repaired ×0.80 |
| युयुत्सवः → युयुत्सवाह | correct `jujutsaʋah` | **our own 1.3× on a short vowel** | regression → **fixed** |
| मामकाः → मामकाहा | correct `maːmakaːh` | the `h` over-lengthened | partly our repair → h only now |
| अहम् / भगवान् final nasal | correct, closed | ratio 1.01 | `ACOUSTIC_EPENTHESIS` — not fixable |
| तत् / कृत् final stop | correct, closed | ratio 3.4–4.5 | **no defect** |
| visarga as a syllable | correct, non-syllabic | no coda frication in any voice | `ACOUSTIC_MODEL_LIMITATION: VISARGA` |
| dense clusters | correct, no epenthesis | — | no frontend defect |

## 6. Answers to the decision questions

1. **Final vowels in canonical phonemes?** No.
2. **Inserted during Kokoro mapping?** No.
3. **Inserted during tokenization?** No — round trip clean, nothing duplicated.
4. **Produced only acoustically?** Yes, for final nasals and short vowels.
   Final stops are fine.
5. **Can any voice avoid them?** No — see the voice comparison.
6. **Any safe boundary strategy?** No boundary change helps; per-token duration
   does, and is what the two repairs use.
7. **Non-syllabic visarga?** No. Established over `h`, `x`, `ɸ`, `s` and five
   voices.
8. **Can final short इ stay short?** Not by the model alone. With the ×0.80
   repair the contrast returns to 0.79.
9. **Dense clusters closed without epenthesis?** Yes — no cluster gains a vowel.
10. **Is fine-tuning required?** For the visarga and final nasal closure, yes.
