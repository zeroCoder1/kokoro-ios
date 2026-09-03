import Foundation
import Testing
@testable import KokoroSwift

// Unit tests for the Sanskrit front end, layer by layer.
//
// These assert the *intermediate* forms as well as the final phonemes, because
// a wrong pronunciation is diagnosed by finding the layer that introduced it.
// `canonical` is SLP1 straight from the aksharas and is directly comparable
// against Vagdhenu's output; `phonological` is SLP1 after the rules run;
// `kokoroPhonemes` is what the model is sent.
//
// No Misaki guard is needed anywhere in this file: the Sanskrit path has no
// English fallback and never constructs a Misaki engine.

private func analyze(_ text: String, _ options: SanskritOptions = .default)
  -> SanskritPhonemizer.Result
{
  SanskritPhonemizer.analyze(text, options: options)
}

private func phonemes(_ text: String) -> String {
  SanskritPhonemizer.phonemize(text)
}

// MARK: - Vowels

@Test func independentVowelsAreAllRead() {
  let expected: [(String, String, String)] = [
    ("अत्र", "atra", "atɾa"),
    ("आत्मा", "AtmA", "aːtmaː"),
    ("इति", "iti", "iti"),
    ("ईश", "ISa", "iːʃa"),
    ("उप", "upa", "upa"),
    ("ऊर्ध्व", "UrDva", "uːɾdʰʋa"),
    ("एव", "eva", "eːʋa"),
    ("ओम्", "om", "oːm"),
  ]
  for (input, canonical, ipa) in expected {
    let result = analyze(input)
    #expect(result.canonical == canonical, "\(input) canonical \(result.canonical)")
    #expect(result.kokoroPhonemes == ipa, "\(input) gave \(result.kokoroPhonemes)")
  }
}

@Test func dependentVowelSignsAreAllRead() {
  // The same consonant with each sign in turn, so a mistake in one sign shows
  // up against eleven correct neighbours.
  let signs: [(String, String)] = [
    ("क", "ka"), ("का", "kaː"), ("कि", "ki"), ("की", "kiː"),
    ("कु", "ku"), ("कू", "kuː"), ("के", "keː"), ("कै", "kaɪ"),
    ("को", "koː"), ("कौ", "kaʊ"),
  ]
  for (input, ipa) in signs {
    #expect(phonemes(input) == ipa, "\(input) gave \(phonemes(input))")
  }
}

/// The rule Sanskrit exists on. A consonant with no vowel sign and no virama
/// carries `a`, at the end of a word as much as inside it.
@Test func theInherentVowelIsNeverDeleted() {
  #expect(phonemes("कर्म") == "kaɾma")
  #expect(phonemes("धर्म") == "dʰaɾma")
  #expect(phonemes("योग") == "joːɡa")
  #expect(phonemes("अर्जुन") == "aɾɟuna")
  #expect(phonemes("सञ्जय") == "saɲɟaja")
  #expect(phonemes("पाण्डव") == "paːɳɖaʋa")
  #expect(phonemes("ब्रह्म") == "bɾahma")
  #expect(phonemes("क्षेत्र") == "kʂeːtɾa")
  #expect(phonemes("शास्त्र") == "ʃaːstɾa")
  #expect(phonemes("मन्त्र") == "mantɾa")
}

/// The same words through the Hindi engine, to prove the two paths really are
/// separate rather than merely intended to be.
@Test func sanskritDoesNotInheritHindiSchwaDeletion() {
  for word in ["कर्म", "धर्म", "योग", "अर्जुन"] {
    let sanskrit = phonemes(word)
    let hindi = HindiPhonemizer.phonemize(word)
    #expect(sanskrit != hindi, "\(word) read identically to Hindi: \(sanskrit)")
    #expect(sanskrit.hasSuffix("a"), "\(word) lost its final vowel: \(sanskrit)")
  }
  // And the two inherited conjuncts, which modern Hindi fuses and Sanskrit
  // reads compositionally.
  #expect(phonemes("क्षेत्र").hasPrefix("kʂ"))
  #expect(phonemes("ज्ञान").hasPrefix("ɟɲ"))
  #expect(HindiPhonemizer.phonemize("क्षेत्र").hasPrefix("kʃ"))
}

