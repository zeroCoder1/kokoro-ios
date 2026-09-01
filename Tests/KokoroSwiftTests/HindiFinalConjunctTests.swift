import Testing
@testable import KokoroSwift

// Final-conjunct schwa.
//
// Whether a consonant closing a written conjunct keeps the inherent schwa is
// decided by sonority: a cluster that rises into its last consonant needs a
// vowel to release it, one that is level or falling does not. व is the
// exception and never takes it.
//
// र and य are kept in separate groups deliberately. They were investigated
// separately and turned out to follow one principle, but if a future model
// ever wants them apart, this is where that shows up first.
//
// Expected values agree with espeak on every case here. That agreement is
// evidence, not the goal — see Tools/espeak-diff.py.

private func checkConjuncts(_ cases: [HindiWordCase]) {
  for testCase in cases {
    #expect(
      HindiPhonemizer.phonemize(testCase.word) == testCase.phonemes,
      "\(testCase.word): got \(HindiPhonemizer.phonemize(testCase.word)), want \(testCase.phonemes)"
    )
  }
}

/// A rising cluster ending in र keeps the schwa.
private let finalRaConjuncts: [HindiWordCase] = [
    ("राष्ट्र", "ɾˈaːʂʈɾə"),
    ("क्षेत्र", "kʃˈeːtɾə"),
    ("केंद्र", "kˈe\u{0303}ːdɾə"),
    ("मित्र", "mˈɪtɾə"),
    ("चित्र", "cˈɪtɾə"),
    ("पत्र", "pˈʌtɾə"),
    ("सूत्र", "sˈuːtɾə"),
    ("शास्त्र", "ʃˈaːstɾə"),
    ("मंत्र", "mˈʌntɾə"),
    ("यंत्र", "jˈʌntɾə"),
    ("तंत्र", "tˈʌntɾə"),
    ("पुत्र", "pˈʊtɾə"),
    ("मूत्र", "mˈuːtɾə"),
    ("वस्त्र", "ʋˈʌstɾə"),
    ("सत्र", "sˈʌtɾə"),
    ("गोत्र", "ɡˈoːtɾə"),
    ("मात्र", "mˈaːtɾə"),
    ("पात्र", "pˈaːtɾə"),
    ("छात्र", "cʰˈaːtɾə"),
    ("वक्र", "ʋˈʌkɾə"),
    ("चक्र", "cˈʌkɾə"),
    ("शीघ्र", "ʃˈiːɡʰɾə"),
    ("उग्र", "ˈʊɡɾə"),
    ("समग्र", "səmˈʌɡɾə"),
]

/// The same clusters with morphology continuing, which must agree with the
/// word-final forms above.
private let raConjunctsWithMorphology: [HindiWordCase] = [
    ("मित्रता", "mˈɪtɾətˌaː"),
    ("चित्रकार", "cɪtɾəkˈaːɾ"),
    ("पत्रकार", "pətɾəkˈaːɾ"),
    ("मंत्रालय", "mˈʌntɾaːləj"),
    ("यंत्रणा", "jˈʌntɾəɳˌaː"),
    ("राष्ट्रीय", "ɾaːʂʈɾˈiːj"),
    ("क्षेत्रीय", "kʃeːtɾˈiːj"),
    ("केंद्रीय", "ke\u{0303}ːdɾˈiːj"),
]

/// A rising cluster ending in य keeps the schwa. This protection predates the
/// र work and must not regress with it.
private let finalYaConjuncts: [HindiWordCase] = [
    ("मुख्य", "mˈʊkʰjə"),
    ("योग्य", "jˈoːɡjə"),
    ("वाक्य", "ʋˈaːkjə"),
    ("भाग्य", "bʰˈaːɡjə"),
    ("राज्य", "ɾˈaːɟjə"),
    ("स्वास्थ्य", "sʋˈaːstʰjə"),
    ("सौभाग्य", "sɔːbʰˈaːɡjə"),
    ("अनिवार्य", "ʌnɪʋˈaːrjə"),
    ("कार्य", "kˈaːrjə"),
    ("लक्ष्य", "lˈʌkʃjə"),
    ("सूर्य", "sˈuːrjə"),
    ("धैर्य", "dʰˈɛːrjə"),
    ("आश्चर्य", "ˈaːʃcərjə"),
    ("मध्य", "mˈʌdʰjə"),
]

/// य clusters with morphology continuing.
private let yaConjunctsWithMorphology: [HindiWordCase] = [
    ("मुख्यमंत्री", "mˈʊkʰjə mˈʌntɾi"),
    ("योग्यता", "jˈoːɡjətˌaː"),
    ("राज्यसभा", "ɾˈaːɟjə sˈʌbʰaː"),
    ("कार्यक्रम", "kˈaːrjəkɾəm"),
]

