# Can Kokoro express Sanskrit? — token audit

Gate 2 of the three-gate model. Gate 1 asks whether the front end produces a
defensible Sanskrit representation; **this document asks whether the model can
say it**, and answers per sound.

Audited against `Resources/config.json` in this repository: **114 vocabulary
entries**, `n_token` 178. Every "available" claim below was checked
programmatically against that file, not from memory.

## How Kokoro's vocabulary works, and why it constrains us

`Tokenizer.tokenize` maps **one Unicode scalar to one token**. There is no
multi-character token. So a sound like `kʰ` is not one token — it is `k`
(53) followed by `ʰ` (162), and `aː` is `a` (43) + `ː` (158).

An unknown scalar is **dropped silently** in release builds. A phoneme we
cannot spell does not degrade; it *vanishes*, taking its syllable with it. That
is why this audit exists and why `SanskritKokoroMapper` warns rather than
substituting.

**IndicVoice sets the contrast.** It is Kokoro-82M with an Indic front end, and
it extended the vocabulary from 114 to 151 entries to add exactly what Indic
needs as single tokens — `aː eː iː oː uː`, `kʰ gʰ ʈʰ ɖʰ …`, `ã ẽ ĩ õ ũ`, `ɭ`,
`ɦ`. Those rows sit in embedding slots the **base Kokoro weights never
trained**. IndicVoice can use them because it trained the model. We are on
stock weights (§34: no training in this phase), so **we must spell every
Sanskrit sound as a sequence of the 114 base tokens.**

## 1. Vowels

| Sanskrit | SLP1 | Desired IPA | Kokoro spelling | Tokens | Available | Risk |
|---|---|---|---|---|---|---|
| अ | `a` | `ɐ` ~ `ə` | `a` | 43 | ✅ | **none** |
| आ | `A` | `aː` | `a` `ː` | 43,158 | ✅ | **none** |
| इ | `i` | `i` | `i` | 51 | ✅ | **none** |
| ई | `I` | `iː` | `i` `ː` | 51,158 | ✅ | **none** |
| उ | `u` | `u` | `u` | 63 | ✅ | **none** |
| ऊ | `U` | `uː` | `u` `ː` | 63,158 | ✅ | **none** |
| ए | `e` | `eː` | `e` `ː` | 47,158 | ✅ | **none** |
| ऐ | `E` | `aːi̯` | `a` `ɪ` | 43,102 | ✅ | **low** — see §5.3 |
| ओ | `o` | `oː` | `o` `ː` | 57,158 | ✅ | **none** |
| औ | `O` | `aːu̯` | `a` `ʊ` | 43,135 | ✅ | **low** — see §5.3 |
| **ऋ** | `f` | **`r̩`** | `ɾ` `ɪ` | 125,102 | ⚠️ | **`APPROXIMATION_REQUIRED`** — §5.1 |
| **ॠ** | `F` | **`r̩ː`** | `ɾ` `i` `ː` | 125,51,158 | ⚠️ | **`APPROXIMATION_REQUIRED`** — §5.1 |
| **ऌ** | `x` | **`l̩`** | `l` `ɪ` | 54,102 | ⚠️ | **`APPROXIMATION_REQUIRED`** — §5.1 |
| **ॡ** | `X` | **`l̩ː`** | `l` `iː` | 54,51,158 | ⚠️ | **`APPROXIMATION_REQUIRED`** — §5.1 |

Vowel **length is fully expressible**: `ː` (U+02D0) is token 158. The five
phonemic length pairs अ/आ, इ/ई, उ/ऊ, ऋ/ॠ, ऌ/ॡ all survive. ए and ओ carry `ː`
because they are inherently long in Sanskrit.

## 2. Consonants — all 33 are expressible

Aspiration uses `ʰ` (U+02B0, token 162), which is present. `ʱ` (U+02B1, the
breathy-voiced modifier that घ झ ढ ध भ arguably want) is **absent**, so the
voiced aspirates use `ʰ` as well. That is the same compromise
`HindiPhonemizer` makes; the ten aspirated/unaspirated contrasts are all
preserved, which is what matters phonemically.