@Test func phonemicVowelLengthIsPreserved() {
  // The five length pairs must never merge.
  let pairs: [(String, String)] = [
    ("अत्र", "आत्मा"), ("दिन", "दीन"), ("सुत", "सूत"),
    ("ऋषि", "ॠकार"), ("ऌकार", "ॡकार"),
  ]
  for (short, long) in pairs {
    #expect(phonemes(short) != phonemes(long))
  }
  #expect(phonemes("दिन") == "dina")
  #expect(phonemes("दीन") == "diːna")
  #expect(phonemes("सुत") == "suta")
  #expect(phonemes("सूत") == "suːta")
}

/// e and o are historically monophthongised diphthongs and are always guru.
/// EdgeSanskrit writes them short, which loses a distinction metre depends on.
@Test func eAndOAreAlwaysLong() {
  #expect(phonemes("एव") == "eːʋa")
  #expect(phonemes("योग") == "joːɡa")
  #expect(phonemes("ते") == "teː")
  for vowel in [SanskritVowel.e, .o, .ai, .au] {
    #expect(vowel.isLong, "\(vowel.rawValue) should be long")
  }
}

@Test func vocalicLiquidsAreApproximatedAndReported() {
  let r = analyze("ऋषि")
  #expect(r.canonical == "fzi")
  #expect(r.kokoroPhonemes == "ɾɪʂi")
  #expect(r.warnings.contains { $0.text.contains("KOKORO_APPROXIMATION") })
  #expect(r.warnings.contains { $0.text.contains("vocalic ṛ") })

  // Long against short, and the long one reports separately.
  #expect(phonemes("ॠकार") == "ɾiːkaːɾa")
  #expect(phonemes("कृष्ण") == "kɾɪʂɳa")
  #expect(phonemes("ऌकार") == "lɪkaːɾa")
  #expect(phonemes("ॡकार") == "liːkaːɾa")
  #expect(analyze("ॡकार").warnings.contains { $0.text.contains("ḹ") })

  // The South Indian realisation, which is equally traditional.
  var options = SanskritOptions.default
  options.vocalicLiquid = .ru
  #expect(analyze("कृष्ण", options).kokoroPhonemes == "kɾuʂɳa")
}

// MARK: - Consonants

@Test func everyAspirationContrastSurvives() {
  let pairs: [(String, String)] = [
    ("कर", "खर"), ("गज", "घट"), ("चल", "छल"), ("जन", "झष"),
    ("तप", "थल"), ("दम", "धन"), ("पल", "फल"), ("बल", "भय"),
    ("टीका", "ठग"), ("डम", "ढक्क"),
  ]
  for (plain, aspirated) in pairs {
    #expect(phonemes(plain) != phonemes(aspirated))
  }
  #expect(phonemes("कर") == "kaɾa")
  #expect(phonemes("खर") == "kʰaɾa")
  #expect(phonemes("धन") == "dʰana")
}

@Test func dentalAndRetroflexNeverMerge() {
  #expect(phonemes("तप") == "tapa")
  #expect(phonemes("टप") == "ʈapa")
  #expect(phonemes("दम") == "dama")
  #expect(phonemes("डम") == "ɖama")
  #expect(phonemes("तप") != phonemes("टप"))
  #expect(phonemes("दम") != phonemes("डम"))
}

