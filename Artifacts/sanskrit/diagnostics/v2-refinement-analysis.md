# Sanskrit v2 refinement analysis

Third-pass diagnosis, after the v2 build fixed the systematic ए→ई percept and
the spurious visarga syllable.

**Method.** Nothing decided by ear. Every claim is a pipeline trace (exact and
reproducible) or an acoustic measurement on generated audio — zero-crossing
rate and high-frequency energy for frication, energy-nucleus counts for
syllable articulation, spectral envelopes for vowel quality. Where a claim
could not be measured, it says so.

Baseline `8e74575`, voice `hf_alpha` unless stated, model `kokoro-v1_0`.

## Headline

**No frontend bug was found anywhere in this pass.** All fifteen target words
are canonically correct, and all round-trip through the tokenizer with zero
drops, substitutions or duplications. The remaining defects are acoustic, and
the voice comparison shows they are model-level rather than voice-specific.

| Area | Frontend | Tokenizer | Verdict |
|---|---|---|---|
| ए vs ई | correct | correct | **fixed in v2, now locked by tests** |
| visarga | correct | correct | `ACOUSTIC_MODEL_LIMITATION` |
| long vowel before visarga | correct | correct | `ACOUSTIC_MODEL_LIMITATION` |
| clusters | correct | correct | `ACOUSTIC_MODEL_LIMITATION` (thin support) |
| vocalic ऋ | correct + reported | correct | `ACOUSTIC_MODEL_LIMITATION: VOCALIC_R` |
| nasals | correct | correct | frontend fine; see §7 |
| sibilants | correct | correct | frontend fine |
| daṇḍa pauses | correct | n/a | `PROSODY_ERROR`, fixed in v2, tuned here |
| speed | n/a | n/a | `PROSODY_ERROR` — 1.0 is wrong for Sanskrit |

## 1. Pipeline traces

Fifteen words, every stage. Full 15-field rows in `traces.tsv`; regenerate with
`Tools/sanskrit-diagnose.sh`.

| input | canonical | Kokoro IPA | round trip | approximation |
|---|---|---|---|---|
| धर्मक्षेत्रे | `Darmakzetre` | `dʰaɾmakʂeːtɾeː` | OK | — |
| कुरुक्षेत्रे | `kurukzetre` | `kuɾukʂeːtɾeː` | OK | — |
| युयुत्सवः | `yuyutsavaH` | `jujutsaʋah` | OK | visarga |
| मामकाः | `mAmakAH` | `maːmakaːh` | OK | visarga |
| पाण्डवाश्चैव | `pARqavAScEva` | `paːɳɖaʋaːʃcaɪʋa` | OK | — |
| सञ्जय | `saYjaya` | `saɲɟaja` | OK | — |
| कर्मण्येवाधिकारस्ते | `karmaRyevADikAraste` | `kaɾmaɳjeːʋaːdʰikaːɾasteː` | OK | — |
| कर्मफलहेतुर्भूर्मा | `karmaPalaheturBUrmA` | `kaɾmapʰalaheːtuɾbʰuːɾmaː` | OK | — |
| सङ्गोऽस्त्वकर्मणि | `saNgo'stvakarmaRi` | `saŋɡoːstʋakaɾmaɳi` | OK | — |
| ग्लानिर्भवति | `glAnirBavati` | `ɡlaːniɾbʰaʋati` | OK | — |
| अभ्युत्थानमधर्मस्य | `aByutTAnamaDarmasya` | `abʰjuttʰaːnamadʰaɾmasja` | OK | — |
| तदात्मानं | `tadAtmAnaM` | `tadaːtmaːnam` | OK | — |
| सृजाम्यहम् | `sfjAmyaham` | `sɾɪɟaːmjaham` | OK | vocalic ṛ |
| कृष्ण | `kfzRa` | `kɾɪʂɳa` | OK | vocalic ṛ |
| हृषीकेश | `hfzIkeSa` | `hɾɪʂiːkeːʃa` | OK | vocalic ṛ |

Boundaries are preserved as structure throughout — `word`, `pada`, `verse`,
`elision` — and each akṣara still carries its source offsets, so the chain
source range → word → akṣara → canonical → tokens is intact.

## 2. Visarga — `ACOUSTIC_MODEL_LIMITATION`

The reported "still sounds like हा" is real, and it is **not** the frontend.
v2 already emits a bare `h` with no echo vowel, and that is what reaches the
model.

### What the model does with a coda `h`

Zero-crossing rate and high-frequency energy over the last 120 ms. A real
visarga is a voiceless fricative: high on both. A vowel is low on both.

