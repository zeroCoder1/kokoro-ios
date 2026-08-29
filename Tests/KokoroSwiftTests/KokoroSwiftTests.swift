import Testing
@testable import KokoroSwift

@Test func hindiPhonemizerUsesNaturalCommonPronunciations() {
  #expect(HindiPhonemizer.phonemize("नमस्ते") == "nəmˈʌsteː")
  #expect(HindiPhonemizer.phonemize("दुनिया") == "dˈʊnɪjˌaː")
  #expect(HindiPhonemizer.phonemize("यह") == "jˈʌh")
  #expect(HindiPhonemizer.phonemize("मैं") == "mˈɛ\u{0303}ː")
  #expect(HindiPhonemizer.phonemize("में") == "mˈe\u{0303}ː")
  #expect(HindiPhonemizer.phonemize("मे") == "mˈeː")
  #expect(HindiPhonemizer.phonemize("मुंबई") == "mˈʊmbəˌi")
  #expect(HindiPhonemizer.phonemize("मुम्बई") == "mˈʊmbəˌi")
}

@Test func hindiPhonemizerDistinguishesRetroflexStopsAndNuktaFlaps() {
  let decomposed = HindiPhonemizer.phonemize("पढ़ना")
  let precomposed = HindiPhonemizer.phonemize("पढ़ना")

  #expect(decomposed == "pˈʌɽʰənˌaː")
  #expect(precomposed == decomposed)
  #expect(HindiPhonemizer.phonemize("ढंग") == "ɖʰˈʌŋɡ")
  #expect(HindiPhonemizer.phonemize("बढ़िया") == "bˈʌɽʰɪjˌaː")
  #expect(HindiPhonemizer.phonemize("लड़का") == "lˈʌɽkaː")
}

@Test func hindiPhonemizerKeepsHindiConsonantFamiliesDistinct() {
  #expect(HindiPhonemizer.phonemize("चाय") == "cˈaːj")
  #expect(HindiPhonemizer.phonemize("छत") == "cʰˈʌt")
  #expect(HindiPhonemizer.phonemize("जल") == "ɟˈʌl")
  #expect(HindiPhonemizer.phonemize("झंडा") == "ɟʰˈʌɳɖaː")
  #expect(HindiPhonemizer.phonemize("जाना") == "ɟˈaːnaː")
  #expect(HindiPhonemizer.phonemize("ज़मीन") == "zəmˈiːn")
  #expect(HindiPhonemizer.phonemize("फल") == "pʰˈʌl")
  #expect(HindiPhonemizer.phonemize("फ़ल") == "fˈʌl")
  #expect(HindiPhonemizer.phonemize("फैसला") == "fˈɛːslaː")
  #expect(HindiPhonemizer.phonemize("फ़ैसला") == "fˈɛːslaː")
  #expect(HindiPhonemizer.phonemize("दादा") == "dˈaːdaː")
  #expect(HindiPhonemizer.phonemize("धागा") == "dʰˈaːɡaː")
}

@Test func hindiConsonantContrastsAreAllKokoroTokens() throws {
  _ = try KokoroConfig.loadConfig()
  let phonemes = HindiPhonemizer.phonemize(
    "चाय छत जल झंडा ज़मीन फैसला फ़ैसला डाक लड़का ढंग पढ़ना दादा धागा"
  )

  #expect(
    Tokenizer.tokenize(phonemizedText: phonemes).count
      == phonemes.unicodeScalars.count
  )
}

@Test func hindiNasalVowelsRemainDistinctAfterTokenization() throws {
  let config = try KokoroConfig.loadConfig()
  let main = HindiPhonemizer.phonemize("मैं")
  let mein = HindiPhonemizer.phonemize("में")
  let mainTokens = Tokenizer.tokenize(phonemizedText: main)
  let meinTokens = Tokenizer.tokenize(phonemizedText: mein)

  #expect(mainTokens.count == main.unicodeScalars.count)
  #expect(meinTokens.count == mein.unicodeScalars.count)
  #expect(mainTokens != meinTokens)
  #expect(config.vocab["ɛ"].map(mainTokens.contains) == true)
  #expect(config.vocab["e"].map(meinTokens.contains) == true)
  #expect(config.vocab["\u{0303}"].map(mainTokens.contains) == true)
  #expect(config.vocab["\u{0303}"].map(meinTokens.contains) == true)
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
  #expect(HindiPhonemizer.phonemize("प्रधानमंत्री") == "pɾədʰˈaːn mˈʌntɾi")
  #expect(HindiPhonemizer.phonemize("मुख्यमंत्री") == "mˈʊkʰjə mˈʌntɾi")
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
  let allowed = Set(". abcdefhijklmnopqrstuvxyzəɛɪʊɔɟɡɣŋɲɳɖɾɽʂʃʈʋʌʰˈˌː\u{0303}".unicodeScalars)
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
