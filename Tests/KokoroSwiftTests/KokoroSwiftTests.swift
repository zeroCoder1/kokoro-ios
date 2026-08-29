import Testing
@testable import KokoroSwift

@Test func hindiPhonemizerUsesNaturalCommonPronunciations() {
  #expect(HindiPhonemizer.phonemize("नमस्ते") == "nəmˈʌsteː")
  #expect(HindiPhonemizer.phonemize("दुनिया") == "dˈʊnɪjˌaː")
  #expect(HindiPhonemizer.phonemize("यह") == "jˈʌh")
  #expect(HindiPhonemizer.phonemize("में") == "mˈe\u{0303}ː")
  #expect(HindiPhonemizer.phonemize("मे") == "mˈeː")
}

@Test func hindiPhonemizerDistinguishesRetroflexStopsAndNuktaFlaps() {
  let decomposed = HindiPhonemizer.phonemize("पढ़ना")
  let precomposed = HindiPhonemizer.phonemize("पढ़ना")

  #expect(decomposed == "pˈʌɽʰnaː")
  #expect(precomposed == decomposed)
  #expect(HindiPhonemizer.phonemize("ढंग") == "ɖʰˈʌŋɡ")
  #expect(HindiPhonemizer.phonemize("बढ़िया") == "bˈʌɽʰɪjˌaː")
}

@Test func hindiPhonemizerSupportsBorrowedNuktaConsonants() {
  #expect(HindiPhonemizer.phonemize("क़ानून") == "qaːnˈuːn")
  #expect(HindiPhonemizer.phonemize("ख़बर") == "xˈʌbəɾ")
  #expect(HindiPhonemizer.phonemize("ग़लत") == "ɣˈʌlət")
  #expect(HindiPhonemizer.phonemize("ज़िला") == "zˈɪlaː")
  #expect(HindiPhonemizer.phonemize("फ़ैसला") == "fˈɛːslaː")
}

@Test func hindiPhonemizerPreservesConjunctVowels() {
  #expect(HindiPhonemizer.phonemize("मुख्य") == "mˈʊkʰjə")
  #expect(HindiPhonemizer.phonemize("योग्य") == "jˈoːɡjə")
  #expect(HindiPhonemizer.phonemize("वाक्य") == "ʋˈaːkjə")
  #expect(HindiPhonemizer.phonemize("स्वतंत्रता") == "sʋətˈʌntɾətˌaː")
  #expect(HindiPhonemizer.phonemize("क्\u{200D}षेत्र") == "kʃˈeːtɾ")
}

@Test func hindiPhonemizerRespectsCommonNewsCompoundBoundaries() {
  #expect(HindiPhonemizer.phonemize("प्रधानमंत्री") == "pɾədʰˈaːn mˈʌntɾiː")
  #expect(HindiPhonemizer.phonemize("मुख्यमंत्री") == "mˈʊkʰjə mˈʌntɾiː")
  #expect(HindiPhonemizer.phonemize("राष्ट्रपति") == "ɾˈaːʂʈɾ pˈʌtɪ")
  #expect(HindiPhonemizer.phonemize("विश्वविद्यालय") == "ʋɪʃʋəʋɪdjˈaːləj")
}

@Test func hindiPhonemizerAppliesContextualHVowels() {
  #expect(HindiPhonemizer.phonemize("कहना") == "kˈɛhnaː")
  #expect(HindiPhonemizer.phonemize("रहना") == "ɾˈɛhnaː")
  #expect(HindiPhonemizer.phonemize("पहला") == "pˈɛhlaː")
  #expect(HindiPhonemizer.phonemize("बहुत") == "bˈʌhʊt")
  #expect(HindiPhonemizer.phonemize("महिला") == "mˈʌhɪlˌaː")
}

@Test func hindiPhonemizerOnlyEmitsKokoroVocabularySymbols() {
  let corpus = """
  पढ़ना ढंग क़ानून ख़बर ग़लत ज़िला फ़ैसला मुख्यमंत्री राष्ट्रपति \
  विश्वविद्यालय स्वतंत्रता श्रद्धा ज्ञान क्षेत्र हिंदी महिला कहना ॐ
  """
  let allowed = Set(" abcdefhijklmnopqrstuvxyzəɛɪʊɔɡɣŋɲɳɖɽɾʂʃʈʋʌʤʧʰˈˌː\u{0303}".unicodeScalars)
  let output = HindiPhonemizer.phonemize(corpus)
  let unsupported = Set(output.unicodeScalars).subtracting(allowed)

  #expect(unsupported.isEmpty)
}

#if canImport(MisakiSwift)
@Test func hindiG2PProcessesDevanagariWithoutExternalRuntime() throws {
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)

  let phonemes = try processor.process(input: "यह दुनिया में है.").0

  #expect(phonemes.contains("jˈʌh"))
  #expect(phonemes.contains("dˈʊnɪjˌaː"))
  #expect(phonemes.contains("mˈe\u{0303}ː"))
}

@Test func hindiG2PCanSwitchBetweenHindiAndEnglishModes() throws {
  let processor = HindiG2PProcessor()

  try processor.setLanguage(.enGB)
  try processor.setLanguage(.hi)
  let phonemes = try processor.process(input: "यह दुनिया है.").0

  #expect(phonemes.contains("jˈʌh"))
  #expect(phonemes.contains("dˈʊnɪjˌaː"))
}

@Test func hindiG2PRejectsUnsupportedLanguages() {
  let processor = HindiG2PProcessor()

  #expect(throws: G2PProcessorError.self) {
    try processor.setLanguage(.none)
  }
}
#endif
