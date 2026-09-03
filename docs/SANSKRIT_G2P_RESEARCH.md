# Sanskrit G2P — reference comparison and decisions

Written **before** any Sanskrit code, as §4 of the brief requires. Every
reference cell below was produced by running the reference, not by reading it:

```bash
Tools/sanskrit-reference-compare.py --refs <clones> --corpus Tools/sanskrit-listening-corpus.txt --tsv
```

Licensing and what was reused: `docs/SANSKRIT_SOURCES.md`.
Token-level feasibility: `docs/SANSKRIT_KOKORO_COMPATIBILITY.md`.

## The eSpeak column is empty, and that is a finding

**eSpeak NG 1.52 has no Sanskrit voice.** `-v sa` errors; `lang/inc/` holds
`as bn bpy gu hi kok mr ne or pa sd si ur` and no `sa`. The brief assumed one
existed. It does not.

Where a comparison is still useful the column shows **eSpeak Hindi as a proxy**,
marked *(hi)*. It is a coverage check only. Hindi schwa deletion makes it wrong
for Sanskrit on most words by construction — `कर्म` → `kˈʌrm`, where Sanskrit
needs `kaɾma`. **Agreement with this column is not a goal, and disagreement is
usually evidence we are right.**

## 1. The comparison matrix

`REVIEW_REQUIRED` marks a row where the references genuinely disagree and our
choice should be checked by ear before it is trusted.

| Feature | Vāgdhenu | EdgeSanskrit | eSpeak *(hi proxy)* | **Our decision** | Status |
|---|---|---|---|---|---|
| **अ inherent vowel** | Always kept (`karma`) | Always kept (`kaɾma`) | Deleted | **Always kept.** Emit `a` after every consonant with no vowel sign and no virāma | CONFIRMED |
| **final inherent vowel** | Kept (`Darma`) | Kept (`dʰaɾma`) | Deleted (`dʰˈərm`) | **Kept.** No word-final deletion | CONFIRMED |
| **Hindi-style schwa deletion** | Never | Never | Always | **Never applied anywhere.** No `HindiPhonemizer` code path is reachable from Sanskrit | CONFIRMED |
| **ऋ** | SLP1 `f` (unresolved) | `ɾɪ` | `ɾɪ` | **`ɾɪ`.** True value is syllabic `r̩`; Kokoro has no syllabic diacritic | APPROXIMATION |
| **ॠ** | SLP1 `F`; → `rU` for their model | `ɾiː` | — | **`ɾiː`.** Length preserved against ऋ | APPROXIMATION |
| **ऌ** | SLP1 `x` | `lɪ` | — | **`lɪ`.** True value `l̩` | APPROXIMATION |
| **ॡ** | SLP1 `X` | **dropped silently** | — | **`liː`.** Never dropped | APPROXIMATION |
| **ए / ओ** | SLP1 `e`/`o` — long by definition | **`e` / `o` — short** | `eː`/`oː` | **`eː` / `oː`.** Always long in Sanskrit; metre depends on it | CONFIRMED |
| **ऐ / औ** | SLP1 `E`/`O` | `aɪ` / `aʊ` | `ɛː`/`ɔː` | **`aɪ` / `aʊ`.** Inherently guru | REVIEW_REQUIRED |
| **anusvāra + velar** | `ङ्` → `N` | `ŋ` | `ŋ` | **`ŋ`** | ALL_AGREE |
| **anusvāra + palatal** | `ञ्` → `Y` | `ɲ` | `ɲ` | **`ɲ`** | ALL_AGREE |
| **anusvāra + retroflex** | `ण्` → `R` | `ɳ` | `ɳ` | **`ɳ`** | ALL_AGREE |
| **anusvāra + dental** | `न्` → `n` | `n` | `n` | **`n`** | ALL_AGREE |
| **anusvāra + labial** | `म्` → `m` | `m` | `m` | **`m`** | ALL_AGREE |
| **anusvāra + semivowel** `य र ल व` | **kept as nasal continuant** (`saMrakza`); ं+य → `y~` | **`m`** (`samjoɡa`) | `n`/`m` | **Nasalise the preceding vowel** (`◌̃`) | REVIEW_REQUIRED |
| **anusvāra + sibilant / ह** | **kept** (`saMskfta`) | **`m`** (`samskɾɪta`) | `n` | **Nasalise the preceding vowel** | REVIEW_REQUIRED |
| **anusvāra word-final** | → `म्` (`aham`) | `m` | `m`/`ŋ` | **`m`** | ALL_AGREE |
| **visarga, at pause** | echo vowel, final only: `rAmaH`→*rāmaha* | echo vowel: `ɾaːmaha` | `ɾˈaːməh` | **Echo vowel: `h` + copy of preceding vowel** | VAGDHENU_EDGE_AGREE |
| **visarga, word-internal** | jihvāmūlīya/upadhmānīya or sibilant | **echo vowel** (`duhukʰa`) | `h` | **Plain `h`** (`duhkʰa`). Echo here adds a syllable and breaks metre | REVIEW_REQUIRED |
| **visarga, never** | — | — | — | **Never dropped, never turned into ह** | CONFIRMED |
| **chandrabindu ँ** | `~` (nasalisation) | **dropped silently** | nasalisation | **Nasalise the vowel** (`◌̃`) | CONFIRMED |
| **avagraha ऽ** | dropped, "not a phone" | **→ `ː` length mark** | — | **Silent.** Kept as a boundary marker internally | CONFIRMED |
| **क्ष** | `kza` = k+ṣ | `kʂa` = k+ṣ | `kʃ` (Hindi) | **`kʂ`, compositional.** Not the Hindi `kʃ` | ALL_AGREE *(vs Hindi)* |
| **ज्ञ** | `jYa` = j+ñ | `dʒɲa` = j+ñ | `ɡj` (Hindi) | **`ɟɲ`, compositional.** Not the Hindi `ɡj` | ALL_AGREE *(vs Hindi)* |
| **श्र** | `Sra` | `ʃɾa` | `ʃɾ` | **`ʃɾ`, compositional** | ALL_AGREE |
| **retroflex** ट ठ ड ढ ण | `w W q Q R` | `ʈ ʈʰ ɖ ɖʰ ɳ` | same | **`ʈ ʈʰ ɖ ɖʰ ɳ`** | ALL_AGREE |
| **aspiration** | separate SLP1 letters | `ʰ` modifier | `ʰ` modifier | **`ʰ` after the stop.** All ten pairs contrast | ALL_AGREE |
| **श / ष / स** | `S / z / s` | `ʃ / ʂ / s` | `ʃ / ʂ / s` | **`ʃ / ʂ / s`.** Three-way contrast preserved | ALL_AGREE |
| **च / छ / ज / झ** | `c C j J` (palatal) | `tʃ tʃʰ dʒ dʒʰ` (affricate) | `c cʰ ɟ ɟʰ` | **`c cʰ ɟ ɟʰ`** — palatal stops, as तालव्य and as this repo's Hindi | REVIEW_REQUIRED |
| **व** | `v` | `v` | `ʋ` | **`ʋ`.** दन्त्योष्ठ्य approximant | CONFIRMED |
| **virāma ्** | consonant only | consonant only | consonant only | **Consonant only, no vowel** | ALL_AGREE |
| **conjuncts** | compositional | compositional | compositional | **Compositional, arbitrary depth.** No glyph table | ALL_AGREE |
| **daṇḍa ।** | pause token `\|` | `.` | `.` | **Moderate pause → `,`** | CONFIRMED |
| **double daṇḍa ॥** | pause token `\|\|` | `.` | `.` | **Strong pause → `.`** | CONFIRMED |
| **word boundaries** | space preserved | space preserved | space preserved | **Preserved**; drive the visarga-at-pause rule | CONFIRMED |
| **sandhi** | utva/rutva/lopa rewriting available | none | none | **None.** The Gita text already carries its written sandhi | CONFIRMED |
| **ॐ** | → `ओम्` then parsed | **produces nothing** | — | **Expand to ओम्** before parsing | CONFIRMED |