/// The rule is not specific to र and य: न, ल and म close rising clusters too.
/// These were clipped by a syllable while the rule named only the two glides.
private let finalSonorantConjuncts: [HindiWordCase] = [
    ("प्रश्न", "pɾˈʌʃnə"),
    ("यत्न", "jˈʌtnə"),
    ("रत्न", "ɾˈʌtnə"),
    ("स्वप्न", "sʋˈʌpnə"),
    ("चिह्न", "cˈɪhnə"),
    ("शुक्ल", "ʃˈʊklə"),
    ("अम्ल", "ˈʌmlə"),
    ("पद्म", "pˈʌdmə"),
    ("रश्म", "ɾˈʌʃmə"),
    ("ग्रीष्म", "ɡɾˈiːʂmə"),
]

/// Level or falling clusters take no schwa, and व takes none even when the
/// cluster rises. This half stops the rule over-applying.
private let conjunctsWithoutFinalSchwa: [HindiWordCase] = [
    ("विश्व", "ʋˈɪʃʋ"),
    ("अश्व", "ˈʌʃʋ"),
    ("तत्व", "tˈʌtʋ"),
    ("सत्व", "sˈʌtʋ"),
    ("शुल्क", "ʃˈʊlk"),
    ("जन्म", "ɟˈʌnm"),
    ("कर्म", "kˈʌrm"),
    ("धर्म", "dʰˈʌrm"),
    ("वर्म", "ʋˈʌrm"),
]

// MARK: - Tests

@Test func hindiFinalRaConjunctsKeepTheirSchwa() { checkConjuncts(finalRaConjuncts) }
@Test func hindiRaConjunctsStayConsistentUnderMorphology() { checkConjuncts(raConjunctsWithMorphology) }
@Test func hindiFinalYaConjunctsKeepTheirSchwa() { checkConjuncts(finalYaConjuncts) }
@Test func hindiYaConjunctsStayConsistentUnderMorphology() { checkConjuncts(yaConjunctsWithMorphology) }
@Test func hindiFinalSonorantConjunctsKeepTheirSchwa() { checkConjuncts(finalSonorantConjuncts) }
@Test func hindiLevelAndFallingConjunctsTakeNoSchwa() { checkConjuncts(conjunctsWithoutFinalSchwa) }

/// A suffix beginning with a consonant leaves the schwa where it was, so the
/// same cluster is read the same way in both forms. Reading मित्र one way and
/// मित्रता another would put two pronunciations of one word in a paragraph.
@Test(arguments: [
  ("मित्र", "मित्रता"),
  ("चित्र", "चित्रकार"),
  ("पत्र", "पत्रकार"),
  ("यंत्र", "यंत्रणा"),
])
func hindiConjunctKeepsItsSchwaBeforeAConsonantSuffix(bare: String, suffixed: String) {
  #expect(HindiPhonemizer.phonemize(bare).contains("tɾə"), "\(bare)")
  #expect(HindiPhonemizer.phonemize(suffixed).contains("tɾə"), "\(suffixed)")
}

/// A suffix that supplies its own vowel takes the place of the schwa rather
/// than adding to it: the र in मंत्रालय carries the ा, so there is no inherent
/// schwa left to preserve. espeak agrees — /məntɾˈaːlˌɛj/.
@Test func hindiConjunctTakesTheSuffixVowelWhenThereIsOne() {
  #expect(HindiPhonemizer.phonemize("मंत्र") == "mˈʌntɾə")
  #expect(HindiPhonemizer.phonemize("मंत्रालय") == "mˈʌntɾaːləj")
  // The cluster itself survives in both; only what follows it differs.
  #expect(HindiPhonemizer.phonemize("मंत्रालय").contains("ntɾaː"))
}

/// The whole corpus stays inside the Kokoro vocabulary.
@Test func hindiFinalConjunctsEmitOnlyKokoroVocabulary() throws {
  let vocab = try KokoroConfig.loadConfig().vocab
  let all = finalRaConjuncts + raConjunctsWithMorphology + finalYaConjuncts
    + yaConjunctsWithMorphology + finalSonorantConjuncts + conjunctsWithoutFinalSchwa

  for testCase in all {
    let unsupported = testCase.phonemes.unicodeScalars.filter { vocab[String($0)] == nil }
    #expect(unsupported.isEmpty, "\(testCase.word) -> \(testCase.phonemes)")
  }
}