/// श, ष and स are three different sounds and must stay three.
@Test func theThreeSibilantsStayDistinct() {
  let sha = phonemes("शर")
  let ssa = phonemes("षड")
  let sa = phonemes("सर")
  #expect(sha == "ʃaɾa")
  #expect(ssa == "ʂaɖa")
  #expect(sa == "saɾa")
  #expect(Set([sha, ssa, sa]).count == 3)

  // The more accurate palatal value is available, and keeps the contrast.
  var options = SanskritOptions.default
  options.palatalSibilant = .alveoloPalatal
  #expect(analyze("शर", options).kokoroPhonemes == "ɕaɾa")
}

@Test func allFiveNasalsAreDistinct() {
  let nasals = ["अङ्ग", "पञ्च", "अण्ड", "अन्त", "अम्ब"].map(phonemes)
  #expect(nasals == ["aŋɡa", "paɲca", "aɳɖa", "anta", "amba"])
  #expect(Set(nasals).count == 5)
}

@Test func vaIsAnApproximantAndPalatalsAreStops() {
  #expect(phonemes("वन") == "ʋana")
  #expect(phonemes("चल") == "cala")
  #expect(phonemes("जन") == "ɟana")

  var options = SanskritOptions.default
  options.palatalStops = .affricates
  #expect(analyze("चल", options).kokoroPhonemes == "ʧala")
  #expect(analyze("जन", options).kokoroPhonemes == "ʤana")
}

/// The one letter Kokoro genuinely cannot say.
@Test func retroflexLateralIsReportedUnsupported() {
  let result = analyze("ळ")
  #expect(result.kokoroPhonemes == "la")
  #expect(result.warnings.contains { $0.text.hasPrefix("KOKORO_UNSUPPORTED") })
  #expect(result.warnings.contains { $0.text.contains("ɭ") })
}

// MARK: - Virama and conjuncts

@Test func viramaLeavesAConsonantWithNoVowel() {
  #expect(phonemes("क") == "ka")
  #expect(phonemes("का") == "kaː")
  #expect(phonemes("कि") == "ki")
  #expect(phonemes("क्") == "k")
  #expect(phonemes("भगवान्") == "bʰaɡaʋaːn")
  #expect(phonemes("ब्रह्मन्") == "bɾahman")

  let bare = analyze("क्")
  #expect(bare.units.count == 1)
  if case let .some(.akshara(akshara)) = bare.units.first {
    #expect(akshara.onset == [.ka])
    #expect(akshara.vowel == nil)
  } else {
    Issue.record("expected a single akshara")
  }
}

/// Conjuncts are parsed compositionally, so arbitrary depth works without a
/// table. `क्त्व` is three consonants in one cluster.
@Test func conjunctsAreCompositional() {
  let expected: [(String, String)] = [
    ("क्ष", "kʂa"), ("त्र", "tɾa"), ("ज्ञ", "ɟɲa"), ("श्र", "ʃɾa"),
    ("क्त", "kta"), ("क्त्व", "ktʋa"), ("त्त्व", "ttʋa"), ("द्व", "dʋa"),
    ("द्भ", "dbʰa"), ("द्ध", "ddʰa"), ("न्त", "nta"), ("न्ध", "ndʰa"),
    ("न्द", "nda"), ("म्प", "mpa"), ("म्ब", "mba"), ("स्थ", "stʰa"),
    ("स्म", "sma"), ("स्व", "sʋa"), ("ह्म", "hma"), ("ह्न", "hna"),
  ]
  for (input, ipa) in expected {
    #expect(phonemes(input) == ipa, "\(input) gave \(phonemes(input))")
  }

  // The three-consonant cluster really is one akshara.
  let ktva = analyze("क्त्व")
  #expect(ktva.units.count == 1)
  #expect(ktva.canonical == "ktva")
}