| Varga | Letters | Kokoro spelling | Available | Risk |
|---|---|---|---|---|
| कण्ठ्य (velar) | क ख ग घ ङ | `k` `kʰ` `ɡ` `ɡʰ` `ŋ` | ✅ | none |
| तालव्य (palatal) | च छ ज झ ञ | `c` `cʰ` `ɟ` `ɟʰ` `ɲ` | ✅ | **low** — §5.4 |
| मूर्धन्य (retroflex) | ट ठ ड ढ ण | `ʈ` `ʈʰ` `ɖ` `ɖʰ` `ɳ` | ✅ | none |
| दन्त्य (dental) | त थ द ध न | `t` `tʰ` `d` `dʰ` `n` | ✅ | **low** — dental vs alveolar, §5.5 |
| ओष्ठ्य (labial) | प फ ब भ म | `p` `pʰ` `b` `bʰ` `m` | ✅ | none |
| अन्तःस्थ | य र ल व | `j` `ɾ` `l` `ʋ` | ✅ | none |
| ऊष्मन् | श ष स ह | `ʃ` `ʂ` `s` `h` | ✅ | **low** — §5.2, §5.6 |

All five nasals are distinct tokens: `ŋ`(112) `ɲ`(114) `ɳ`(113) `n`(56)
`m`(55). All three sibilants are distinct: `ʃ`(131) `ʂ`(130) `s`(61). The
retroflex/dental contrast `ʈ`/`t` and `ɖ`/`d` is intact.

### Consonants outside the Classical 33

| Letter | Desired IPA | Status |
|---|---|---|
| **ळ** (Vedic/Marathi retroflex lateral) | **`ɭ`** | **`KOKORO_UNSUPPORTED`.** U+026D is not in the vocabulary. Falls back to `l`, with a warning. Present in IndicVoice's extended vocabulary but not in base Kokoro. Does not occur in the Classical Gita text. |
| ऩ ऱ ऴ, nukta forms क़ ख़ ग़ ज़ ड़ ढ़ फ़ | — | Not Classical Sanskrit. Parsed without crashing, mapped to their base letter, warning emitted. |

## 3. Marks

| Mark | Desired | Kokoro spelling | Available | Risk |
|---|---|---|---|---|
| **anusvāra ं** before a varga | homorganic nasal | `ŋ ɲ ɳ n m` | ✅ | none |
| **anusvāra ं** before य र ल व श ष स ह | nasalised continuant | nasalise the vowel: `◌̃` (17) | ⚠️ | **`APPROXIMATION_REQUIRED`** — §5.7 |
| **anusvāra ं** word-final | `m` | `m` | ✅ | none |
| **chandrabindu ँ** | nasalised vowel | vowel + `◌̃` | ✅ | none |
| **visarga ः** at pause | `h` + echo vowel | `h` + vowel | ✅ | none |
| **visarga ः** word-internal | `h` | `h` | ✅ | **low** — §5.6 |
| jihvāmūlīya (option) | `x` | `x` (66) | ✅ | available, off by default |
| upadhmānīya (option) | `ɸ` | `ɸ` (118) | ✅ | available, off by default |
| **avagraha ऽ** | silent | *(nothing emitted)* | ✅ | none |
| **virāma ्** | no vowel | *(nothing emitted)* | ✅ | none |
| **daṇḍa ।** | moderate pause | `,` (3) | ✅ | **low** — §5.8 |
| **double daṇḍa ॥** | strong pause | `.` (4) | ✅ | **low** — §5.8 |
| Vedic accents U+0951/0952 | — | dropped | n/a | `VEDIC_ACCENT_IGNORED`, out of scope per §9 |

**Nasalised vowels are expressible.** U+0303 is token 17, and
`Tokenizer.tokenize` iterates Unicode *scalars* specifically so that `a`+`◌̃`
survives as two tokens rather than being combined into one unmappable grapheme
— a bug already found and fixed for Hindi.

