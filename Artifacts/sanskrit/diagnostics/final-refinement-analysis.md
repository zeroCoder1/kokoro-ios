# Sanskrit final refinement analysis

Fourth-pass diagnosis. The v3 build resolved the systematic ए→ई percept; this
pass examines what is left and asks whether any of it is still ours.

**Method.** Nothing decided by ear. Every claim is a pipeline trace (exact,
reproducible) or an acoustic measurement — zero-crossing rate and
high-frequency energy for frication, energy-nucleus counts against known
syllable counts, spectral envelopes for vowel quality. Where a claim could not
be measured, it says so.

Baseline `a0b7419`, voice `hf_alpha` unless stated, model `kokoro-v1_0`.

## Headline

**No frontend bug was found.** All eighteen target words are canonically
correct and round-trip through the tokenizer with zero drops, substitutions or
duplications. Two things did change, neither of them a phoneme:

1. **Source-to-token alignment now exists** — the chain source range → akṣara
   → canonical → phonemes → token indices was previously broken at the
   phonology layer. This closes it, which the highlighting feature needs and
   which §3 of the brief asks for as trace field 14.
2. **Recitation speed moves 0.84 → 0.80** on a three-pāda measurement.

Everything else is `ACOUSTIC_MODEL_LIMITATION`, now established exhaustively
rather than by inference.

## 1. Pipeline traces

Eighteen items, every stage. Full rows in `final-traces.tsv`.

| input | canonical | Kokoro IPA | round trip | approximation |
|---|---|---|---|---|
| धर्मक्षेत्रे | `Darmakzetre` | `dʰaɾmakʂeːtɾeː` | OK | — |
| युयुत्सवः | `yuyutsavaH` | `jujutsaʋah` | OK | visarga |
| मामकाः | `mAmakAH` | `maːmakaːh` | OK | visarga |
| पाण्डवाश्चैव | `pARqavAScEva` | `paːɳɖaʋaːʃcaɪʋa` | OK | — |
| चैव | `cEva` | `caɪʋa` | OK | — |
| सञ्जय | `saYjaya` | `saɲɟaja` | OK | — |
| कर्मण्येवाधिकारस्ते | `karmaRyevADikAraste` | `kaɾmaɳjeːʋaːdʰikaːɾasteː` | OK | — |
| कर्मफलहेतुर्भूर्मा | `karmaPalaheturBUrmA` | `kaɾmapʰalaheːtuɾbʰuːɾmaː` | OK | — |
| भूर्मा | `BUrmA` | `bʰuːɾmaː` | OK | — |
| सङ्गोऽस्त्वकर्मणि | `saNgo'stvakarmaRi` | `saŋɡoːstʋakaɾmaɳi` | OK | — |
| सङ्गः | `saNgaH` | `saŋɡah` | OK | visarga |
| सोऽहम् | `so'ham` | `soːham` | OK | — |
| ग्लानिर्भवति | `glAnirBavati` | `ɡlaːniɾbʰaʋati` | OK | — |
| अभ्युत्थानम् | `aByutTAnam` | `abʰjuttʰaːnam` | OK | — |
| तदात्मानम् | `tadAtmAnam` | `tadaːtmaːnam` | OK | — |
| सृजाम्यहम् | `sfjAmyaham` | `sɾɪɟaːmjaham` | OK | vocalic ṛ |
| कृष्ण | `kfzRa` | `kɾɪʂɳa` | OK | vocalic ṛ |
| हृषीकेश | `hfzIkeSa` | `hɾɪʂiːkeːʃa` | OK | vocalic ṛ |

**Source alignment**, now available on every result. `मामकाः`:

```
[0..<2] मा    mA    maː    tokens[0..<3] = 55 43 158
[2..<3] म     ma    ma     tokens[3..<5] = 55 43
[3..<6] काः   kAH   kaːh   tokens[5..<9] = 53 43 158 50
```

## 2. Visarga — `ACOUSTIC_MODEL_LIMITATION: VISARGA`, exhaustively

Previous passes showed `h` gets no frication in coda. This pass tested **every
defensible mapping in the vocabulary**, to answer §8's question directly:
*can Kokoro produce a non-syllabic visarga at all?*

Tail 110 ms; frication needs ZCR > 0.15 and HF > 0.25.