@Test func conjunctsInsideRealWords() {
  let expected: [(String, String)] = [
    ("क्षेत्रज्ञ", "kʂeːtɾaɟɲa"),
    ("क्षत्रिय", "kʂatɾija"),
    ("विज्ञान", "ʋiɟɲaːna"),
    ("प्रज्ञा", "pɾaɟɲaː"),
    ("श्रद्धा", "ʃɾaddʰaː"),
    ("अश्वत्थामा", "aʃʋattʰaːmaː"),
    ("तत्त्व", "tattʋa"),
    ("यज्ञ", "jaɟɲa"),
    ("गाण्डीव", "ɡaːɳɖiːʋa"),
    ("अच्युत", "acjuta"),
  ]
  for (input, ipa) in expected {
    #expect(phonemes(input) == ipa, "\(input) gave \(phonemes(input))")
  }
}

// MARK: - Anusvara

/// The five varga environments, where all three references agree.
@Test func anusvaraTakesTheHomorganicNasal() {
  let expected: [(String, String, String)] = [
    ("संकल्प", "saNkalpa", "saŋkalpa"),
    ("संचय", "saYcaya", "saɲcaja"),
    ("कुंठित", "kuRWita", "kuɳʈʰita"),
    ("संतोष", "santoza", "santoːʂa"),
    ("संपत्", "sampat", "sampat"),
  ]
  for (input, phonological, ipa) in expected {
    let result = analyze(input)
    #expect(result.phonological == phonological, "\(input) gave \(result.phonological)")
    #expect(result.kokoroPhonemes == ipa, "\(input) gave \(result.kokoroPhonemes)")
  }
}

/// The canonical form keeps the anusvara as a mark; only the phonological
/// stage resolves it. That separation is what makes the canonical column
/// comparable against a reference.
@Test func theCanonicalFormKeepsTheAnusvaraUnresolved() {
  let result = analyze("संकल्प")
  #expect(result.canonical == "saMkalpa")
  #expect(result.phonological == "saNkalpa")
}

/// REVIEW_REQUIRED. Vagdhenu keeps a nasal continuant here; EdgeSanskrit
/// forces `m` and so says *samskrita* and *samyoga*, which no reciter does.
@Test func anusvaraBeforeAContinuantNasalisesTheVowel() {
  for word in ["संयोग", "संरक्ष", "संलग्न", "संवाद", "संशय", "संस्कृत", "संहार"] {
    let result = analyze(word)
    // Scalars, not Characters: `ã` is one grapheme cluster, so a Character
    // search for the combining tilde finds nothing. This is the same trap the
    // tokenizer avoids by iterating scalars, and it is why the nasal mark
    // survives as its own token.
    #expect(
      result.kokoroPhonemes.unicodeScalars.contains("\u{0303}"),
      "\(word) lost its nasalisation"
    )
    #expect(!result.kokoroPhonemes.hasPrefix("sam"), "\(word) took a labial nasal")
    #expect(result.warnings.contains { $0.text.contains("anusvāra before a continuant") })
  }
  #expect(phonemes("संस्कृत") == "sãskɾɪta")
  #expect(phonemes("संयोग") == "sãjoːɡa")

  // The other reading, for comparison by ear.
  var options = SanskritOptions.default
  options.anusvaraBeforeContinuant = .labialNasal
  #expect(analyze("संस्कृत", options).kokoroPhonemes == "samskɾɪta")
}

@Test func wordFinalAnusvaraIsALabialNasal() {
  for (input, ipa) in [("अहं", "aham"), ("त्वं", "tʋam"), ("इदं", "idam"), ("एतं", "eːtam")] {
    #expect(phonemes(input) == ipa, "\(input) gave \(phonemes(input))")
  }
}

// MARK: - Visarga

/// At a pause the visarga takes an echo of the vowel before it, which is what
/// recitation sounds like and what both Sanskrit references do.
@Test func visargaTakesItsEchoVowelAtAPause() {
  let expected: [(String, String)] = [
    ("रामः", "ɾaːmaha"),
    ("हरिः", "haɾihi"),
    ("गुरुः", "ɡuɾuhu"),
    ("देवैः", "deːʋaɪhi"),
    ("युयुत्सवः", "jujutsaʋaha"),
    ("पाण्डवाः", "paːɳɖaʋaːha"),
    ("नमः", "namaha"),
    ("श्रेयः", "ʃɾeːjaha"),
  ]
  for (input, ipa) in expected {
    #expect(phonemes(input) == ipa, "\(input) gave \(phonemes(input))")
  }
}