| phonemes | span | ZCR | HF ratio | reading |
|---|---|---|---|---|
| `maː` | 480 ms | 0.043 | 0.011 | vowel |
| **`maːh`** | 525 ms | **0.040** | **0.006** | **vowel — no frication at all** |
| `maːs` | 570 ms | 0.081 | 0.033 | weak frication |
| `maːx` | 500 ms | 0.028 | 0.002 | none |
| `kaːh` | 505 ms | 0.026 | 0.001 | none |
| `jujutsaʋah` | 985 ms | 0.033 | 0.013 | none |

`maːh` is acoustically indistinguishable from `maː`. The `h` produces no
frication whatever, so the ear hears the vowel running on — which is exactly
the "हा" percept.

### It is positional, and that is the explanation

| position | ZCR | HF ratio |
|---|---|---|
| onset — `haːma`, first 25% | **0.122** | **0.135** |
| coda — `maːh`, last 25% | 0.040 | 0.006 |
| medial — `maːhaː`, middle | 0.027 | 0.002 |

**Kokoro renders `h` correctly as an onset and not at all elsewhere.** In its
nine training languages `h` is essentially onset-only, so a coda `h` is out of
distribution. Even `x`, a much stronger fricative, gets no frication in coda.

```
FRONTEND_CORRECT       canonical H, distinct from ह / ह् / हा
TOKENIZATION_CORRECT   round-trips as `h`, token 50
ACOUSTIC_MODEL_INSUFFICIENT — coda fricatives are not realised
```

No mapping change is available that would not be a hack. `s` is the only coda
symbol with measurable frication, and visarga is not `s`. Per §16 nothing was
changed. `KOKORO_APPROXIMATED_VISARGA` is emitted on every occurrence.

## 3. Long vowels before visarga — `ACOUSTIC_MODEL_LIMITATION`

The frontend keeps the length mark, in the right place, every time —
`maːmakaːh`, `paːɳɖaʋaːh`, `dʰiːh`, `bʰuːh`, `haɾeːh`, `ɡuɾoːh`, all asserted
in `longVowelsSurviveBeforeVisarga`.

The model shortens what it is given. Total speech span, same word with and
without the visarga:

| | without | with `h` | change |
|---|---|---|---|
| `ɾaːmaː` / `ɾaːmaːh` | 670 ms | 580 ms | **−90 ms** |
| `maːmakaː` / `maːmakaːh` | 815 ms | 760 ms | **−55 ms** |
| `dʰiː` / `dʰiːh` | 600 ms | 560 ms | −40 ms |

Adding a phoneme makes the word *shorter*. The model compresses the preceding
long vowel to accommodate a segment it does not know how to realise. Same
cause as §2, and the same conclusion.

## 4. Clusters — frontend correct

Every cluster the brief lists parses compositionally with no epenthetic vowel,
no dropped consonant, and aspiration intact:

| cluster | canonical | IPA | | cluster | canonical | IPA |
|---|---|---|---|---|---|---|
| र्मक्ष | `rmakza` | `ɾmakʂa` | | भ्युत्थ | `ByutTa` | `bʰjuttʰa` |
| श्चै | `ScE` | `ʃcaɪ` | | त्थ | `tTa` | `ttʰa` |
| ण्ये | `Rye` | `ɳjeː` | | त्म | `tma` | `tma` |
| र्भू | `rBU` | `ɾbʰuː` | | ञ्ज | `Yja` | `ɲɟa` |
| ङ्गो | `Ngo` | `ŋɡoː` | | सृ | `sf` | `sɾɪ` |
| स्त्व | `stva` | `stʋa` | | निर्भ | `nirBa` | `niɾbʰa` |

None of the invalid expansions the brief names is possible, and each is now an
assertion: क्ष ≠ कष, स्त्व ≠ सतव, त्थ ≠ ततह, र्भू ≠ रभू, भ्य ≠ भिया, ञ्ज ≠ नज.

Their audible weakness is training support. An espeak scan across Kokoro's
nine training languages counts `ʂ` 4 times, `ɖ` 1, `ɳ` 9, `ɟ` 12, `ʈ` 13 —
against `s` 4336 and `t` 4129. **`ACOUSTIC_MODEL_LIMITATION`**, worsened by
speed (§8).

## 5. Vocalic ऋ — `ACOUSTIC_MODEL_LIMITATION: VOCALIC_R`

Canonical stays `f` in all eight test words. The Kokoro layer renders `ɾɪ` and
emits `KOKORO_APPROXIMATION` every time.

