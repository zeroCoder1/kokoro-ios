# Validation v2 — before and after

Second-pass renders after the confirmed frontend corrections. The first-pass
files are preserved in `Artifacts/sanskrit/` and nothing here overwrote them.

| | v1 | v2 |
|---|---|---|
| commit | `bcb3a30` | `20cadb6` + prosody defaults |
| path | `Artifacts/sanskrit/bg_*.wav` | `Artifacts/sanskrit/validation-v2/bg_*.wav` |
| visarga | `h` + echo vowel | `h` |
| pāda / verse pause | model's own, undifferentiated | 500 ms / 1000 ms |
| synthesis | one call per verse | one call per pāda, joined with silence |
| voice / model | `hf_alpha`, kokoro-v1_0 | unchanged |

Evidence for every change: `../diagnostics/audio-failure-analysis.md`.
Machine-readable per-file record: `manifest.json`.

## What changed, and why

### 1. Visarga no longer gains a syllable

**Reason.** Measured, holding everything else identical:

| phonemes | span | energy nuclei |
|---|---|---|
| `ɾaːma` | 585 ms | 3 |
| `ɾaːmah` | 565 ms | **3** |
| `ɾaːmaha` (v1) | 735 ms | **6** |

The echo vowel was a whole extra syllable. रामः was being said *rā-ma-ha* —
three syllables where Sanskrit has two and a light aspiration. The traditional
echo is brief and voiceless; Kokoro can only spell a full voiced vowel.

**Not** a case of the correct phoneme sounding bad. The v1 output was
phonologically over-specified relative to what the target can express, and
`KOKORO_APPROXIMATED_VISARGA` now says so on every occurrence. The echo
remains available via `SanskritOptions.visargaEchoAtPause`.

### 2. Pāda and verse breaks are now differentiated

**Reason.** Kokoro's punctuation was measured at verse length before any
silence was inserted:

| separator | longest internal silence |
|---|---|
| none | 350 ms |
| `,` | 385 ms |
| `.` | 355 ms |

The model gives a substantial gap on its own but does not distinguish `।` from
`॥`, or either from a plain space. `SanskritProsody` synthesizes each pāda
separately and rejoins with configured silence — the mechanism
`generateContinuousAudio` already uses. No phoneme changes.

**Measured result:**

| file | longest internal silence | next longest (word gaps) |
|---|---|---|
| v1 bg_01_01 | 365 ms | 220 ms |
| **v2 bg_01_01** | **585 ms** | 240 ms |
| v1 bg_02_47 | 320 ms | 295 ms |
| **v2 bg_02_47** | **555 ms** | 235 ms |
| v1 bg_04_07 | 380 ms | 255 ms |
| **v2 bg_04_07** | **570 ms** | 255 ms |

The pāda break is 2.4× a word gap where it used to be level with one. A first
attempt at 320 ms measured *no better than v1* — each stretch is trimmed of the
decoder's own edge silence, so the configured value is the whole gap and has to
exceed the model's natural 350 ms.

## Per-verse phoneme changes

Only the visarga differs. Everything else is byte-identical.

### BG 1.1

```
v1  dʰaɾmakʂeːtɾeː kuɾukʂeːtɾeː samaʋeːtaː jujutsaʋaha, maːmakaːh …
v2  dʰaɾmakʂeːtɾeː kuɾukʂeːtɾeː samaʋeːtaː jujutsaʋah,  maːmakaːh …
                                                   ^^ echo vowel removed
```

`युयुत्सवः` loses the spurious final syllable. Token count 98 → 97.
Segmented as two pādas: pause 0.5 s after `।`, 1.0 s after `॥`.

### BG 2.47

```
v1  kaɾmaɳjeːʋaːdʰikaːɾasteː maː pʰaleːʂu kadaːcana, maː kaɾmapʰalaheːtuɾbʰuːɾmaː teː saŋɡoːstʋakaɾmaɳi.
v2  identical — this verse has no visarga
```

Changed only by the pause layer. It remains the hardest verse: 
`कर्मण्येवाधिकारस्ते` is 24 phonemes in one orthographic word, and splitting it
into prosodic words recovers six syllable nuclei and 16% more time per phoneme.
That needs a sandhi-splitting lexicon and is **not** fixed here.

### BG 4.7

```
v1  jadaː jadaː hi dʰaɾmasja ɡlaːniɾbʰaʋati bʰaːɾata, abʰjuttʰaːnamadʰaɾmasja tadaːtmaːnã sɾɪɟaːmjaham.
v2  identical — no visarga
```

Changed only by the pause layer. `तदात्मानं` keeps its nasalised vowel before
the following sibilant, and `सृजाम्यहम्` keeps `sɾɪ` with its
`KOKORO_APPROXIMATION` for vocalic ṛ.

## Unresolved — model limitations, not frontend faults

These are unchanged on purpose. Changing them would mean misspelling Sanskrit
to flatter a voice that has never heard it.

| | status | why |
|---|---|---|
| **ए centralized** | `ACOUSTIC_MODEL_LIMITATION` | `eː` and `iː` are 7.3 dB apart — more than `oː`/`uː` — so not collapsed, but `eː` sits nearest `ɛ`/`ə` rather than being tense. Frontend and tokenization both verified correct. |
| **ए short in context** | same | final ए is 114 ms in `kʂeːtɾeː` against 156 ms in isolation |
| **retroflexes thin** | same | `ʂ` appears 4 times, `ɳ` 9, `ʈ` 13, `ɖ` 1 across Kokoro's training languages, against `s` 4336 and `t` 4129 |
| **vocalic ṛ** | `KOKORO_APPROXIMATION` | no syllabic diacritic exists in the vocabulary, so `r̩` is unspellable |
| **visarga** | `KOKORO_APPROXIMATED_VISARGA` | real visarga is voiceless; ह is breathy `ɦ`, absent from base Kokoro. `ः` and `ह्` collapse in IPA and stay distinct only in the canonical form |
| **long compounds** | `ACOUSTIC_MODEL_LIMITATION` | 24-phoneme words are outside anything Kokoro trained on; needs a sandhi splitter |

## How to judge these files

Compare v1 and v2 **on the two things that changed**: whether `युयुत्सवः` and
`मामकाः` still end in an audible "-ha" syllable, and whether the half-verse
break is now clearly longer than the gaps between words.

Everything else is the same phoneme stream. If ए still sounds wrong in v2, that
confirms the acoustic finding rather than contradicting it — and the answer is
a Sanskrit-trained voice, not a different vowel symbol.