## 4. Verdict

**Gate 2 passes, with four documented approximations and one unsupported
letter.**

| | Count | Which |
|---|---|---|
| ✅ Faithful | 44 | all 33 Classical consonants, 10 of 14 vowels, virāma, avagraha, chandrabindu, visarga-at-pause, anusvāra before all five vargas |
| ⚠️ Approximation | 5 | ऋ ॠ ऌ ॡ, anusvāra before continuants |
| ❌ Unsupported | 1 | ळ → `l` |

The four vocalic-liquid approximations all have the **same single cause**:
Kokoro has no syllabic diacritic (U+0329 / U+0325 are both absent), so `r̩` and
`l̩` cannot be written. One missing token, four affected sounds.

**Nothing is silently approximated.** `SanskritPhonemizer.inspect(text:)` and
the `warnings` array report every one:

```
KOKORO_APPROXIMATION: vocalic ṛ → ɾɪ (no syllabic diacritic in Kokoro vocabulary)
KOKORO_APPROXIMATION: anusvāra before a continuant → vowel nasalisation
KOKORO_UNSUPPORTED:   ḷa (ळ) → l (ɭ, U+026D, is not in the Kokoro vocabulary)
```

## 5. Risk notes

**5.1 Vocalic liquids.** The one genuine gap. `ɾɪ` is one light syllable, so
metre is preserved, and it is what EdgeSanskrit, eSpeak Hindi and this
repository's Hindi front end all use — the best-conditioned option available.
`ɾu` (South Indian) is offered as an option. A model that ever gains a
syllabic diacritic would let this be exact.

**5.2 श as `ʃ`.** `ɕ` is more accurate and *is* available (token 77), but
reaches Kokoro only through Japanese and Chinese. `ʃ` is heavily trained and
preserves श≠ष≠स, which is the contrast that matters. Configurable.

**5.3 ऐ/औ.** Written `aɪ`/`aʊ`, the best-trained diphthong sequences in the
model (English *price*, *mouth*). Classically these are long (guru). The
diphthong carries that implicitly rather than by an explicit `ː`. Worth a
listen.

**5.4 च-varga as `c`/`ɟ`.** Palatal stops rather than affricates. Trained via
Kokoro's Hindi. See `docs/SANSKRIT_G2P_RESEARCH.md` §2.4.

**5.5 Dentals.** Sanskrit त द न are true dentals; Kokoro's `t d n` are
English alveolars. The *contrast* with the retroflex series survives, which is
the phonemic requirement, but a fastidious ear will hear alveolars. This is a
voice-training matter, not a phonemizer one — do not "fix" it by moving the
dentals somewhere else in the vocabulary.

**5.6 Visarga.** `h` is well trained. What the current voices will not give is
the *voicelessness* and the characteristic echo timbre of a real visarga; the
echo vowel approximates it. If it sounds weak, that is Gate 3.

**5.7 Anusvāra before continuants.** Vowel nasalisation is the closest thing
Kokoro can spell to a nasalised approximant. Well trained via Hindi and French.

**5.8 Daṇḍas.** Kokoro's punctuation tokens are the only pause control
available, and there are two useful strengths: `,` and `.`. That is exactly
enough for pāda vs verse. The **structural** information is richer than the
token stream can carry, so it is retained internally on
`SanskritPhonemizer.Result` (`boundaries`) for a future prosody-aware path,
rather than being thrown away at the punctuation mark. This is the "document
the limitation and retain structured boundary information" case of §19.

## 6. What this does not tell us

This document is Gate 2 only: *can the tokens be written*. It says nothing
about whether the current English and Hindi voice packs, which never heard
Sanskrit, will **render** them acceptably. That is Gate 3, and it is settled by
listening to `Artifacts/sanskrit/*.wav`.

If Gate 3 fails while Gates 1 and 2 pass, §37 governs: the phonemizer is
correct and the acoustic model needs Sanskrit training. Do not misspell
Sanskrit to flatter an untrained voice — it would poison exactly the labels a
future fine-tune depends on.
