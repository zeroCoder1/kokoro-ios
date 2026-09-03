# Bhagavad Gita metre analysis

Diagnostic only. Derived algorithmically from the syllabifier — no pattern was
supplied, no phoneme was adjusted to fit one, and the source text is unchanged.

Rules from sanskritguide.com/chapter-4-syllables, used as a linguistic
reference: one vowel per syllable; a syllable is light iff it ends in a short
vowel; heavy if it has a long vowel, is closed by a consonant, ends in
anusvāra or visarga, or is line-final. Heavy is two mātrās, light one.

## The result validates the frontend

The Gita is written in **anuṣṭubh** — four pādas of eight syllables. The
*pathyā* cadence fixes syllables 5–7 of each pāda: **L G G** in an odd pāda and
**L G L** in an even one. Syllables 1–4 and 8 are free.

Nothing in this codebase knows that. The syllabifier applies phonological rules
to a phoneme stream; it has never seen a metre. Yet across the three verses:

| verse | pāda a | pāda b | pāda c | pāda d |
|---|---|---|---|---|
| BG 1.1 | `GGGG·LGG·G` | `LLGG·LGL·G` | `GLGG·LGG·L` | `LLGL·LGL·G` |
| BG 2.47 | `GGGG·LGG·G` | `GLGL·LGL·G` | `GGLL·LGG·G` | `GGGG·LGL·G` |
| BG 4.7 | `LGLG·LGG·L` | `GGLL·LGL·G` | `GGGL·LGG·L` | `LGGG·LGL·G` |

**All twelve pādas match.** Every odd pāda has L G G at 5–7; every even pāda
has L G L. Twelve independent four-way agreements that no part of the
implementation was fitted to.

That is the strongest evidence available that the akṣara parser, the phonology,
the vowel-length model and the syllabifier are jointly correct — a single wrong
vowel length or a misplaced syllable boundary would break the pattern.

Syllable counts are 16 + 16 for every verse, as an anuṣṭubh printed on two
lines should be, and no verse produced a `PADA_SYLLABLE_COUNT_UNUSUAL` warning.

---

## BG 1.1

SOURCE
  धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।
  मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥

PĀDA 1
  syllables:  Dar · mak · zet · re · ku · ruk · zet · re · sa · ma · ve · tA · yu · yut · sa · vaH
  weights:    GGGGLGGGLLGGLGLG
  mātrās:     2 2 2 2 1 2 2 2 1 1 2 2 1 2 1 2   total 27
  count:      16
  holding:    Dar mak zet ruk zet yut

PĀDA 2
  syllables:  mA · ma · kAH · pAR · qa · vAS · cE · va · ki · ma · kur · va · ta · saY · ja · ya
  weights:    GLGGLGGLLLGLLGLG
  mātrās:     2 1 2 2 1 2 2 1 1 1 2 1 1 2 1 2   total 24
  count:      16
  holding:    pAR vAS kur saY

TOTALS
  syllables per pāda: 16 + 16
  mātrās:             51

WARNINGS
  none

CANONICAL PHONEMES
  Darmakzetre kurukzetre samavetA yuyutsavaH | mAmakAH pARqavAScEva kimakurvata saYjaya ||

## BG 2.47

SOURCE
  कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।
  मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥

PĀDA 1
  syllables:  kar · maR · ye · vA · Di · kA · ras · te · mA · Pa · le · zu · ka · dA · ca · na
  weights:    GGGGLGGGGLGLLGLG
  mātrās:     2 2 2 2 1 2 2 2 2 1 2 1 1 2 1 2   total 27
  count:      16
  holding:    kar maR ras

PĀDA 2
  syllables:  mA · kar · ma · Pa · la · he · tur · BUr · mA · te · saN · gost · va · kar · ma · Ri
  weights:    GGLLLGGGGGGGLGLG
  mātrās:     2 2 1 1 1 2 2 2 2 2 2 2 1 2 1 2   total 27
  count:      16
  holding:    kar tur BUr saN gost kar

TOTALS
  syllables per pāda: 16 + 16
  mātrās:             54

WARNINGS
  none

CANONICAL PHONEMES
  karmaRyevADikAraste mA Palezu kadAcana | mA karmaPalaheturBUrmA te saNgo'stvakarmaRi ||

## BG 4.7

SOURCE
  यदा यदा हि धर्मस्य ग्लानिर्भवति भारत ।
  अभ्युत्थानमधर्मस्य तदात्मानं सृजाम्यहम् ॥

PĀDA 1
  syllables:  ya · dA · ya · dA · hi · Dar · mas · ya · glA · nir · Ba · va · ti · BA · ra · ta
  weights:    LGLGLGGLGGLLLGLG
  mātrās:     1 2 1 2 1 2 2 1 2 2 1 1 1 2 1 2   total 24
  count:      16
  holding:    Dar mas nir

PĀDA 2
  syllables:  aB · yut · TA · na · ma · Dar · mas · ya · ta · dAt · mA · naM · sf · jAm · ya · ham
  weights:    GGGLLGGLLGGGLGLG
  mātrās:     2 2 2 1 1 2 2 1 1 2 2 2 1 2 1 2   total 26
  count:      16
  holding:    aB yut Dar mas dAt jAm ham

TOTALS
  syllables per pāda: 16 + 16
  mātrās:             50

WARNINGS
  none

CANONICAL PHONEMES
  yadA yadA hi Darmasya glAnirBavati BArata | aByutTAnamaDarmasya tadAtmAnaM sfjAmyaham ||