| variant | ZCR | HF | frication | extra syllable |
|---|---|---|---|---|
| `kaːh` — current | 0.025 | 0.001 | no | no |
| `kaːx` — jihvāmūlīya | 0.071 | 0.018 | no | no |
| `kaːɸ` — upadhmānīya | 0.023 | 0.001 | no | no |
| `kaːs` — sibilant | 0.027 | 0.000 | no | **yes** |
| `ɾaːmax` | 0.025 | 0.002 | no | **yes** |
| `jujutsaʋax` | 0.038 | 0.008 | no | **yes** |
| `kaːha` — *negative control* | 0.023 | 0.002 | no | yes |

**No mapping produces frication.** `x` and `ɸ` — genuine voiceless fricatives,
and the Classical allophones — behave exactly like `h`, and `x` additionally
adds a syllable in three of the words tested. `s` adds one too.

The cause was established last pass and holds: the failure is **positional**.
The same `h` as an onset in `haːma` measures ZCR 0.122 / HF 0.135; in coda it
measures nothing. In Kokoro's nine training languages `h` is essentially
onset-only.

```
FRONTEND_CORRECT        canonical H, distinct from ह / ह् / हा at every stage
TOKENIZATION_CORRECT    round-trips as `h`, token 50
ACOUSTIC_MODEL_INSUFFICIENT — coda fricatives are not realised, by any symbol
```

The current mapping is kept: it is the only one that adds no syllable.
`KOKORO_APPROXIMATED_VISARGA` is emitted on every occurrence.

## 3. Long vowels before visarga — frontend correct

The length mark is present, and immediately before the `h`, in all nine test
words — asserted in `preVisargaLongVowelSurvives`. Measured, the model still
compresses: `ɾaːmaːh` is 90 ms *shorter* than `ɾaːmaː`. Same cause as §2.

Isolated, the length mark works: भु 390 ms → भू 545 ms is **1.40×**. Inside a
cluster it is weakened: र्भु 525 ms → र्भू 610 ms is only **1.16×**.

## 4. Vocalic ऋ — `ACOUSTIC_MODEL_LIMITATION: VOCALIC_R`, now decisive

Nine consonant contexts × five candidate mappings, plus eleven real words.

The decisive evidence is training support, counted from an espeak scan across
Kokoro's nine training languages:

| candidate | occurrences | languages |
|---|---|---|
| `ɾ` | 532 | en-us, es, hi, it, pt-br |
| `ɪ` | 8012 | en-gb, en-us, hi, it, ja, pt-br |
| `u` | 817 | eight languages |
| **`ɽ`** retroflex flap | **1** | ja only |
| **`ɻ`** retroflex approximant | **0** | **none** |

**The two tokens that could carry rhotic vowel colour are untrained.** `ɻ` was
never produced by any training language and `ɽ` once. That shows in the audio:
both stretch to 580–725 ms in a frame where the trained options take 400–500 ms
— the model does not know what they are.

So the usable options are `ɾɪ` and `ɾu`, both well-trained, neither a syllabic
rhotic. Kokoro's vocabulary has **no syllabic diacritic** (U+0329, U+0325 both
absent), so `r̩` is unwritable in principle, not merely inconvenient.

One observation for the record, not acted on: `ɾu` resolves as a single energy
nucleus in 8 of 9 consonant contexts against `ɾɪ`'s 5 of 9, and ऋ is one light
syllable. Both are traditional — `ɾɪ` North Indian, `ɾu` South Indian — so this
is a regional choice, not a correctness one, and it stays a documented option
rather than a unilateral default change. **REVIEW_REQUIRED.**

Per §10, no further G2P change follows: canonical correctness is proven.

## 5. Palatal nasal ञ — frontend correct

`ɲ` in every test word — सञ्जय, ज्ञान, विज्ञान, पञ्च, अञ्जलि, चञ्चल, यज्ञ. सञ्जय
contains no dental `n` at all. All five nasals produce five different readings.

**Documented behaviour, not a collapse:** सञ्जय and संजय differ canonically
(`saYjaya` vs `saMjaya`) and converge in pronunciation (`saɲɟaja`). That is
correct Sanskrit — an anusvāra before a palatal stop *is* the palatal nasal —
so they are genuine homophones. §13 asks for this to be documented rather than
silent; it is, and `sanjayaAndSamjayaAreDocumentedHomophones` pins both halves.

