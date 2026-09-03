# validation-v4 versus validation-v3

Fourth-pass renders. v3 is preserved in `../validation-v3/` and nothing here
overwrote it.

| | v3 | v4 |
|---|---|---|
| commit | `a0b7419` | this pass |
| learning | 0.75 | **0.76** |
| recitation | 0.84 | **0.80** |
| fast | 1.00 | 1.00 |
| phonemes | — | **byte-identical to v3** |
| isolated target files | none | **10** |
| voice / model | `hf_alpha`, kokoro-v1_0 | unchanged |

**No phoneme changed in this pass.** The diagnosis found no frontend bug. The
only changes are the speed defaults and a new source-to-token alignment that
affects no audio. Evidence:
`../diagnostics/final-refinement-analysis.md`.

## Issue tracker

| Issue | v3 | v4 | Evidence | Status |
|---|---|---|---|---|
| **ए vs ई regression** | fixed | unchanged, now locked at 4 stages × 13 pairs | 120 Sanskrit tests | **RESOLVED** |
| **visarga in युयुत्सवः** | bare `h`, unfricated | identical | every symbol in the vocabulary tested; `h`, `x`, `ɸ`, `s` all ZCR 0.02–0.07 vs 0.15 threshold | **ACOUSTIC_MODEL_LIMITATION** |
| **visarga in मामकाः** | as above | identical | as above; no voice fricates it | **ACOUSTIC_MODEL_LIMITATION** |
| **long vowels before visarga** | length mark correct | identical, now asserted in position | भु 390 ms → भू 545 ms is 1.40× isolated; `ɾaːmaːh` still 90 ms shorter than `ɾaːmaː` | **ACOUSTIC_MODEL_LIMITATION** |
| **धर्मक्षेत्रे cluster** | `dʰaɾmakʂeːtɾeː` | identical | splitting gives **5** nuclei against **6** joined — splitting is worse, and the source has no space | **UNCHANGED** (correct as-is) |
| **पाण्डवाश्चैव** | `paːɳɖaʋaːʃcaɪʋa` | identical, both long vowels asserted | ण्ड, श्च, ऐ and final व all verified | **IMPROVED** (speed only) |
| **ऐ in चैव** | `caɪ` | identical | distinct from चे `ceː` at canonical, IPA, token and decoded stages | **RESOLVED** at the frontend |
| **palatal nasal in सञ्जय** | `saɲɟaja` | identical, no dental `n` | ɲ asserted; सञ्जय/संजय documented as genuine homophones | **REVIEW_REQUIRED** acoustically |
| **र्भूर्** | `heːtuɾbʰuːɾmaː` | identical, asserted | र् attaches, भ keeps `ʰ`, ऊ keeps `ː`, second र् present. Long vowel weakens to 1.16× inside the cluster | **ACOUSTIC_MODEL_LIMITATION** |
| **सङ्गोऽस्त्वकर्मणि** | `saŋɡoːstʋakaɾmaɳi` | identical | ŋɡ correct, ओ long, स्त्व one vowel, avagraha silent | **IMPROVED** (speed only) |
| **avagraha** | silent, retained as `.elision` | identical, now asserted distinct from word/pāda | not spoken, no word break, boundary preserved | **RESOLVED** |
| **स्त्व** | `stʋa` | identical | exactly one vowel; ≠ सतव | **RESOLVED** at the frontend |
| **अभ्युत्थानम्** | `abʰjuttʰaːnam` | identical, asserted | भ्+य, short उ, त्+थ, aspiration, long आ all present | **IMPROVED** (speed only) |
| **त्थ aspiration** | `ttʰa` | identical | ≠ थ, ≠ त्त, contains `ʰ` | **RESOLVED** at the frontend |
| **सृजाम्यहम्** | `sɾɪɟaːmjaham` | identical | `ɻ` untrained (0 occurrences), `ɽ` (1); no syllabic diacritic exists | **ACOUSTIC_MODEL_LIMITATION: VOCALIC_R** |
| **कृष्ण** | `kɾɪʂɳa` | identical | as above | **ACOUSTIC_MODEL_LIMITATION: VOCALIC_R** |
| **हृषीकेश** | `hɾɪʂiːkeːʃa` | identical | as above | **ACOUSTIC_MODEL_LIMITATION: VOCALIC_R** |
| **daṇḍa pauses** | 0.50 / 1.00 s | per mode, ordered and asserted above the model's own 350 ms gap | — | **RESOLVED** |
| **recitation speed** | 0.84 | **0.80** | BG 2.47's hard pāda loses 1 syllable at 0.80 vs 4 at 0.84 vs 8 at 1.00 | **IMPROVED** |
| **voice variation** | hf_alpha best | unchanged | no voice fricates the visarga; hf_alpha ties for best clusters | **ACOUSTIC_MODEL_LIMITATION** |
| **source→token alignment** | absent | **added** | each akṣara carries its character range to a token index range | **RESOLVED** |