The cause is a hard token gap, not a choice: **Kokoro's vocabulary contains no
syllabic diacritic** — neither U+0329 nor U+0325 — so `r̩` cannot be written at
all. The alternative `ɾu` is available as an option and is equally traditional
(South Indian); both are one light syllable, so metre survives either way.

Per §12, no further Sanskrit-rule adjustment follows from this point. The
classification is final until the model or vocabulary changes.

## 6. Boundaries and avagraha

Word boundaries survive as spaces and are asserted. Avagraha is silent, is not
a word break, and is retained as `.elision` so source alignment for
highlighting is preserved — `सङ्गोऽस्त्वकर्मणि` → `saŋɡoːstʋakaɾmaɳi`, one
unbroken stretch, with the boundary still in `Result.units`.

The long-compound compression measured in the previous pass is unchanged and
unfixable here: splitting `कर्मण्येवाधिकारस्ते` into prosodic words recovers six
syllable nuclei, but doing so needs a sandhi-splitting lexicon and would
transform the source text. Recorded as future work.

## 7. Nasals and sibilants — frontend correct

All five nasals stay distinct: `saŋɡa`, `saɲɟaja`, `paːɳɖaʋa`, `santa`,
`sampad`. **सञ्जय keeps its palatal `ɲ`** and contains no dental `n` — the
specific collapse the brief warns about is asserted as impossible.

All three sibilants stay distinct: `ʃakti`, `ʂaʈ`, `sat`.

Whether the *voice* resolves `ɲ` from `n`, or `ʂ` from `ʃ`, is a separate
question this pass could not settle by measurement — the contrast is spectral
and short, and the nucleus-counting method is not sensitive enough. Flagged
`REVIEW_REQUIRED` rather than claimed either way.

## 8. Speed — `PROSODY_ERROR`, and the most actionable finding

Identical phonemes and token ids at every rate; only `speed` changed. Counting
separately articulated energy nuclei against the 16 syllables BG 1.1's first
pāda actually has:

| speed | duration | nuclei | mean nucleus | ms/phoneme |
|---|---|---|---|---|
| 0.72 | 4750 ms | 18 | 106 ms | 105.6 |
| 0.78 | 4420 ms | **20** | 93 ms | 98.2 |
| 0.84 | 3960 ms | **19** | 86 ms | 88.0 |
| 0.90 | 3475 ms | 17 | 85 ms | 77.2 |
| **1.00** | 3255 ms | **15** | 92 ms | 72.3 |

**At 1.0 the model resolves fewer nuclei than the pāda has syllables.**
Syllables are merging. From 0.84 down every syllable is separately
articulated. This is a measure of articulation, not of beauty, but it is
objective and it points one way.

Hence the three modes, with the measured basis recorded on the type:

| mode | speed | pāda | verse |
|---|---|---|---|
| learning | 0.75 | 0.70 s | 1.30 s |
| **recitation** | **0.84** | 0.50 s | 1.00 s |
| fast | 1.00 | 0.40 s | 0.80 s |

## 9. Voice comparison — the failures are not voice-specific

Seven words × five voices, identical text, phonemes, tokens and speed.
Full table in `v2-voice-comparison.tsv`.

| voice | words with a measured defect |
|---|---|
| **hf_alpha** | **3 / 7** |
| hf_beta | 5 / 7 |
| af_heart | 5 / 7 |
| hm_omega | 6 / 7 |
| hm_psi | 7 / 7 |

**Every voice fails the visarga**, tail ZCR 0.017–0.066 against a 0.10
threshold — not one renders a coda `h` with frication. Every voice merges
syllables on at least two of the seven words.

`hf_alpha` is the best of the five and is kept as the default. It does not
escape either problem, so per §15 the classification is **model-level, not
voice-specific**.

## 10. Failure categories

| Finding | Category |
|---|---|
| ए→ई | *resolved in v2* — frontend and tokenization both correct |
| coda `h` gets no frication | `ACOUSTIC_MODEL_LIMITATION` |
| long vowel shortened before visarga | `ACOUSTIC_MODEL_LIMITATION` |
| retroflex/palatal thinly trained | `ACOUSTIC_MODEL_LIMITATION` |
| vocalic ṛ | `ACOUSTIC_MODEL_LIMITATION: VOCALIC_R` |
| syllables merge at speed 1.0 | `PROSODY_ERROR` — fixed by the modes |
| long sandhi compounds compressed | `ACOUSTIC_MODEL_LIMITATION` |
| ɲ / ʂ acoustic resolution | `REVIEW_REQUIRED` — not measurable here |
| anything in normalization, parsing, phonology, mapping, tokenization | **none found** |
