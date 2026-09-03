# Sanskrit audio failure analysis

Diagnosis of the audible errors in the first-pass BG 1.1 / 2.47 / 4.7 renders.

**Method.** Nothing here was decided by ear — I cannot listen to the files.
Every claim is either a pipeline trace (exact, reproducible) or an acoustic
measurement on generated audio (spectral profile, nucleus duration, syllable
count). Where a claim could not be measured, it says so.

Baseline: `bcb3a30`, voice `hf_alpha`, model `kokoro-v1_0` (hexgrad/Kokoro-82M).

## Verdict summary

| # | Complaint | Layer | Fixable here |
|---|---|---|---|
| A | ए sounds like ई | **ACOUSTIC_MODEL_LIMITATION** (+ prosody contribution) | No — reported |
| B | Visarga sounds like "हा" | **KOKORO_MAPPING_ERROR** | **Yes — confirmed our bug** |
| C | Word boundaries compressed | **ACOUSTIC_MODEL_LIMITATION** (long sandhi compounds) | Partly |
| D | Daṇḍa pauses too weak | **PROSODY_CONFIGURATION_ERROR** | **Yes — confirmed our bug** |
| E | Clusters unclear | FRONTEND_CORRECT; thin acoustic support | No — reported |
| F | Vocalic ऋ weak | FRONTEND_CORRECT, documented approximation | No — reported |
| G | Vowel length inconsistent | **FRONTEND_CORRECT** — length mark verified working | No bug found |

Plus one bug found by inspection, not from the audio:

| — | `markStressOnHeavySyllables` is declared but never read | **Dead option** | **Yes** |

## 1. Pipeline traces

Full 15-field traces for all 22 target words: `traces.tsv` (regenerate with the
dump in `Tools/sanskrit-diagnose.sh`). Phonological and IPA forms:

| input | phonological (SLP1) | Kokoro IPA | round trip |
|---|---|---|---|
| क्षेत्रे | `kzetre` | `kʂeːtɾeː` | OK |
| कुरुक्षेत्रे | `kurukzetre` | `kuɾukʂeːtɾeː` | OK |
| समवेता | `samavetA` | `samaʋeːtaː` | OK |
| अधिकारस्ते | `aDikAraste` | `adʰikaːɾasteː` | OK |
| फलेषु | `Palezu` | `pʰaleːʂu` | OK |
| युयुत्सवः | `yuyutsavaha` | `jujutsaʋaha` | OK |
| मामकाः | `mAmakAha` | `maːmakaːha` | OK |
| पाण्डवाश्चैव | `pARqavAScEva` | `paːɳɖaʋaːʃcaɪʋa` | OK |
| सञ्जय | `saYjaya` | `saɲɟaja` | OK |
| कर्मण्येवाधिकारस्ते | `karmaRyevADikAraste` | `kaɾmaɳjeːʋaːdʰikaːɾasteː` | OK |
| कर्मफलहेतुर्भूर्मा | `karmaPalaheturBUrmA` | `kaɾmapʰalaheːtuɾbʰuːɾmaː` | OK |
| सङ्गोऽस्त्वकर्मणि | `saNgo'stvakarmaRi` | `saŋɡoːstʋakaɾmaɳi` | OK |
| ग्लानिर्भवति | `glAnirBavati` | `ɡlaːniɾbʰaʋati` | OK |
| अभ्युत्थानमधर्मस्य | `aByutTAnamaDarmasya` | `abʰjuttʰaːnamadʰaɾmasja` | OK |
| तदात्मानं | `tadAtmAnam` | `tadaːtmaːnam` | OK |
| सृजाम्यहम् | `sfjAmyaham` | `sɾɪɟaːmjaham` | OK |
| कृष्ण | `kfzRa` | `kɾɪʂɳa` | OK |
| हृषीकेश | `hfzIkeSa` | `hɾɪʂiːkeːʃa` | OK |
| क्षेत्रज्ञ | `kzetrajYa` | `kʂeːtɾaɟɲa` | OK |
| ज्ञान | `jYAna` | `ɟɲaːna` | OK |
| श्रद्धा | `SradDA` | `ʃɾaddʰaː` | OK |
| दुःख | `duhKa` | `duhkʰa` | OK |

**Every one of the 22 is linguistically correct at the frontend.** `eː` is
present wherever ए is written; no inherent vowel is deleted; clusters are
compositional.

## 2. Tokenizer round-trip audit — 22/22 clean

`SanskritTokenAudit.audit(phonemes:)` decodes token ids back to symbols and
diffs them against what was sent.

```
unknown: 0    dropped: 0    substituted: 0    duplicated: 0
```

**`TOKENIZER_ERROR` is ruled out for every target word.** In particular the
`e`→`i` hypothesis cannot be a tokenization fault: `e` is token 47, `i` is
token 51, they are distinct entries, and `eː` round-trips as `e ː` every time.

## 3. ए versus ई — the highest-priority hypothesis

### 3.1 Frontend and tokenization are correct