## Durations

| verse | v3 recitation (0.84) | v4 recitation (0.80) | v4 learning (0.76) | v4 fast |
|---|---|---|---|---|
| BG 1.1 | 9.63 s | **10.38 s** | 11.65 s | 7.75 s |
| BG 2.47 | 9.65 s | **10.47 s** | 11.77 s | 7.87 s |
| BG 4.7 | 9.83 s | **10.77 s** | 11.92 s | 7.89 s |

## Isolated target files

New this pass — one word each at recitation pace, so a single problem can be
heard without hunting for it inside a verse.

| file | what to listen for | expected |
|---|---|---|
| `visarga_yuyutsavah.wav` | does the final ः have any friction? | no — limitation |
| `visarga_mamakah.wav` | as above, after a long ā | no — limitation |
| `nasal_sanjaya.wav` | is ञ palatal or a generic nasal? | **your judgement needed** |
| `cluster_pandavashchaiva.wav` | श्च, and ऐ against ए | should be distinct |
| `cluster_rbhurma.wav` | is the second र् audible? is ऊ long? | partly |
| `cluster_sangostvakarmani.wav` | ङ्ग, avagraha, स्त्व | avagraha silent |
| `cluster_abhyutthanam.wav` | is त्थ two stops with aspiration? | partly |
| `vocalic_r_srijamyaham.wav` | ऋ | approximation — limitation |
| `vocalic_r_krishna.wav` | ऋ | approximation — limitation |
| `vocalic_r_hrishikesha.wav` | ऋ | approximation — limitation |

## How to judge this set

The phoneme stream is unchanged from v3, so **only pace and pausing differ**
in the verses.

1. **`bg_02_47_recitation.wav` against v3's** — the same phonemes at 0.80
   instead of 0.84. This is the verse the measurement says benefits most.
2. **The isolated files** — these are where a specific defect can be judged
   without a verse around it.
3. **`nasal_sanjaya.wav`** is the one genuinely open question. The tokens are
   right; whether the voice resolves `ɲ` could not be measured.

The visarga and ऋ files will still sound wrong. That is expected, documented
and exhaustively established — confirming it by ear supports the finding.

## Unresolved, and why nothing was done

All left alone deliberately. See `docs/SANSKRIT_MODEL_DECISION.md`.

| | why nothing changed |
|---|---|
| **visarga** | no symbol in the vocabulary fricates in coda; `x` and `s` also add a syllable |
| **vocalic ṛ** | `ɻ` untrained, `ɽ` untrained, no syllabic diacritic exists |
| **clusters** | splitting measurably worsens articulation and misrepresents the source |
| **ɲ / ʂ resolution** | not measurable with the available methods |

Changing phonemes to mask any of these is the hack the brief forbids, and
would poison the labels a Sanskrit fine-tune depends on.
