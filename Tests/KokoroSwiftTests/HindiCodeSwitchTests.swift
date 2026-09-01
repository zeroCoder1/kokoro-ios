import Testing
@testable import KokoroSwift

#if canImport(MisakiSwift)

// Latin token handling: how a Latin run in Hindi copy is classified, and what
// it is read as. Classification is pure and needs nothing; the rendering tests
// stay on the native path except where a case is specifically about the Misaki
// fallback, which needs MLX and a Metal device (Tools/install-metallib.sh).

private typealias Kind = HindiG2PProcessor.LatinTokenKind

private func expectKind(_ word: String, _ kind: Kind) {
  #expect(HindiG2PProcessor.classify(word) == kind,
          "\(word): got \(HindiG2PProcessor.classify(word).rawValue)")
}

// MARK: - Category 26: acronyms spelled out

/// The commoner case in Hindi news: these are read letter by letter.
@Test(arguments: [
  "BJP", "NDRF", "RBI", "SEBI", "UPI", "GST", "GDP", "IMF", "WHO",
  "CBI", "ED", "IPL", "DRDO", "AI", "ML", "IT", "OTT",
])
func latinSpelledAcronyms(word: String) {
  expectKind(word, .spelledAcronym)
  let rendered = HindiG2PProcessor.hindiRendering(of: word)
  #expect(rendered != nil, "\(word) produced no Devanagari")
  // One name per letter, space separated so each gets its own stress.
  #expect(rendered?.split(separator: " ").count == word.count, "\(word) -> \(rendered ?? "")")
}

/// Letter names must be Devanagari, and F must keep its /f/ rather than
/// becoming the aspirated stop.
@Test func latinAcronymLetterNames() {
  #expect(HindiG2PProcessor.hindiRendering(of: "BJP") == "बी जे पी")
  #expect(HindiG2PProcessor.hindiRendering(of: "UPI") == "यू पी आई")
  #expect(HindiG2PProcessor.hindiRendering(of: "RBI") == "आर बी आई")

  let ndrf = HindiPhonemizer.phonemize(HindiG2PProcessor.hindiRendering(of: "NDRF") ?? "")
  #expect(ndrf.contains("f"), "NDRF lost its /f/: \(ndrf)")
  #expect(!ndrf.contains("pʰ"), "NDRF aspirated its F: \(ndrf)")
}

// MARK: - Category 26: acronyms said as words

/// Speakers say these as words. Spelling them out would be wrong.
@Test(arguments: [
  ("FIFA", "फीफा"), ("NATO", "नाटो"), ("ISRO", "इसरो"),
  ("AIIMS", "एम्स"), ("NASA", "नासा"), ("COVID", "कोविड"),
])
func latinSpokenAcronyms(word: String, devanagari: String) {
  expectKind(word, .spokenAcronym)
  #expect(HindiG2PProcessor.hindiRendering(of: word) == devanagari)
}

// MARK: - Category 27: alphanumeric acronyms

/// Digits take English number names, which is what speakers use: 5G is
/// "फ़ाइव जी", not "पाँच जी".
@Test(arguments: [
  ("G20", "जी ट्वेंटी"),
  ("5G", "फ़ाइव जी"),
  ("4G", "फ़ोर जी"),
  ("3G", "थ्री जी"),
  ("U19", "यू नाइनटीन"),
  ("U17", "यू सेवनटीन"),
  ("COVID-19", "कोविड नाइनटीन"),
  ("H1N1", "एच वन एन वन"),
  ("B2B", "बी टू बी"),
  ("B2C", "बी टू सी"),
  ("Web3", "वेब थ्री"),
])
func latinAlphanumerics(word: String, devanagari: String) {
  expectKind(word, .alphanumeric)
  #expect(HindiG2PProcessor.hindiRendering(of: word) == devanagari)
}

// MARK: - Category 25: Hinglish

/// Everyday English words a Hindi speaker says with Hindi phonology.
@Test(arguments: [
  "mobile", "online", "internet", "doctor", "hospital", "report",
  "update", "video", "camera", "server", "network", "digital",
  "data", "model", "final", "match", "team", "phone", "film",
])
func latinHinglish(word: String) {
  expectKind(word, .hinglish)
  #expect(HindiG2PProcessor.hindiRendering(of: word) != nil)
}

// MARK: - Category 24: English left to Misaki

/// Brand and product names with no settled Devanagari form go to the English
/// engine, which is the right default for anything not listed.
@Test(arguments: ["OpenAI", "ChatGPT", "Apple", "iPhone", "Microsoft", "Netflix", "Amazon"])
func latinEnglishNative(word: String) {
  expectKind(word, .english)
  #expect(HindiG2PProcessor.hindiRendering(of: word) == nil,
          "\(word) should fall through to Misaki")
}

/// Classification must not depend on how the word is capitalised in copy.
@Test func latinClassificationIsCaseInsensitiveForTables() {
  #expect(HindiG2PProcessor.classify("FIFA") == .spokenAcronym)
  #expect(HindiG2PProcessor.classify("Fifa") == .spokenAcronym)
  #expect(HindiG2PProcessor.classify("Mobile") == .hinglish)
  #expect(HindiG2PProcessor.classify("MOBILE") == .hinglish)
}

/// A long all-caps run is a word, not an initialism, so it is not spelled out.
@Test func latinLongUppercaseRunsAreNotAcronyms() {
  #expect(HindiG2PProcessor.classify("BREAKING") == .english)
  #expect(HindiG2PProcessor.classify("A") == .english)
}

#endif
