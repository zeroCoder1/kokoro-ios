# What a Sanskrit fine-tune needs

Written because the mapping experiments concluded **B**: a few sounds improve
through remapping, and the rest need a model that has heard Sanskrit.

**Nothing here starts training.** It records what the training data must cover
and — more importantly — what must *not* be changed to accommodate a weak base
voice.

## The governing rule

> The existing frontend is the source of training labels. Labels are never
> adjusted to mimic what the current model can already say.

`HindiTrainingLabels` is the precedent, and its reasoning applies verbatim:
labelling with this repository's phonemizer rather than eSpeak is what makes a
fine-tune learn the phonemes inference will actually send it. Five diagnostic
passes have found no frontend bug since the v2 visarga correction; that
correctness is the asset the training run depends on.

If a label looks wrong because the base voice renders it badly, the label is
still right.

## Canonical phoneme inventory to preserve

The training labels must carry every distinction below. Each is currently
correct and asserted by tests.

**Vowels (14).** a ā i ī u ū ṛ ṝ ḷ ḹ e ai o au — with e, ai, o and au long for
prosody. Five phonemic length pairs, none of which may merge.

**Consonants (33), as a feature matrix.**

| varga | members | features |
|---|---|---|
| velar | क ख ग घ ङ | place velar; cols 1–2 voiceless, 3–4 voiced; 2 and 4 aspirated |
| palatal | च छ ज झ ञ | as above, palatal |
| retroflex | ट ठ ड ढ ण | as above, retroflex |
| dental | त थ द ध न | as above, dental |
| labial | प फ ब भ म | as above, labial |
| antaḥstha | य र ल व | semivowels |
| ūṣman | श ष स ह | palatal / retroflex / dental sibilants, plus ह |

**Aspirated stops are single phonemes.** ख is not क + ह. Ten pairs.

**Marks.** anusvāra (homorganic before a varga, nasalised before a continuant),
visarga, chandrabindu, avagraha, virāma.

**Prosody.** Syllable weight (guru/laghu), mātrā counts, conjunct holding, and
pāda/verse boundaries — all computed and validated against anuṣṭubh.

## What the base model cannot do, and what recordings must therefore cover

Ranked by how badly the current model fails.

### 1. Visarga — the hardest gap

Kokoro realises `h` only word-initially: onset `h` measures ZCR 0.122, coda `h`
0.040 — no frication at all. No symbol in the vocabulary fricates in coda
(`h`, `x`, `ɸ`, `s`, `ç` all tested), and no voice differs.

**Recordings must cover** visarga after every vowel and in every environment:

- after a: रामः, नमः, योगः, अर्जुनः, सङ्गः
- after ā: मामकाः, पाण्डवाः, देवाः, काः
- after i / ī: हरिः, धीः, कविः
- after u / ū: गुरुः, भूः, साधुः
- after e / o: हरेः, गुरोः
- word-internal: दुःख, निःशेष, अन्तःकरण, दुःशासन
- before an unvoiced velar and labial (jihvāmūlīya / upadhmānīya contexts):
  रामः करोति, रामः पश्यति
- at a pāda end, where the traditional echo vowel appears: युयुत्सवः ।

### 2. Vocalic ṛ

No syllabic diacritic exists in the vocabulary, and both symbols that could
carry rhotic colour are untrained (`ɻ` 0, `ɽ` 1). `ɚ` is the best available
approximation and still an approximation.

**Recordings must cover** ṛ in every consonant context — कृ गृ तृ दृ पृ मृ वृ
सृ हृ — and in words: कृष्ण, कृत, कृपा, गृह, तृप्त, दृष्टि, पृथ्वी, मृत्यु,
वृत्ति, सृजति, हृदय, प्रकृति. Long ṝ separately: ॠकार, पितॄन्. Vocalic ḷ is
rare but should appear at least once: क्ऌप्त.

### 3. Final nasal closure

Final stops close correctly (तत् / तत ratio 3.36) but final nasals do not
(भगवान् / भगवान 1.01) in any of five voices.

**Recordings must cover** words ending in म् and न् against their open forms:
अहम् / अहम, भगवान् / भगवान, ब्रह्मन्, तदात्मानम्, अभ्युत्थानम्, सृजाम्यहम्,
किम्, त्वम्, इदम्, एतत्, कदाचित्.

### 4. Retroflex and palatal series — thinly trained

Across all nine training languages: `ʂ` 4 occurrences, `ɖ` 1, `ɳ` 9, `ɟ` 12,
`ʈ` 13, `ɲ` 7 — against `s` 4336 and `t` 4129.

**Recordings must cover** the contrasts directly:

- ś / ṣ / s: शक्ति, षट्, सत् · शास्त्र, कृष्ण, सम · श्रद्धा, क्षेत्र, सञ्जय
- ṅ / ñ / ṇ / n / m: सङ्ग, सञ्जय, पाण्डव, सन्त, सम्पद्
- retroflex vs dental: टप/तप, डम/दम, ठग/थल, ढक्क/धन, णत्व/नर
- all ten aspiration pairs: कर/खर, गज/घट, चल/छल, जन/झष, टीका/ठग, डम/ढक्क,
  तप/थल, दम/धन, पल/फल, बल/भय

### 5. Dense conjuncts

These parse correctly and compress acoustically; splitting them measurably
makes articulation *worse* (धर्मक्षेत्रे: 5 nuclei split vs 6 joined), so the
model must learn them as they are written.

**Recordings must cover** क्ष त्र ज्ञ श्र क्त क्त्व त्त्व द्व द्भ द्ध न्त न्ध
न्द म्प म्ब स्थ स्म स्व ह्म ह्न र्मक्ष ण्य श्च र्भ भ्य त्थ ङ्ग स्त्व ञ्ज,
and the long compounds: कर्मण्येवाधिकारस्ते, कर्मफलहेतुर्भूर्मा,
सङ्गोऽस्त्वकर्मणि, अभ्युत्थानमधर्मस्य.

### 6. Chant tempo — the model cannot be stretched into it

A reciter holds a syllable for **477 ms** (median over 585 anuṣṭubh verses of
the Gītā Supersite recordings). Kokoro at the shipped `recitation` rate gives
**195 ms** — 2.4× faster.

Closing that from the frontend was tried and failed. Speed 0.30 matches the
figure numerically (475 ms) and shows no F0 instability, but the rendered verse
is **unintelligible on listening**: stretching every phoneme 2.7× past the
decoder's normal range leaves pitch intact and destroys consonant articulation.

**Recordings must therefore carry the tempo itself**, at chant pace rather than
read pace, and the training labels must carry the syllable and mātrā metadata
alongside so the duration predictor learns held syllables rather than inheriting
stretched short ones.

The reciter is also continuous — 0.0% internal silence at a 2% energy gate,
against 21–29% for this model at every rate. Whatever is trained should learn
that phrasing too: silence between syllables is not how a śloka is recited.

### 6. Vowel length in context

Length is honoured in isolation (भु 390 ms → भू 545, 1.40×) and weakens inside
clusters (र्भु → र्भू only 1.16×) and collapses word-finally (कर्मणि / कर्मणी
1.02).

**Recordings must cover** all five length pairs in three positions — initial,
medial, final — and word-finally in particular: कर्मणि/कर्मणी, भवति/भवती,
कदाचन/कदाचना, सञ्जय/सञ्जया.

## Minimum validation corpus

`Tools/sanskrit-listening-corpus.txt` already exercises every phoneme and
conjunct and is the starting point. A training run should additionally hold out:

- the three validation verses (BG 1.1, 2.47, 4.7), never trained on
- ten further ślokas covering the metre variants
- the visarga, vocalic-ṛ and final-closure minimal-pair sets from
  `Artifacts/sanskrit/experiments/`
- the anuṣṭubh scan as an automated check: all twelve pādas must still match
  the pathyā cadence after training

## How to label

1. Run `SanskritPhonemizer` over each transcript, exactly as inference will.
2. Reject any clip whose phonemes contain a token outside the vocabulary —
   `SanskritTokenAudit` is the check, and `HindiTrainingLabels` shows the
   pattern of hard rejection rather than silent inclusion.
3. Record the syllable and mātrā metadata alongside; the duration predictor is
   what most needs it.
4. Keep every `KOKORO_APPROXIMATION` warning with its clip. A fine-tune is the
   moment those become fixable, and knowing which clips carry them is what makes
   that measurable.

## Consider extending the vocabulary

If a fine-tune is happening anyway, the token set is worth revisiting. IndicVoice
added 37 entries to Kokoro-82M for Indic. The two that would matter most here:

- a **syllabic diacritic** (U+0329), which would make ṛ and ḷ exact rather than
  approximate
- **`ɦ`**, the breathy voiced h, which ह properly is and base Kokoro lacks

`ɭ` would also make ळ supported rather than the one unsupported letter.

## Expert review

The frontend is defensible on paper — the metre scan is strong evidence — but
sacred text warrants a human check before any of this is treated as settled.
Review should cover, in order:

1. The **canonical SLP1** for a sample of verses, which is script-independent
   and does not require listening to anything.
2. The **open questions** in `docs/SANSKRIT_G2P_RESEARCH.md` §8: the visarga
   echo at pause, anusvāra before sibilants, ऋ as `ɾɪ` / `ɾu` / `ɚ`, the
   च-varga as stops or affricates, and ऐ/औ.
3. The **audio**, last. It is the least reliable signal while the acoustic
   model is the known weak link.
