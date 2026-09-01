import Testing
@testable import KokoroSwift

#if canImport(MisakiSwift)

// Sentence-level regression over real Hindi news copy.
//
// Asserted as properties rather than one long IPA string: a whole-sentence
// literal breaks on any unrelated change and says nothing about what went
// wrong. These check the things that actually go wrong — a phoneme with no
// token, a lost sentence break, a spurious pause, a word read on the wrong
// path — and pin the individual words that have regressed before.

private func processor() throws -> HindiG2PProcessor {
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)
  return processor
}

private let newsSentences = [
  // Government and politics
  "प्रधानमंत्री ने संसद में संविधान संशोधन पर बयान दिया।",
  "राष्ट्रपति ने नए कानून को मंजूरी दी।",
  "संयुक्त राष्ट्र सुरक्षा परिषद ने प्रस्ताव पारित किया।",
  "मुख्यमंत्री ने राज्य सरकार के अधिकारियों के साथ बैठक की।",
  "लोकसभा में विपक्ष ने सरकार से जवाब मांगा।",
  "भारत और फ्रांस के बीच नया समझौता हुआ।",
  // Breaking news
  "मुंबई में भारी बारिश के कारण कई उड़ानें रद्द हुईं।",
  "एनडीआरएफ की टीम घटनास्थल पर पहुंची।",
  "पुलिस ने मामले की जांच शुरू कर दी है।",
  "अस्पताल में घायलों का इलाज जारी है।",
  "मौसम विभाग ने अगले 24 घंटों के लिए चेतावनी जारी की।",
  // Technology
  "5G नेटवर्क का विस्तार तेजी से हो रहा है।",
  "भारत में UPI लेनदेन ने नया रिकॉर्ड बनाया।",
  "G20 सम्मेलन में digital infrastructure पर चर्चा हुई।",
  // Sport
  "भारत ने FIFA विश्व कप क्वालीफायर में जीत दर्ज की।",
  "IPL का फाइनल रविवार को खेला जाएगा।",
  "भारत की U19 टीम ने टूर्नामेंट जीता।",
  // Economy
  "भारत की GDP वृद्धि दर 7.2 प्रतिशत रही।",
  "RBI ने ब्याज दरों में कोई बदलाव नहीं किया।",
  "कंपनी ने ₹1,500 करोड़ के निवेश की घोषणा की।",
  // Nasal-heavy
  "संसद में संविधान संशोधन पर चर्चा हुई।",
  "संयुक्त राष्ट्र ने संकट पर चिंता व्यक्त की।",
  "सरकार ने संस्कृति और संरक्षण से जुड़ी नई योजना शुरू की।",
  "संस्था ने संसाधनों के बेहतर प्रबंधन पर जोर दिया।",
  "संगठन ने संबंधित विभाग से संपर्क किया।",
  // फ contrasts
  "फल और फूल बाजार में उपलब्ध हैं।",
  "फिल्म का फाइनल ट्रेलर जारी हुआ।",
  "फोन में नया फीचर जोड़ा गया।",
  "टीम सफल रही लेकिन फाइनल मैच कठिन था।",
]

/// Nothing may reach the model that it has no token for. A dropped scalar is
/// silent at runtime and shows up only as a word that sounds wrong.
@Test(arguments: newsSentences)
func newsSentencesEmitOnlyKokoroVocabulary(sentence: String) throws {
  let vocab = try KokoroConfig.loadConfig().vocab
  let phonemes = try processor().process(input: sentence).0
  let unsupported = phonemes.unicodeScalars
    .filter { vocab[String($0)] == nil }
    .map { "U+" + String($0.value, radix: 16) }

  #expect(unsupported.isEmpty, "\(sentence)\n  -> \(phonemes)\n  OOV: \(unsupported)")
}

/// Space is a token. A doubled one, or one in front of punctuation, is a pause
/// the model was never trained to produce there.
@Test(arguments: newsSentences)
func newsSentencesHaveNoSpuriousPauses(sentence: String) throws {
  let phonemes = try processor().process(input: sentence).0

  #expect(!phonemes.contains("  "), "double space: \(phonemes)")
  for mark in [".", ",", "?", "!", ";", ":"] {
    #expect(!phonemes.contains(" \(mark)"), "space before \(mark): \(phonemes)")
  }
  #expect(!phonemes.hasPrefix(" ") && !phonemes.hasSuffix(" "), "edge space: \(phonemes)")
}

