# Classical Sanskrit in Kokoro

A Sanskrit front end for Bhagavad Gita recitation. Classical Sanskrit in
Devanagari, phonemized for Kokoro's IPA vocabulary — deterministic, offline,
and sharing no rules with the Hindi engine.

| Document | What it holds |
|---|---|
| **this file** | architecture, scope, how to use it, what is left |
| `SANSKRIT_G2P_RESEARCH.md` | the reference comparison matrix and every decision |
| `SANSKRIT_SOURCES.md` | the projects consulted, their licences, what was reused |
| `SANSKRIT_KOKORO_COMPATIBILITY.md` | per-sound token audit against the 114-entry vocabulary |

## Using it

```swift
let tts = try KokoroTTS(modelPath: modelURL, g2p: .sanskrit)
let (audio, _) = try tts.generateAudio(
  voice: voice,
  language: .sa,
  text: "धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।",
  speed: 0.7          // genuine slow articulation, not a slowed-down render
)
```

Inspecting, which is how a verse gets reviewed:

```bash
Tools/sanskrit-inspect.sh "धर्मक्षेत्रे कुरुक्षेत्रे"
```

Comparing against the reference implementations (development only, needs local
clones — see `SANSKRIT_SOURCES.md`):

```bash
Tools/sanskrit-reference-compare.py --refs /tmp/refs --corpus Tools/sanskrit-listening-corpus.txt
```

## Architecture

Five layers, each with one job. Only the last one knows Kokoro exists.

```
Devanagari
  │
  ├─ SanskritNormalizer      Unicode composition, join controls, ॐ → ओम्,
  │                          Vedic accents dropped with a warning.
  │                          Devanagari in, Devanagari out.
  │
  ├─ SanskritAksharaParser   akṣaras: onset cluster, vowel, marks, plus
  │                          structured boundaries and source offsets.
  │                          Compositional — conjuncts need no table.
  │
  ├─ SanskritPhonology       which sounds occur: anusvāra by following place,
  │                          visarga by position, chandrabindu.
  │                          Canonical form is SLP1. No Kokoro anywhere.
  │
  ├─ SanskritKokoroMapper    canonical → Kokoro IPA, warning on every
  │                          approximation. The only model-specific layer.
  │
  └─ Tokenizer               Kokoro token ids
```

`SanskritPhonemizer` orchestrates them and keeps **every** intermediate form,
because a wrong pronunciation is diagnosed by finding the layer that
introduced it, not by listening harder. `SanskritG2PProcessor` is the
`G2PProcessor` conformance; `G2P.sanskrit` and `Language.sa` are the routing.

**Why the canonical layer is separate.** Retargeting a different acoustic model
means writing a new mapper and leaving the phonology alone. It is also what
keeps §37 enforceable: everything contested about *Kokoro* lives in one file,
so linguistics cannot quietly be bent to flatter a voice.

### Why not Vāgdhenu's Kannada routing

Their tech report gives the reason twice: IndicF5 is a **script-input** model,
and its Devanagari embeddings carry Hindi reading habits, so Devanagari
triggers Hindi schwa deletion and transliterating to Kannada escapes it.

Kokoro is a **phoneme-input** model. We compute the IPA ourselves, so there is
no script embedding and no habit to escape — schwa deletion cannot happen
unless we write code that does it, and we do not. Reproducing the Kannada step
would be cargo cult. What we did take is the layering underneath it, and SLP1.
Full argument: `SANSKRIT_G2P_RESEARCH.md` §5.

## Scope

**In:** Classical Sanskrit in Devanagari. The Bhagavad Gita is the target
corpus.

**Out, deliberately:**

- **Vedic accent** — udātta, anudātta, svarita. The marks are recognised,
  dropped, and reported as `VEDIC_ACCENT_IGNORED` rather than silently
  ignored. Vedic recitation is a separate project with a separate acoustic
  requirement.
- **Sandhi rewriting.** The Gita text already carries its written sandhi.
  Vāgdhenu can rewrite utva/rutva/lopa; we do not, because that transforms the
  source into a different surface form and §20 forbids it. Only
  pronunciation-level behaviour is applied.
- **Mixed script.** Classical recitation has no English and no digits in it.
  Both are dropped with a warning rather than guessed at — a deliberate
  difference from `HindiG2PProcessor`, which mixes scripts because Hindi news
  does.
- **Forced alignment.** Not implemented. The information a future
  word-highlighting feature needs is preserved: each akṣara carries
  `sourceOffsets` into the normalized text, and the chain source word → akṣara
  → canonical phoneme → Kokoro token survives on `SanskritPhonemizer.Result`.

## Sanskrit is not Hindi

A hard rule, and the reason this is a separate engine rather than a flag on the
Hindi one. `SanskritPhonemizer` shares no code with `HindiPhonemizer` and can
reach none of its rules.

| | Hindi (correctly, for Hindi) | Sanskrit |
|---|---|---|
| कर्म | `kʌrm` — schwa deleted | `kaɾma` |
| final inherent vowel | deleted | **never** deleted |
| क्ष | `kʃ` — fused modern reading | `kʂ` — compositional |
| ज्ञ | `ɡj` — fused modern reading | `ɟɲ` — compositional |
| ए / ओ | `eː` / `oː` | `eː` / `oː`, always long |
| stress | assigned by syllable weight | **none** — Sanskrit has no stress accent |
| lexicon | overrides, compounds, acronyms, Hinglish | none |
| numbers | `HindiNumbers` expands digits | not used |

The only shared utilities are script-range predicates, which are
linguistically neutral. A test runs the same words through both engines and
requires them to differ, so this is demonstrated rather than merely intended.

## Phoneme inventory

Full per-sound audit with token ids: `SANSKRIT_KOKORO_COMPATIBILITY.md`.