`के` → `keː` → `[53, 47, 158]` → `k e ː`.
`की` → `kiː` → `[53, 51, 158]` → `k i ː`.

Distinct at every stage. Confirmed in code by
`sanskritEAndLongIDoNotCollapse`.

### 3.2 What the model actually does

Sixteen minimal pairs were synthesized through the diagnostic phoneme entry
point, holding voice, speed and everything else identical. Measurement is the
smoothed spectral envelope of the vowel nucleus (200 Hz bands, dB relative to
the strongest band) — **not** LPC formants, which proved unreliable on a female
voice because the tracker locks onto F0.

Pairwise RMS spectral distance in the `kV` frame:

```
          kaː    keː    kiː    koː    kuː     kɛ     kA     kə
kaː       0.0   11.1   14.6    8.8    7.9   10.3   14.2    8.1
keː      11.1    0.0    7.3   12.6   11.1    3.7    5.4    4.9
kiː      14.6    7.3    0.0   13.3   11.7    9.1    8.3   10.4
koː      12.6   13.3    0.0 …
```

Reading:

- **`eː` and `iː` are genuinely distinguished** — 7.3 dB apart, *more* than
  `oː` vs `uː` (5.4 dB), which nobody would call collapsed. The model is not
  merging them.
- **But `eː` is realized centralized.** Its nearest neighbours are `ɛ` (3.7),
  `kə` (4.9) and `A` (5.4) — a mid-central region — rather than a tense
  cardinal [e]. Sanskrit ए is a close, tense, long vowel.
- `iː` shows the classic [i] signature: a deep valley at 1200–2600 Hz and a
  peak at 2800–3200 Hz. `eː` has neither.

**Verdict:**

```
FRONTEND_CORRECT
TOKENIZATION_CORRECT
ACOUSTIC_MODEL_LIMITATION — eː is rendered centralized, not collapsed onto iː
```

Per §25 the mapping is **not** being changed. `eː` is the correct symbol for ए
and stays.

### 3.3 A contributing factor: duration

Final-vowel nucleus, same word, same voice:

| variant | nucleus |
|---|---|
| `keː` in isolation | 156 ms |
| ours `kʂeːtɾeː` | **114 ms** |
| ours + stress `kʂˈeːtɾeː` | 126 ms |
| Hindi-style `kʃˈeːtɾeː` | 138 ms |

Our final ए is **27% shorter** than the same vowel in isolation, and 17%
shorter than the Hindi pipeline's rendering of the same word. A long vowel
rendered short is a real defect for a language where ए is guru.

Two causes, measured separately: the stress mark accounts for ~10% and `ʂ` vs
`ʃ` for another ~10%. The `ʂ` is correct Sanskrit and stays. The stress is
discussed in §7 below.

Note that **stress does not change vowel quality** — `kˈeː` still measures a
centralized `eː`. The stress hypothesis is refuted for complaint A and only
survives as a duration effect.

## 4. Visarga — a confirmed bug in our own mapping

This one is ours, and it is measurable.

| phonemes | span | syllable nuclei |
|---|---|---|
| `ɾaːma` | 585 ms | 3 |
| `ɾaːmah` (plain h) | 565 ms | **3** |
| `ɾaːmaha` (our echo) | 735 ms | **6** |
| `jujutsaʋah` | 980 ms | 5 |
| `jujutsaʋaha` (our echo) | 1090 ms | **6** |

**The echo vowel adds a whole syllable** — +110 to +170 ms and an extra energy
nucleus. `रामः` comes out as *rā-ma-ha*, three syllables, where Sanskrit has
two plus a light aspiration. The user's "sounds like a fully pronounced हा" is
exactly what our phonological layer asks for.

The traditional visarga echo is a *brief, voiceless* echo of the preceding
vowel. Kokoro has no way to spell that: `h` + `a` is a full voiced vowel token
and the model renders it as one. Plain `h` adds no nucleus at all — it is the
faithful choice available.

```
Layer 1 canonical Sanskrit       H, preserved and distinct from ह / ह् / हा
Layer 2 phonetic realization     brief voiceless echo of the preceding vowel
Layer 3 Kokoro approximation     h  (the echo is UNSPELLABLE, not omitted by choice)
Layer 4 acoustic workaround      none
```

**Classification: `KOKORO_MAPPING_ERROR`. Fixed** — the echo is off by
default and emits `KOKORO_APPROXIMATED_VISARGA`.

## 5. Daṇḍa pauses — a confirmed bug

Kokoro's punctuation was inspected before reaching for post-hoc silence, as
§9 requires. It does not deliver a usable pause:

| separator between two words | total span | internal silences ≥20 ms |
|---|---|---|
| none | 865 ms | [25] |
| space | 995 ms | [35, 20] |
| `,` — our pāda daṇḍa | 1040 ms | [25, 30] |
| `.` — our verse daṇḍa | 970 ms | [30, 20] |