/// Every one of these ends in a danda, which has no Kokoro token of its own
/// and must become the sentence break the model does know.
@Test(arguments: newsSentences)
func newsSentencesEndInASentenceBreak(sentence: String) throws {
  let phonemes = try processor().process(input: sentence).0

  #expect(phonemes.hasSuffix("."), "no sentence break: \(phonemes)")
  #expect(!phonemes.contains("।"), "danda survived: \(phonemes)")
}

/// The सं- vocabulary keeps its nasal consonant rather than collapsing to a
/// nasalized vowel. This is what the anusvara rewrite was for.
@Test func newsNasalVocabularyKeepsItsConsonant() throws {
  let phonemes = try processor().process(
    input: "संसद में संविधान संशोधन पर चर्चा हुई।"
  ).0

  #expect(phonemes.contains("sˈʌnsəd"), "संसद: \(phonemes)")
  #expect(phonemes.contains("sənʋɪdʰˈaːn"), "संविधान: \(phonemes)")
  #expect(phonemes.contains("sənʃˈoːdʰən"), "संशोधन: \(phonemes)")
}

/// The फ contrast survives inside a sentence, not just in isolation.
@Test func newsKeepsTheAspirateAndFricativeApart() throws {
  let native = try processor().process(input: "फल और फूल बाजार में उपलब्ध हैं।").0
  #expect(native.contains("pʰˈʌl"), "फल: \(native)")
  #expect(native.contains("pʰˈuːl"), "फूल: \(native)")

  let loanwords = try processor().process(input: "फिल्म का फाइनल ट्रेलर जारी हुआ।").0
  #expect(loanwords.contains("fˈɪlm"), "फिल्म: \(loanwords)")
  #expect(loanwords.contains("fˈaːɪnəl"), "फाइनल: \(loanwords)")

  // Both in one line, which is the case that actually catches a bad rule.
  let both = try processor().process(input: "टीम सफल रही लेकिन फाइनल मैच कठिन था।").0
  #expect(both.contains("sˈʌpʰəl"), "सफल kept pʰ: \(both)")
  #expect(both.contains("fˈaːɪnəl"), "फाइनल took f: \(both)")
}

/// Latin tokens land on the right path inside real copy.
@Test func newsRoutesLatinTokensCorrectly() throws {
  let acronym = try processor().process(input: "भारत में UPI लेनदेन ने रिकॉर्ड बनाया।").0
  #expect(acronym.contains("jˈu pˈi ˈaːi"), "UPI spelled out: \(acronym)")

  let spoken = try processor().process(input: "भारत ने FIFA विश्व कप जीता।").0
  #expect(spoken.contains("fˈiːfaː"), "FIFA as a word: \(spoken)")

  let alphanumeric = try processor().process(input: "5G नेटवर्क का विस्तार हुआ।").0
  #expect(alphanumeric.contains("fˈaːɪʋ ɟˈi"), "5G: \(alphanumeric)")
}

/// Amount, scale word, then currency — "पंद्रह सौ करोड़ रुपये". The currency
/// used to be emitted straight after the digits, giving "रुपये करोड़".
@Test func newsReadsCurrencyAfterTheScaleWord() throws {
  let phonemes = try processor().process(
    input: "कंपनी ने ₹1,500 करोड़ के निवेश की घोषणा की।"
  ).0
  let crore = try #require(phonemes.range(of: "kəɾˈoːɖ"))
  let rupees = try #require(phonemes.range(of: "ɾˈʊpjeː"))

  #expect(crore.lowerBound < rupees.lowerBound, "currency before scale: \(phonemes)")
}

/// Function words must not take primary stress, or a sentence reads as a list
/// of emphasised particles.
@Test func newsLeavesFunctionWordsUnstressed() throws {
  let phonemes = try processor().process(
    input: "भारत के प्रधानमंत्री ने कहा कि सरकार इस मामले पर जल्द फैसला करेगी।"
  ).0

  for particle in ["keː", "neː", "kɪ", "pəɾ"] {
    #expect(phonemes.contains(particle), "\(particle) missing from \(phonemes)")
    #expect(!phonemes.contains("ˈ" + particle), "\(particle) took stress: \(phonemes)")
  }
}

#endif