**Vowels** — `a aː i iː u uː eː aɪ oː aʊ`, plus the four vocalic liquids.
Length is phonemic and all five pairs survive. ए and ओ carry an explicit length
mark because they are always guru in Sanskrit and metre depends on it.

**Consonants** — all 33, with all ten aspiration contrasts, all five nasals
(`ŋ ɲ ɳ n m`), all three sibilants (`ʃ ʂ s`), and the retroflex/dental
contrast intact.

**Marks** — anusvāra takes the homorganic nasal before a varga stop and
nasalises the vowel before a continuant; visarga takes its echo vowel at a
pause (`रामः` → *rāmaha*) and a plain `h` inside a word; chandrabindu
nasalises; avagraha is silent; daṇḍa and double daṇḍa are two pause strengths.

### What Kokoro cannot do

**Five approximations, four of them one problem.** Kokoro's vocabulary has no
syllabic diacritic — neither U+0329 nor U+0325 — so `r̩` and `l̩` cannot be
written at all. ऋ ॠ ऌ ॡ are therefore rendered `ɾɪ ɾiː lɪ liː`, each one light
syllable so metre survives. The fifth is anusvāra before a continuant,
rendered as vowel nasalisation because a nasalised approximant is unspellable.

**One unsupported letter.** ळ → `l`, because `ɭ` (U+026D) is not in the
vocabulary. It does not occur in the Classical Gita text.

**Nothing is silent about any of it.** Every one emits a warning:

```
KOKORO_APPROXIMATION: vocalic ṛ (ऋ) → ɾɪ (no syllabic diacritic in the Kokoro vocabulary)
KOKORO_UNSUPPORTED: ḷa (ळ) — ɭ (U+026D) is not in the Kokoro vocabulary; read as l
```

## Options

The rules the references genuinely disagree about are `SanskritOptions` fields
rather than buried constants, so a decision can be *heard* rather than argued
about. Defaults are argued for in `SANSKRIT_G2P_RESEARCH.md`.

| Option | Default | Alternative |
|---|---|---|
| `anusvaraBeforeContinuant` | `.nasalizeVowel` (Vāgdhenu) | `.labialNasal` (EdgeSanskrit) |
| `internalVisarga` | `.aspirate` | `.placeAssimilated` (jihvāmūlīya/upadhmānīya) |
| `vocalicLiquid` | `.ri` (North Indian) | `.ru` (South Indian) |
| `palatalSibilant` | `.postalveolar` `ʃ` | `.alveoloPalatal` `ɕ` |
| `palatalStops` | `.stops` `c ɟ` | `.affricates` `ʧ ʤ` |
| `visargaEchoAtPause` | `true` | `false` |
| `markStressOnHeavySyllables` | `false` | `true` |

None of these exists to make the current voices sound better. See below.

## Speed

Sanskrit goes through Kokoro's ordinary generation path, where `speed` divides
the predicted phoneme durations before the decoder runs
(`KokoroTTS.predictDurations`). The model genuinely articulates slowly; there
is no DSP slowdown of a normal-speed render anywhere in the path. Learning-mode
speed control therefore works for Sanskrit exactly as it does for the other
languages, with no Sanskrit-specific code.

## The three gates

**Gate 1 — linguistic front end.** Passes. The canonical form agrees with
Vāgdhenu on 154 of 172 comparable corpus lines, and every difference is a
documented decision rather than a defect.

**Gate 2 — token compatibility.** Passes, with the five approximations and one
unsupported letter above. All 33 consonants and 10 of 14 vowels are faithful.

**Gate 3 — acoustic quality.** **Open.** It is settled by listening to
`Artifacts/sanskrit/*.wav`, not by argument.

### If Gate 3 fails

The rule, and the most important sentence in this document:

> A linguistically correct sequence may sound wrong because the model was never
> trained on that phoneme combination. **Do not misspell Sanskrit to trick the
> voice.**

The current voice packs are English and Hindi. None has heard Sanskrit. If
correct phonemes render badly, the finding is:

```
PHONEMIZER VALID — ACOUSTIC MODEL / VOICE TRAINING REQUIRED
```

Bending the phonemizer would poison exactly the labels a future fine-tune
depends on, and would trade a fixable model problem for a permanent
linguistic one. `HindiTrainingLabels` exists precisely because labelling
training data with this repository's phonemizer — rather than eSpeak — is what
makes a fine-tune learn what inference will actually send it. The same will be
true for Sanskrit.

There is external evidence for this ordering. EdgeSanskrit-TTS v1 pointed a
Sanskrit phonemizer at stock Kokoro-82M; v2 moved to IndicF5 with Vāgdhenu's
front end. Vāgdhenu reached ~4.6 MOS only after fine-tuning on five hours of
chanted Sanskrit. Nobody has got excellent Sanskrit out of an untrained voice.

## Future work

1. **Listen to the three verses** and decide about Gate 3.
2. **Settle the open questions** in `SANSKRIT_G2P_RESEARCH.md` §8 — the visarga
   echo, anusvāra before sibilants, vocalic ṛ, the palatal series, ऐ/औ, and
   whether an entirely unstressed line is acceptable.
3. **Sanskrit voice fine-tuning**, if Gate 3 requires it. A
   `SanskritTrainingLabels` alongside `HindiTrainingLabels` would be the entry
   point, and the same vocabulary check applies: never train on a phoneme with
   no token.
4. **Metre.** The akṣara structure already carries what a guru/laghu
   classifier needs — vowel length, and whether a coda cluster follows. Vāgdhenu
   found chandas-aware prosody worth real effort.
5. **Forced alignment** for word highlighting, using the preserved source
   offsets.
6. **Vedic accent**, as a separate scope.