/// Word-internally it does not, and that is where EdgeSanskrit goes wrong:
/// its `duhukʰa` is three syllables where Sanskrit has two, which changes the
/// metre of any pada the word appears in.
@Test func visargaInsideAWordDoesNotTakeAnEchoVowel() {
  #expect(phonemes("दुःख") == "duhkʰa")
  #expect(phonemes("निःशेष") == "nihʃeːʂa")
  #expect(phonemes("अन्तःकरण") == "antahkaɾaɳa")
  // Three syllables of vowel in duhkha would mean an extra `u`.
  #expect(phonemes("दुःख").filter { "aeiou".contains($0) }.count == 2)
}

/// Mid-line, before another word, it is a plain h rather than an echo: a pause
/// is a danda or the end of the text, not any word boundary.
@Test func visargaBeforeAnotherWordIsPlain() {
  #expect(phonemes("रामः करोति") == "ɾaːmah kaɾoːti")
  #expect(phonemes("रामः पश्यति") == "ɾaːmah paʃjati")
  // ...but the last word in the line is at a pause.
  #expect(phonemes("रामः षष्ठः").hasSuffix("ʂaʂʈʰaha"))
}

@Test func visargaIsNeverDroppedOrTurnedIntoHa() {
  for word in ["रामः", "दुःख", "नमः", "अर्जुनः", "योगः"] {
    #expect(phonemes(word).contains("h"), "\(word) lost its visarga")
    #expect(analyze(word).canonical.contains("H"))
  }
}

/// The Classical allophones, available and off by default.
@Test func placeAssimilatedVisargaIsAvailable() {
  var options = SanskritOptions.default
  options.internalVisarga = .placeAssimilated
  #expect(analyze("दुःख", options).kokoroPhonemes == "duxkʰa")
  #expect(analyze("रामः पश्यति", options).kokoroPhonemes == "ɾaːmaɸ paʃjati")
}

// MARK: - Chandrabindu, avagraha, dandas

@Test func chandrabinduNasalisesTheVowel() {
  #expect(phonemes("हुँ") == "hũ")
  #expect(analyze("हुँ").canonical == "hu~")
  // Never reduced to a nasal consonant, and never dropped as EdgeSanskrit does.
  #expect(!phonemes("हुँ").contains("m"))
  #expect(phonemes("हुँ") != phonemes("हु"))
}

/// Avagraha is a silent elision marker. It is not a length mark, which is what
/// EdgeSanskrit makes of it.
@Test func avagrahaIsSilentButKeptAsABoundary() {
  #expect(phonemes("सोऽहम्") == "soːham")
  #expect(phonemes("नरोऽपराणि") == "naɾoːpaɾaːɳi")
  #expect(phonemes("तेऽपि") == "teːpi")
  #expect(analyze("सोऽहम्").canonical == "so'ham")
  #expect(analyze("सोऽहम्").units.contains(.boundary(.elision)))
}

@Test func dandasArePausesAndAreNeverPronounced() {
  let result = analyze("अस्ति । नास्ति ॥")
  #expect(result.kokoroPhonemes == "asti, naːsti.")
  #expect(result.units.contains(.boundary(.pada)))
  #expect(result.units.contains(.boundary(.verse)))
  // The two strengths differ, which is what the danda distinction is for.
  #expect(SanskritBoundary.pada.isPause)
  #expect(SanskritBoundary.verse.isPause)
  #expect(!SanskritBoundary.word.isPause)
}

