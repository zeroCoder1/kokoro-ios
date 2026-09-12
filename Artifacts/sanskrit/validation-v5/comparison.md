# validation-v5 versus the previous recitation build

Previous build: `0f6fb3c`. This one adds two duration repairs and **fixes a
regression the last one introduced**.

| | previous | v5 |
|---|---|---|
| visarga before a **short** vowel | vowel lengthened ×1.3 — *wrong* | vowel untouched, `h` only |
| visarga before a **long** vowel | vowel + `h` ×1.3 | unchanged |
| word-final short vowel | none | ×0.80 |
| phonemes | — | **byte-identical throughout** |
| recitation speed | 0.80 | 0.80 |

Evidence: `../diagnostics/word-final-closure-audit.md`.

## The regression, and its fix

Two of the reported errors were **caused by the visarga repair added in
`8651da0`**. It lengthened the vowel before a visarga unconditionally:

```
मामकाः     maːmak[a×1.3][ː×1.3][h×1.3]   ← ā genuinely long: correct
युयुत्सवः   jujutsaʋ[a×1.3][h×1.3]        ← a genuinely SHORT: वः → वाः
```

That is exactly *युयुत्सवाह*. A short vowel lengthened is a different vowel,
which §22 forbids. Now:

```
युयुत्सवः   jujutsaʋa[h×1.30]                  ← short a untouched
मामकाः     maːmak[a×1.30][ː×1.30][h×1.30]     ← long ā still repaired
```

## Issue tracker

| item | frontend | previous | v5 | status |
|---|---|---|---|---|
| **धर्मक्षेत्रे** | `dʰaɾmakʂeːtɾeː` correct | — | unchanged | `FRONTEND_CORRECT` |
| **समवेता** | `samaʋeːtaː` correct | — | unchanged; final ā is long so no repair applies | `FRONTEND_CORRECT` |
| **युयुत्सवः** | `jujutsaʋah` correct | short a wrongly lengthened | **short a restored** | **RESOLVED** (was our bug) |
| **मामकाः** | `maːmakaːh` correct | both ā and `h` ×1.3 | unchanged; `h` still unfricated | `ACOUSTIC_MODEL_LIMITATION: VISARGA` |
| **पाण्डवाश्चैव** | `paːɳɖaʋaːʃcaɪʋa` correct | — | unchanged | `FRONTEND_CORRECT` |
| **सञ्जय** | `saɲɟaja`, `ɲ` present, no `n` | final a lengthened | **×0.80** | **IMPROVED** |
| **कदाचन** | `kadaːcana` correct | final a lengthened | **×0.80** | **IMPROVED** |
| **कर्मणि** | `kaɾmaɳi`, short `i` | ratio 1.02 vs कर्मणी | **×0.80 → ratio 0.79** | **IMPROVED** |
| **हेतुर्भूर्मा** | `heːtuɾbʰuːɾmaː` correct | — | unchanged; final ā long, no repair | `FRONTEND_CORRECT` |
| **सङ्गोऽस्त्वकर्मणि** | `saŋɡoːstʋakaɾmaɳi` correct | — | final short `i` now ×0.80 | **IMPROVED** |
| **अभ्युत्थानम्** | `abʰjuttʰaːnam` closed | — | unchanged | `ACOUSTIC_EPENTHESIS` (final nasal) |
| **सृजाम्यहम्** | `sɾɪɟaːmjaham` closed | — | unchanged | `ACOUSTIC_MODEL_LIMITATION: VOCALIC_R` |

## What the measurements say

**Final stops close correctly and need nothing.** तत् is 110 ms against तत at
370 (ratio 3.36); कृत् 110 against 490 (4.45).

**Final nasals do not.** भगवान् / भगवान measures 1.01 — the closure is lost.
No voice avoids it (ratios 1.04–1.15 across all five). Not fixable from here.

**Final short vowels are lengthened**, and the ×0.80 repair restores the
contrast:

| word | ×1.00 | ×0.80 | reference |
|---|---|---|---|
| कर्मणि | 950 ms | ~820 ms | कर्मणी 970 ms |
| भवति | 370 ms | ~270 ms | भवती 420 ms |
| कदाचन | 630 ms | ~520 ms | कदाचना 580 ms |

**Speed does not help.** The final syllable's share of the word is essentially
flat from 0.72 to 1.00 — कदाचन 50%→57%, युयुत्सवः 51%→56%, मामकाः 32%→40%.
Slowing down buys articulation, not closure.

**One real voice difference.** `hf_alpha` is the only voice that preserves
final stop closure (ratio 3.27; the others 0.62–1.33). It remains the default,
now for a measured reason.

## How to judge this set

The verses differ from the previous build only in duration, never in phonemes.

1. **`yuyutsavah.wav`** — the regression fix. It should no longer sound like
   *युयुत्सवाह*; the vowel before the visarga should be short again.
2. **`sanjaya.wav`, `kadachana.wav`, `karmani.wav`** — final vowels should be
   light rather than drawn out. कर्मणि should no longer sound like कर्मणी.
3. **`aham.wav`, `bhagavan.wav`** — these will still open at the end. The
   frontend closes them; the model does not, and no voice does.
4. **`mamakah.wav`, `ramah.wav`** — the visarga still has no frication. Long
   established and not fixable from the frontend.

## Unresolved

| | why |
|---|---|
| **visarga frication** | no symbol in the vocabulary fricates in coda, across five voices |
| **final nasal closure** | ratio ~1.0 in every voice; the model opens a closed syllable |
| **vocalic ṛ** | `ɻ` untrained, `ɽ` untrained, no syllabic diacritic exists |

All three are the acoustic model, with correct tokens reaching it. Changing the
phonemes to mask them is the hack §22 forbids and would poison the labels a
fine-tune depends on.
