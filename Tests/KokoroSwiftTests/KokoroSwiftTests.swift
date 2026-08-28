import Testing
@testable import KokoroSwift

@Test func hindiPhonemizerUsesNaturalCommonPronunciations() {
  #expect(HindiPhonemizer.phonemize("नमस्ते") == "nəmˈʌsteː")
  #expect(HindiPhonemizer.phonemize("दुनिया") == "dˈʊnɪjˌaː")
  #expect(HindiPhonemizer.phonemize("यह") == "jˈʌh")
  #expect(HindiPhonemizer.phonemize("में") == "mˈe\u{0303}ː")
  #expect(HindiPhonemizer.phonemize("मे") == "mˈeː")
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