/// One ligature scalar with no parseable parts. EdgeSanskrit produces nothing
/// at all for it.
@Test func omIsExpandedRatherThanDropped() {
  #expect(phonemes("ॐ") == "oːm")
  #expect(analyze("ॐ").normalized == "ओम्")
  #expect(phonemes("ॐ नमः शिवाय") == "oːm namah ʃiʋaːja")
}

// MARK: - Normalization and robustness

@Test func joinControlsDoNotChangeTheReading() {
  // The same conjunct with and without a zero-width joiner.
  #expect(phonemes("क्ष") == phonemes("क्\u{200D}ष"))
  #expect(phonemes("क्ष") == phonemes("क्\u{200C}ष"))
}

@Test func decomposedAndComposedInputAgree() {
  // U+0958 has a singleton decomposition, so the two spellings of the same
  // letter must not read differently.
  #expect(phonemes("\u{0958}") == phonemes("\u{0915}\u{093C}"))
  // Whitespace is collapsed rather than producing empty boundaries.
  #expect(phonemes("  कर्म   योग  ") == "kaɾma joːɡa")
}

@Test func vedicAccentsAreDroppedAndReported() {
  let result = analyze("अ\u{0951}ग्नि")
  #expect(result.warnings.contains(.vedicAccentIgnored))
  #expect(result.kokoroPhonemes == "aɡni")
}

@Test func malformedInputIsSurvivedAndReported() {
  // A stranded vowel sign, and a doubled virama.
  let stranded = analyze("ा")
  #expect(stranded.kokoroPhonemes.isEmpty)
  #expect(stranded.warnings.contains { $0.text.hasPrefix("ORPHANED_MARK") })

  let doubled = analyze("क््")
  #expect(doubled.kokoroPhonemes == "k")
  #expect(doubled.warnings.contains { $0.text.hasPrefix("ORPHANED_MARK") })

  #expect(analyze("").kokoroPhonemes.isEmpty)
  #expect(analyze("   ").kokoroPhonemes.isEmpty)
}

/// Classical recitation has no Latin and no digits in it, so they are dropped
/// with a warning rather than guessed at.
@Test func nonDevanagariIsDroppedAndReported() {
  let mixed = analyze("धर्म dharma")
  #expect(mixed.kokoroPhonemes == "dʰaɾma")
  #expect(mixed.warnings.contains { $0.text.contains("dharma") })
  // One warning for the run, not one per letter.
  #expect(mixed.warnings.count == 1)

  let numbered = analyze("अध्याय १")
  #expect(numbered.kokoroPhonemes == "adʰjaːja")
  #expect(numbered.warnings.contains { $0.text.contains("१") })

  let latinOnly = analyze("Bhagavad Gita")
  #expect(latinOnly.kokoroPhonemes.isEmpty)
  #expect(!latinOnly.warnings.isEmpty)
}

@Test func nuktaLettersAreReadAsTheirBaseConsonant() {
  let result = analyze("ज़")
  #expect(result.kokoroPhonemes == "ɟa")
  #expect(result.warnings.contains { $0.text.contains("not Classical Sanskrit") })
}

// MARK: - Source offsets

/// Preserved so a future word-highlighting feature can trace a source word
/// through to its tokens. No forced alignment is implemented yet.
@Test func aksharasCarryTheirSourceOffsets() {
  let result = analyze("कर्म")
  let aksharas: [SanskritAkshara] = result.units.compactMap {
    if case let .akshara(akshara) = $0 { return akshara }
    return nil
  }
  #expect(aksharas.count == 2)
  #expect(aksharas[0].sourceOffsets.lowerBound == 0)
  for akshara in aksharas {
    #expect(akshara.sourceOffsets.lowerBound < akshara.sourceOffsets.upperBound)
    #expect(akshara.sourceOffsets.upperBound <= result.normalized.unicodeScalars.count)
  }
  // In order, and covering the word without gaps.
  #expect(aksharas[0].sourceOffsets.upperBound == aksharas[1].sourceOffsets.lowerBound)
}
