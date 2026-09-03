# काः is arriving as short as क

The reported symptom: मामकाः read as *māmaka* — the final syllable losing both
its length and its visarga.

## What was measured

The frontend is correct: `maːmakaːh`, final syllable `kAH` classed guru at two
mātrās, round-trip clean. So the loss is acoustic. Measured at 0.80 on
`hf_alpha`, final syllable from the `k` closure to the end of speech:

| phonemes | final syllable |
|---|---|
| `maːmaka` — short a | 330 ms |
| `maːmakaː` — long ā | 390 ms |
| **`maːmakaːh` — ours** | **360 ms** |

Two things at once. The model separates long ā from short a by only 18%, and
adding the visarga then pulls it back down: **our काः arrives 9% longer than a
short क.** That is why it is heard as मामक.

## The repair

Per-token duration scaling, which does not touch a phoneme. A visarga-final
syllable is guru by the phonology already computed, so this restores the
duration the analysis specifies rather than inventing one.

`SanskritProsodyIntent.visargaSyllableScale`, at 1.30:

| word | final syllable, plain | repaired | gain |
|---|---|---|---|
| मामकाः | 350 ms | **520 ms** | +49% |
| युयुत्सवः | 670 ms | 890 ms | +33% |
| पाण्डवाः | 890 ms | 1040 ms | +17% |
| **रामः** | **50 ms** | **310 ms** | **+520%** |

रामः is the striking one: its final syllable was essentially absent.

## What this does not fix

**The visarga is still not audible as a visarga.** No symbol in Kokoro's
vocabulary fricates in coda position — established exhaustively over `h`, `x`,
`ɸ` and `s`, across five voices. The repair makes काः a properly long final
syllable; it does not make it *-āḥ*. Expect मामका rather than मामक, not
मामकाः.

Pushed harder the mechanism breaks: at 2.0× and above the model stops
sustaining the vowel and emits disconnected fragments with silence between
them. 1.3× is inside the range it handles.

## Files

`*_plain.wav` against `*_vislen.wav` for मामकाः, रामः, युयुत्सवः and पाण्डवाः —
identical phonemes and tokens, differing only in the per-token duration
multiplier. `len_*.wav` is the scale sweep, including the ones that break.