**`,` and `.` are indistinguishable from a plain space** — 20–35 ms in every
case. There is no phrase break, and no difference between `।` and `॥`. The
structured `SanskritBoundary` information was correct; it simply had nowhere
to go, because a single `generateAudio` call cannot produce a pause the model
does not predict.

`generateContinuousAudio` already solves this for sentences by splitting and
inserting real silence. **Classification: `PROSODY_CONFIGURATION_ERROR`.
Fixed** — as a clearly separated prosody layer, documented as not part of G2P.

## 6. Word boundaries and long sandhi compounds

Word boundaries work: a space adds ~130 ms of span and a 35 ms silence.

The real problem is orthographic words that sandhi has fused. Measured on
`कर्मण्येवाधिकारस्ते` (24 phonemes, one written word):

| | span | nuclei | ms per phoneme |
|---|---|---|---|
| joined, as written | 1730 ms | 15 | **72.1** |
| split into prosodic words | 2005 ms | **21** | **83.5** |

Splitting recovers **six syllable nuclei** and 16% more time per phoneme. The
joined form is genuinely compressed: Kokoro has never seen a 24-phoneme word,
because English and Hindi words are 5–10.

**This is not fixable here.** Splitting `कर्मण्येवाधिकारस्ते` into
कर्मणि + एव + अधिकारः + ते needs a sandhi-splitting lexicon, and §20 of the
original brief forbids transforming the source text. **Classification:
`ACOUSTIC_MODEL_LIMITATION`,** with a sandhi splitter recorded as future work.
The pāda pause (§5) recovers part of the phrasing.

## 7. Stress: a dead option, and what the measurement says

`SanskritOptions.markStressOnHeavySyllables` was **declared and never read
anywhere in the package**. The documentation advertised a switch that did
nothing. That is a straightforward defect and is fixed.

Evidence bearing on whether it should be *on*:

- `ˈ` is the single most frequent token in Kokoro's training distribution —
  8542 occurrences across all nine training languages in an espeak scan,
  285 in Hindi alone. Our Sanskrit emits **zero**.
- It adds ~10% vowel duration (114 → 126 ms on क्षेत्रे).
- It does **not** change vowel quality, so it does not address complaint A.

It is nevertheless left **off by default**. Classical Sanskrit has no stress
accent; turning it on to gain 10% duration would be exactly the trade §25
forbids. It is now real, measurable and documented so the decision can be made
on evidence.

## 8. Clusters, vocalic ṛ, vowel length

**Clusters (E).** All parse compositionally and none gains a spurious vowel —
verified in the traces and asserted in tests: `क्ष`→`kʂ` (not `kaʂa`),
`स्त्व`→`stʋ`, `त्थ`→`ttʰ`, `र्भ`→`ɾbʰ`, `भ्य`→`bʰj`, `ज्ञ`→`ɟɲ`,
`ह्म`→`hm`, `ग्ल`→`ɡl`, `ञ्ज`→`ɲɟ`, `ण्ड`→`ɳɖ`, `त्म`→`tm`, `त्त्व`→`ttʋ`.
FRONTEND_CORRECT. Their audible weakness is thin acoustic support: an espeak
scan of Kokoro's training languages finds `ʂ` 4 times, `ɳ` 9, `ʈ` 13, `ɟ` 12,
`ɖ` 1, against `s` 4336 and `t` 4129. **ACOUSTIC_MODEL_LIMITATION.**

**Vocalic ṛ (F).** Emitted as `ɾɪ` with `KOKORO_APPROXIMATION` on every
occurrence, because Kokoro's vocabulary has no syllabic diacritic — neither
U+0329 nor U+0325 — so `r̩` cannot be written at all. Canonical stays `f`.
Unchanged; already correct and already reported.

**Vowel length (G).** No bug found. The length mark is functional:

| | short | long | gain |
|---|---|---|---|
| `ke` / `keː` | 126 ms | 156 ms | +24% |
| `ko` / `koː` | 132 ms | 162 ms | +23% |
| `kɛ` / `kɛː` | 90 ms | 174 ms | +93% |

**FRONTEND_CORRECT**, and speed does not alter it — see the speed audit.

## 9. Reference comparison

`reference-comparison.tsv`. All 22 targets are `ALL_AGREE` with Vāgdhenu on
the canonical form. The espeak column is a Hindi proxy — there is no Sanskrit
voice in espeak 1.52 — and differs by construction because it deletes schwas.
No implementation change was made to chase agreement.

## 10. What was changed, and what was not

**Changed** (each with a failing test first):

1. Visarga echo off by default — §4, measured spurious syllable.
2. Pāda and verse pauses via a separated prosody layer — §5, measured 25 ms.
3. `markStressOnHeavySyllables` implemented rather than dead — §7.

**Deliberately not changed:**

- `eː` for ए. It is correct and the model is what falls short (§3).
- `ʂ` for ष. Correct, and thinly trained (§8).
- `ɾɪ` for ऋ. Already an explicitly reported approximation (§8).
- Sandhi compounds. Needs a lexicon and is out of scope (§6).
