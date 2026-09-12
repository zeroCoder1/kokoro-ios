# Sanskrit sources and license audit

Every project consulted while building the Sanskrit front end, what was taken
from it, and whether taking it was legally compatible with this repository.

**This repository is MIT** (`LICENSE`, Copyright (c) 2025 Lassi Maksimainen).
MIT is inbound-compatible with MIT and with Apache-2.0, so nothing below was
blocked on licensing. The reason no third-party source was copied is
engineering, not law: every reference is Python targeting a different acoustic
model, and this package is Swift targeting Kokoro's IPA vocabulary.

## Summary

| Project | License | Compatible with MIT inbound? | Code copied | Attribution owed |
|---|---|---|---|---|
| [Vāgdhenu](https://github.com/prathoshap/vagdhenu) | Apache-2.0 | Yes | None | None (no code used) |
| [EdgeSanskrit-TTS](https://github.com/Hariprajwal/EdgeSanskrit-TTS) | MIT | Yes | None | None (no code used) |
| [IndicVoice](https://github.com/Bindkushal/indic-voice) | Apache-2.0 | Yes | None | None (no code used) |
| [indic-g2p](https://github.com/Bindkushal/indic-g2p) | Apache-2.0 | Yes | None | None (no code used) |
| [eSpeak NG](https://github.com/espeak-ng/espeak-ng) | GPL-3.0 | **No** | **None — deliberately** | n/a |

**No source code from any of these projects is present in this repository.**
Not a function, not a table, not a translated line. What was reused is
*documented behaviour*: which phonological rule each project applies in which
environment, which we then decided about independently and implemented from
scratch against Sanskrit phonology and Kokoro's vocabulary.

The references are not vendored. `Tools/sanskrit-reference-compare.py` takes a
`--refs` path to local clones the developer makes themselves, so cloning is a
developer action and this repository stays free of third-party source.

## Vāgdhenu

- **Repository:** https://github.com/prathoshap/vagdhenu
- **License:** Apache License 2.0 (`LICENSE`)
- **Target model:** IndicF5 (F5-TTS DiT, ~337M params) — a **script-input**
  model, not a phoneme-input one.

**Files inspected**

| File | What it does |
|---|---|
| `src/tts_normalize.py` | Devanagari→Devanagari normalization: anusvāra, visarga, ॐ, editorial stripping |
| `src/tts_g2p.py` | Normalized Devanagari → SLP1, via the `indic_transliteration` library |
| `src/prep_text.py` | Production front end: script detection, visarga sandhi, Kannada routing |
| `src/tts_syllabify.py` | SLP1 syllable segmentation, maximise-onset |
| `docs/TECH_REPORT.md` | Experiment log E0–E80, ~54 KB — the rationale for every choice |

**Concepts reused (behaviour, not code)**

1. **The layering itself.** Normalize in Devanagari → convert to a canonical
   phonemic representation → only then adapt to the acoustic model. This is
   the architecture `docs/SANSKRIT.md` describes, and it is the single most
   valuable thing taken from this project.
2. **SLP1 as the canonical representation.** `prep_text.py` states it
   directly: *"SLP1 is phonemic: 1 char = 1 phone"*. Independently adopted.
3. **Anusvāra by following place**, with the continuant environments
   (`र ल व श ष स ह`) left as a nasal *continuant* rather than forced to `m`,
   and word-final anusvāra realised as `म्`.
4. **Visarga echo vowel at pause only** (`visarga_echo_final`): `रामः`→
   *rāmaha*, `गुरुः`→*guruhu*, `हरिः`→*harihi*. Adopted, including the
   restriction to the final visarga — see the research doc for why the
   unrestricted form is metrically wrong.
5. **ॐ → ओम्** expansion before parsing.
6. **Daṇḍa/double-daṇḍa as distinct pause tokens** rather than punctuation.

**Concepts deliberately NOT reused**

- **Kannada script routing.** `TECH_REPORT.md` line 21 gives the reason:
  *"Routes Sanskrit through Kannada script (IndicF5 was trained on Indic
  scripts; Devanagari triggers Hindi schwa-deletion)"*, and line 205:
  *"routing through Kannada (not raw Devanagari) prevents Hindi-style schwa
  deletion"*. This is a workaround for a **script-input** model whose
  Devanagari embeddings carry Hindi reading habits. Kokoro takes IPA phonemes
  that we compute ourselves, so there is no script embedding to fight and
  nothing to route around. See `docs/SANSKRIT_G2P_RESEARCH.md` §5.
- **Their SLP1-vs-Kannada ablation result** (E30, *"Kannada wins (rich
  pretrained embeddings)"*) is an argument about which **embeddings** IndicF5
  had pretrained, not about which representation is linguistically better. It
  does not transfer to a model whose embeddings are IPA.
- **`F` → `"rU"`** for long vocalic ṝ — explicitly a workaround for IndicF5
  mispronouncing the Kannada glyph ೄ.
- **Word-boundary visarga sandhi** (`visarga_sandhi`: utva/rutva/lopa). This
  rewrites the text into a different surface form. The Gita text we are given
  already carries its written sandhi, and §20 of the brief forbids
  transforming the source. Not implemented.

## EdgeSanskrit-TTS

- **Repository:** https://github.com/Hariprajwal/EdgeSanskrit-TTS
- **License:** MIT (Copyright (c) 2026 K R HARI PRAJWAL)

**Files inspected**

| File | What it does |
|---|---|
| `sanskrit_phonemizer.py` | Devanagari → IPA in one pass, ~200 lines |
| `generate_sanskrit.py` | **v1: `hexgrad/Kokoro-82M` + that phonemizer** |
| `generate_sanskrit_v2.py` | v2: IndicF5, and it `import prep_text as PT` — Vāgdhenu's front end |
| `test_run.py`, `test_run_v2.py` | Bhagavad Gita 1.1 examples |

**Why this project matters most to us:** `generate_sanskrit.py` is a direct
precedent for exactly what we are doing — Devanagari → IPA → **base
Kokoro-82M**, no retraining. It is the only reference that has actually
pointed Sanskrit at a stock Kokoro model.

**Why it also matters that v2 exists:** the author moved off that path onto
IndicF5 with Vāgdhenu's front end. That is evidence about Gate 3 (acoustic
quality) before we run a single sample of our own.

**Concepts reused**

1. **No schwa deletion, ever** — the inherent `a` is always emitted. Correct
   for Sanskrit, and the point on which Sanskrit and Hindi part company.
2. **Homorganic nasal for anusvāra** before the five vargas.
3. **Visarga echo vowel** keyed to the preceding vowel (`ha/hi/hu/he/ho`).
4. **Daṇḍa → sentence-final punctuation** for pausing.
5. **Compositional conjunct parsing** — क्ष is `k`+`ʂ` and ज्ञ is `ɟ`+`ɲ`,
   not the Hindi `kʃ`/`gj`. Correct for Sanskrit.

**Defects found and deliberately not reproduced** (each verified by running it)

| Input | EdgeSanskrit output | Problem |
|---|---|---|
| `एव` | `eva` | ए is **always long** in Sanskrit. Should be `eːʋa`. Loses a guru/laghu distinction that metre depends on. |
| `दुःख` | `duhukʰa` | Echo vowel applied **word-internally**, inserting a whole extra syllable. दुःख is 2 syllables; this makes it 3. Metrically wrong. |
| `निःशेष` | `nihiʃeʂa` | Same defect. |
| `संस्कृत` | `samskɾɪta` | Anusvāra before a sibilant forced to `m`. Classically it is a nasalised continuant. |
| `संयोग` | `samjoɡa` | Same, before a semivowel. |
| `हुँ` | `hu` | **Chandrabindu silently dropped** — it is in no table. |
| `ॐ` | *(empty)* | **No ॐ mapping at all**; the ligature produces nothing. |
| `सोऽहम्` | `soːham` | Avagraha mapped to the length mark `ː`. It is a silent elision marker, not length. |

## IndicVoice / indic-g2p

- **Repositories:** https://github.com/Bindkushal/indic-voice,
  https://github.com/Bindkushal/indic-g2p
- **License:** Apache-2.0 (Copyright (c) 2025 Kushal Kant Bind)
- **Relevance:** it is built on the **Kokoro-82M architecture** with a native
  Indic G2P front end — the closest architectural analogue to this package.

**The finding that matters.** IndicVoice **extended the token vocabulary**.
Measured directly against ours:

```
IndicVoice vocab: 151 entries   (n_token 178)
kokoro-ios vocab: 114 entries   (n_token 178)
kokoro-ios ⊂ IndicVoice:  yes — every one of our 114 is present
IndicVoice adds 37:
  aː eː iː oː uː ɔː ɛː ɪː ʊː        long vowels as SINGLE tokens
  kʰ gʰ cʰ ɟʰ tʰ dʰ ʈʰ ɖʰ pʰ bʰ    aspirates as SINGLE tokens
  ã ẽ ĩ õ ũ ə̃                       nasal vowels as SINGLE tokens
  ɭ ɦ ɫ ɱ ʐ b̪ p̪ ɽ͡r
  t͡ɕ d͡ʑ ʈ͡ʂ ɖ͡ʐ                        affricates
```

Those 37 rows sit in embedding slots the **base Kokoro weights never
trained**. IndicVoice can use them because it trained the model; we cannot.

**Therefore, for us, every Sanskrit sound must be spelled as a sequence of the
114 base tokens** — `aː` as `a`+`ː`, `kʰ` as `k`+`ʰ`, `ã` as `a`+`◌̃`. This is
already what `HindiPhonemizer` does, and `Tokenizer.tokenize` iterates Unicode
*scalars* precisely so those sequences survive. Confirmation, not a change.

`indic-g2p` itself has **no Sanskrit support** (`INDIC_PHONES.md` covers Hindi,
partially Punjabi; Bengali and Tamil are "coming soon"), so nothing linguistic
was taken from it.

## eSpeak NG

- **Repository:** https://github.com/espeak-ng/espeak-ng
- **License:** **GPL-3.0**
- **Version checked:** 1.52.0 (Homebrew, local development machine)

**Finding: eSpeak NG has no Sanskrit voice.** This contradicts the assumption
in the brief and is worth stating plainly.

```
$ espeak-ng -v sa -q --ipa "धर्म"
Error: The specified espeak-ng voice does not exist.

$ ls .../espeak-ng-data/lang/inc/
as  bn  bpy  gu  hi  kok  mr  ne  or  pa  sd  si  ur
```

There is no `sa`, and `grep -ril sanskrit` over the whole data directory
returns nothing. The Indic voices are Assamese, Bengali, Bishnupriya,
Gujarati, **Hindi**, Konkani, Marathi, Nepali, Oriya, Punjabi, Sindhi,
Sinhala, Urdu.

So the "eSpeak Sanskrit" column of the comparison matrix cannot be filled. The
closest available reference is **eSpeak Hindi, used as a proxy**, and it is a
poor one — it applies Hindi schwa deletion, which is the exact behaviour
Sanskrit must not have:

| Input | espeak `-v hi` | Correct Sanskrit |
|---|---|---|
| कर्म | `kˈʌrm` | `kaɾma` — final and internal vowels intact |
| संस्कृत | `sˈʌnskɾɪt` | `saⁿskɾɪta` |
| रामः | `ɾˈaːməh` | `ɾaːmaha` — visarga echo |

**Licensing.** eSpeak NG is GPL-3.0 and this repository is MIT. Importing its
source or data would be a licence violation. Nothing was copied. It is invoked
as an external binary by a development-only script (`Tools/sanskrit-reference-
compare.py`), which is ordinary use of an installed program and creates no
derivative work. It is not a dependency of the Swift package, and is not
present at runtime on device.

This matches the existing precedent in the repository: `HindiPhonemizer`
states it "deliberately contains no eSpeak code or data", and
`Tools/espeak-diff.py` / `Tools/hindi-inspect.sh` shell out to the binary for
development comparison only.

## Reference recordings and models evaluated

Neither of these contributes code or data to the package. Both were measured;
one is used as a listening reference and nothing else.

| Source | What it is | License | Used how |
|---|---|---|---|
| [gita_supersite_sanskrit_tts](https://huggingface.co/datasets/yashnbx/gita_supersite_sanskrit_tts) | 701 clips, one reciter, the complete Gītā | **None stated** | Measurement reference only. Not redistributed, not trained on. |
| [R910/Sanskrit_TTS_v2](https://huggingface.co/R910/Sanskrit_TTS_v2) | LoRA over Orpheus-3B, Sanskrit fine-tune | Tagged Apache-2.0 | Evaluated and rejected. Nothing used. |

### The reciter recordings

The prosody calibration in `SanskritDelivery.traditional` comes from this
corpus. What it is, measured rather than taken from the card:

- 701 clips covering all eighteen chapters, and the per-chapter counts match
  the Gītā exactly (1:47, 2:72 … 18:78)
- one voice throughout — median F0 182.8 Hz, sd 5.9 Hz across 24 verses from
  different chapters, which is chant on a fixed reciting tone, not read prose
- 585 verses are anuṣṭubh with no speaker tag, and those are what the pace
  figures are computed over
- the text is canonical Devanagari and matches this repository's validation
  verses character for character, though it carries speaker tags (`उवाच`,
  33 verses) and embedded verse numbers that would need stripping

**It cannot be training data.** The audio is 16 kHz at 16 kbps mono MP3, and
the encoder brick-walled it: the spectrum is flat to about 4.4 kHz and holds
**0.00% of its energy above 5 kHz**, against 11.3 kHz for this repository's own
output. Fricative and sibilant energy lives at 4–10 kHz, so the visarga, the
ś/ṣ/s contrast and stop-burst detail are physically absent from the recording —
precisely the sounds `SANSKRIT_FINE_TUNING_REQUIREMENTS.md` needs covered.

Timing survives lowpassing intact, which is why it is a sound reference for
pace and a useless one for segments.

**License is unresolved.** No license is stated on the dataset card, and no
terms-of-use statement was found at the source (Gītā Supersite, IIT Kanpur).
Measuring a downloaded copy locally is not redistribution; training on it or
shipping it would be, and neither is done here.

### The Orpheus fine-tune

Evaluated because it is the only other Sanskrit TTS model with a Gītā-shaped
purpose. Rejected on architecture, before pronunciation enters into it:

- the repository holds a **389 MB LoRA adapter only**; it needs
  `unsloth/orpheus-3b-0.1-ft`, which is **6.63 GB**
- merged, that is 3.3B parameters — about 2 GB even at 4-bit, against Kokoro's
  ~330 MB
- it is autoregressive over SNAC codec tokens at **82 tokens per second of
  audio**, so a ten-second śloka is ~820 sequential passes of a 3.3B model,
  where Kokoro is one non-autoregressive pass
- there is no MLX Swift implementation of either Orpheus or the SNAC decoder
- it takes raw Devanagari and does its own G2P inside the LLM, so this
  repository's parser, phonology, token audit and metre scan would have no
  entry point

Its four published samples were measured. They articulate cleanly — BG 2.47
reaches 16 of 16 syllable nuclei — but **none of them contains a visarga, a
vocalic ṛ or a word-final म्/न्**, so they demonstrate nothing about the three
gaps documented here.

The Apache-2.0 tag also warrants checking rather than trusting: it is a LoRA
over a Llama-3.2-3B derivative, and the Llama Community License carries naming
and attribution obligations to derivatives.

## Attribution

No file in this repository reproduces third-party code, so no copyright
notices are carried. The projects above are credited here and in
`docs/SANSKRIT_G2P_RESEARCH.md` as the references whose documented behaviour
informed our decisions — which is what they are.