Whether the *voice* resolves `ɲ` from `n` acoustically could not be settled by
measurement — the contrast is short and spectral, and nucleus counting is not
sensitive enough. **REVIEW_REQUIRED: PALATAL_NASAL.**

## 6. Clusters — frontend correct, and splitting makes it worse

| cluster | canonical | IPA | | cluster | canonical | IPA |
|---|---|---|---|---|---|---|
| र्मक्ष | `rmakza` | `ɾmakʂa` | | त्थ | `tTa` | `ttʰa` |
| श्चै | `ScE` | `ʃcaɪ` | | भ्युत्थ | `ByutTa` | `bʰjuttʰa` |
| ण्ये | `Rye` | `ɳjeː` | | ङ्गो | `Ngo` | `ŋɡoː` |
| र्भूर् | `rBUr` | `ɾbʰuːɾ` | | स्त्व | `stva` | `stʋa` |

None gains a vowel, drops a consonant or loses aspiration, and every invalid
expansion the brief names is now an assertion.

**धर्मक्षेत्रे, joined against split** — the "mechanically assembled" report:

| | span | nuclei |
|---|---|---|
| `dʰaɾmakʂeːtɾeː` as written | 1090 ms | **6** |
| `dʰaɾma kʂeːtɾeː` split | 1120 ms | **5** |

Splitting **reduces** articulated nuclei. It would also insert a boundary the
source does not contain. No change is justified, and none was made.

**ऐ in चैव** is distinct at every stage: `caɪ` against `ceː` for चे. The
diphthong resolves as one nucleus, which is what a diphthong should do.

## 7. Speed — the one actionable finding

Three pādas, identical phonemes and token ids at every rate, only `speed`
changed. The figure is **how many syllables went missing** against the count
each pāda actually has.

| speed | BG 1.1 (16) | BG 2.47 (18) | BG 4.7 (18) |
|---|---|---|---|
| 0.72 | ok | −3 | ok |
| 0.76 | ok | −3 | ok |
| **0.80** | **ok** | **−1** | **ok** |
| 0.84 *(was default)* | ok | **−4** | ok |
| 0.88 | −1 | −6 | −2 |
| 0.92 | ok | −6 | −5 |
| 1.00 | ok | −8 | −2 |

BG 2.47's first pāda is the discriminating case — it contains
कर्मण्येवाधिकारस्ते, twenty-four phonemes in one orthographic word, and never
reaches its full count. **0.80 is where it comes closest and the other two are
clean.** Recitation moves 0.84 → 0.80; learning 0.75 → 0.76.

## 8. Voice comparison — not voice-specific

Eight words × five voices, everything else identical, at 0.80.
Full table in `final-voice-comparison.tsv`.

| voice | words reaching their syllable count | visarga |
|---|---|---|
| **hf_alpha** | **4 / 8** | unfricated, ZCR 0.053–0.088 |
| af_heart | 4 / 8 | unfricated, 0.048–0.073 |
| hf_beta | 3 / 8 | unfricated, 0.054–0.067 |
| hm_omega | 1 / 8 | unfricated, 0.021–0.022 |
| hm_psi | 1 / 8 | unfricated, 0.049–0.077 |

**No voice fricates the visarga** — every one is far below the 0.15 threshold.
`hf_alpha` ties for best and is kept for its Indic phoneme coverage. The
failures are model-level.

## 9. Failure categories

| Finding | Category |
|---|---|
| coda visarga unrealisable by any symbol | `ACOUSTIC_MODEL_LIMITATION: VISARGA` |
| long vowel compressed before visarga | `ACOUSTIC_MODEL_LIMITATION` |
| vocalic ṛ: `ɻ` untrained (0), `ɽ` untrained (1), no syllabic diacritic | `ACOUSTIC_MODEL_LIMITATION: VOCALIC_R` |
| dense clusters compress; splitting makes it worse | `ACOUSTIC_MODEL_LIMITATION` |
| syllables merge above 0.80 | `PROSODY_ERROR` — fixed |
| source→token alignment missing | `ALIGNMENT_ERROR` — **fixed** |
| ɲ / ʂ acoustic resolution | `REVIEW_REQUIRED` |
| ऋ as `ɾɪ` vs `ɾu` | `REVIEW_REQUIRED` — regional choice |
| normalization, parsing, phonology, mapping, tokenization | **none found** |