## 2. Rows that need a longer answer

### 2.1 Vocalic ṛ — `APPROXIMATION`

The Classical value is a syllabic retroflex approximant, IPA `r̩` (or `ɻ̍`).
Kokoro's vocabulary contains **no syllabic diacritic** — U+0329 and U+0325 are
both absent — so `r̩` cannot be spelled at all. That is a hard token limit, not
a choice.

Of the realisations that *can* be spelled:

- **`ɾɪ`** — North Indian recitation (*kṛṣṇa* → "krishna"). Chosen by
  EdgeSanskrit, by eSpeak Hindi, and by this repository's `HindiPhonemizer`,
  so it is the best-trained sequence available in the model.
- **`ɾu`** — South Indian recitation ("krushna"). Equally traditional.

Both are one light syllable, so **both are metrically correct** (ऋ is laghu).
We default to `ɾɪ` and expose `ɾu` through `SanskritPhonology.Options`, because
the choice is regional rather than right-or-wrong. A `KOKORO_APPROXIMATION`
warning is emitted either way — the limitation belongs to the model and is not
hidden.

### 2.2 Anusvāra before semivowels and sibilants — `REVIEW_REQUIRED`

The five varga environments are settled and all three references agree. These
two are not.

Pāṇini's anusvāra before `य र ल व श ष स ह` is a **nasal continuant**, not a
labial stop. Vāgdhenu preserves that; EdgeSanskrit forces `m` and so says
*samskṛta* for संस्कृत and *samyoga* for संयोग, which no reciter does.

We follow Vāgdhenu's analysis, realised as **nasalisation of the preceding
vowel** (`a`+`◌̃`), which is what Kokoro can actually express — it has the
combining tilde and `HindiPhonemizer` already uses it. Strictly, before य ल व
the segment is a *nasalised semivowel* (Vāgdhenu's `y~`); Kokoro has no way to
spell a nasalised approximant, so nasalising the vowel is the nearest faithful
form. Marked `REVIEW_REQUIRED` and configurable.

### 2.3 Visarga — split by position, which neither reference does cleanly

Visarga is one symbol doing two jobs, and conflating them is where
EdgeSanskrit goes wrong.

**At pause** (utterance-final, before a daṇḍa, or before a word boundary at
the end of a phrase) the traditional recitation has a **voiceless echo of the
preceding vowel**: रामः *rāmaha*, हरिः *harihi*, गुरुः *guruhu*, देवैः
*devaihi*. Both references do this and we do too.

**Word-internally** it does not. दुःख is **two** syllables — guru + laghu.
EdgeSanskrit's `duhukʰa` is three, which changes the metre of any pāda it
appears in. For a Gita application that is a correctness bug, not a nuance. We
emit a plain `h`: `duhkʰa`.

Vāgdhenu instead resolves internal visarga to **jihvāmūlīya** `ᳵ` (before
क ख) and **upadhmānīya** `ᳶ` (before प फ), and to a geminate sibilant before
`स/त/थ`, `श/च/छ`, `ष/ट/ठ`. These are real Classical allophones and Kokoro
*can* spell the first two — `x` (U+0078) and `ɸ` (U+0278) are both in the
vocabulary. But Vāgdhenu's own tech report records (E80h, and the `prep_text.py`
comment) that they left them **plain** in production because the plain form
scored better in A/B. We follow suit: `h` by default, with jihvāmūlīya and
upadhmānīya available behind an option and marked `REVIEW_REQUIRED`.

### 2.4 च-varga — a deliberate divergence from EdgeSanskrit

EdgeSanskrit writes `tʃ`/`dʒ` (affricates). We write `c`/`ɟ` (palatal stops),
for two reasons that point the same way:

1. **Traditional description.** The च-varga is तालव्य — palatal — and the
   Classical stop analysis is the standard one.
2. **Model conditioning.** Kokoro-82M's languages include Hindi, whose eSpeak
   labels use `c`/`ɟ` for च/ज. Those embeddings have therefore been trained
   *in an Indic context*. `ʧ`/`ʤ` are trained too, but from English.

`HindiPhonemizer` reached the same conclusion for the same reason and states
it in its own comments. Marked `REVIEW_REQUIRED` because it is a real
disagreement with a Sanskrit-specific reference.

### 2.5 श — `ʃ` rather than `ɕ`

Classically श is तालव्य, best written `ɕ`, and `ɕ` **is** in Kokoro's
vocabulary. But it reaches Kokoro only through Japanese and Chinese, so in an
Indic or English voice it is thinly conditioned. `ʃ` is heavily trained and
still keeps the three-way श ≠ ष ≠ स contrast intact, which is the property
that actually matters. Default `ʃ`; `ɕ` available as an option.

## 3. Where Sanskrit must not inherit Hindi

Recorded because §7 of the brief makes it a hard rule and because the two
inherited conjuncts are the easiest way to get this wrong.

| | Hindi (this repo, correctly) | Sanskrit (correctly) |
|---|---|---|
| क्ष | `kʃ` — a fused modern reading | `kʂ` — k + ṣ, compositional |
| ज्ञ | `ɡj` — a fused modern reading | `ɟɲ` — j + ñ, compositional |
| कर्म | `kʌrm` — schwa deleted | `kaɾma` |
| final schwa | deleted, with a sonority rule for conjuncts | never deleted |
| stress | assigned by syllable weight | none assigned — see §4 |
| lexicon | overrides, compounds, acronyms, Hinglish, `फ`→`f` stems | none of it applies |
| numbers | `HindiNumbers` expands digits | not used |

`SanskritPhonemizer` shares **no** code with `HindiPhonemizer`. The only shared
utilities are script-range predicates, which are linguistically neutral.

## 4. Stress: none, deliberately

Classical Sanskrit has no phonemic stress accent. Recitation is governed by
mātrā — syllable weight and timing — not by prominence. `HindiPhonemizer`
assigns `ˈ`/`ˌ` by syllable weight because Hindi has stress; Sanskrit does not,
so **we emit no stress marks at all**.

This is the choice most likely to cost us at Gate 3, because Kokoro was trained
on stressed input and may render an unstressed line flatly. If it does, §37
applies: the answer is a Sanskrit voice, not sprinkling `ˈ` into a language
that has no stress to mark. `SanskritPhonology.Options.stress` exists so the
alternative can be *heard* before anyone argues about it — it is not the
default and should not become one without a reason better than "it sounds
livelier".

## 5. Why we do not copy Vāgdhenu's Kannada routing

§5 of the brief asks specifically about this. The answer is in Vāgdhenu's own
tech report, twice:

> **Routes Sanskrit through Kannada script** (IndicF5 was trained on Indic
> scripts; **Devanagari triggers Hindi schwa-deletion**). — line 21
>
> **Schwa:** routing through Kannada (not raw Devanagari) prevents Hindi-style
> schwa deletion. — line 205

IndicF5 is a **script-input** model. It is handed *characters*, and it learned
its Devanagari embeddings from corpora where Devanagari means Hindi — so it
deletes schwas whatever you intend. Kannada script carries no such habit, so
transliterating into it is a way of *escaping a bad embedding*.

Kokoro is a **phoneme-input** model. We compute the IPA ourselves and hand it
over. There is no script embedding, so there is no Hindi habit to escape:
schwa deletion cannot happen unless we write code that does it, and we do not.
The Kannada step has no analogue here and reproducing it would be cargo cult.

Their E30 ablation — *"Kannada vs SLP1 → Kannada wins (rich pretrained
embeddings)"* — is likewise about which embeddings IndicF5 had pretrained. It
is not a claim that Kannada script is a better *linguistic* representation than
SLP1, and it does not transfer to a model whose embeddings are IPA.

What *does* transfer is the layering underneath it, which we adopt:

```
Devanagari
   → SanskritNormalizer     Unicode + orthographic cleanup, still Devanagari
   → SanskritAksharaParser  akṣaras: onset cluster, vowel, marks
   → SanskritPhonology      canonical SLP1-based phonemes + Sanskrit rules
   → SanskritKokoroMapper   canonical → Kokoro IPA, warning on every approximation
   → Tokenizer              Kokoro token ids
```

The canonical layer is **model-independent by construction**. Retargeting to a
different acoustic model means writing a new mapper, not a new phonemizer.

## 6. SLP1 as the canonical representation — adopted

Evaluated as §6 asks, and adopted. It is the right internal representation
because:

1. **One character, one phoneme.** `prep_text.py` puts it plainly: *"SLP1 is
   phonemic: 1 char = 1 phone"*. Every Sanskrit distinction — vowel length,
   aspiration, all three sibilants, all five nasals, retroflex vs dental — is
   a single ASCII symbol. Comparisons and tests are exact string equality.
2. **Lossless.** ऋ/ॠ/ऌ/ॡ, anusvāra, visarga, avagraha all have symbols
   (`f F x X M H '`), so the canonical form loses nothing the model layer might
   later want.
3. **It is what the mature reference uses**, so our canonical column can be
   diffed directly against Vāgdhenu's.
4. **It keeps linguistics and acoustics apart**, which §37 demands. Everything
   contested about Kokoro lives in `SanskritKokoroMapper`.

We do not adopt SLP1 as the *final* representation — Kokoro needs IPA — and we
extend it slightly, following Vāgdhenu's own precedent, for things standard
SLP1 has no symbol for:

| Symbol | Meaning |
|---|---|
| `Z` | jihvāmūlīya (visarga before क/ख) |
| `V` | upadhmānīya (visarga before प/फ) |
| `~` | anunāsika / nasalisation of the preceding segment |
| `\|` | pāda pause (daṇḍa) |
| `\|\|` | verse pause (double daṇḍa) |

## 7. Vedic accent — out of scope, as instructed

Udātta, anudātta and svarita are **not implemented**, per §9. The parser
recognises the Vedic accent marks U+0951 and U+0952 well enough not to choke on
them, drops them, and emits a `VEDIC_ACCENT_IGNORED` warning rather than
failing silently. Vedic recitation is a separate project with a separate
acoustic requirement.

## 8. Open questions for expert review

Ranked by how much they would change what a listener hears.

1. **Visarga at pause** — is the echo vowel wanted for every śloka-final
   visarga, or only at a full stop? We do it at every pause.
2. **Anusvāra before sibilants** (§2.2) — vowel nasalisation vs `m`.
3. **Vocalic ṛ** (§2.1) — `ɾɪ` vs `ɾu` is a regional preference we cannot
   settle from the text.
4. **च-varga** (§2.4) — `c`/`ɟ` vs `ʧ`/`ʤ`.
5. **ऐ/औ** — `aɪ`/`aʊ` vs an explicitly long `aːɪ`/`aːʊ`.
6. **Stress** (§4) — whether an entirely unstressed line is acceptable through
   the current English and Hindi voices.
7. **Internal visarga** (§2.3) — plain `h` vs jihvāmūlīya/upadhmānīya.
