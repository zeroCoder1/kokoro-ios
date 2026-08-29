import Testing
@testable import KokoroSwift

/// A cross-section of everyday Hindi: pronouns, numerals in word form, common
/// verbs and nouns, nukta loanwords and the dotted retroflex flaps. Anything
/// the phonemizer emits for these has to be a Kokoro token, so a new mapping
/// mistake fails the build instead of being dropped silently at tokenization.
private let commonHindiWords: [String] = [
    "नमस्ते", "धन्यवाद", "कृपया", "हाँ", "नहीं", "आज", "कल", "अभी",
    "यहाँ", "वहाँ", "कहाँ", "क्यों", "कैसे", "कब", "कौन", "क्या",
    "कुछ", "सब", "बहुत", "थोड़ा", "अच्छा", "बुरा", "बड़ा", "छोटा",
    "नया", "पुराना", "लंबा", "छोटी", "तेज़", "धीमा", "पानी", "खाना",
    "रोटी", "चावल", "दूध", "चाय", "फल", "सब्ज़ी", "नमक", "चीनी",
    "घर", "कमरा", "दरवाज़ा", "खिड़की", "सड़क", "बाज़ार", "दुकान", "स्कूल",
    "अस्पताल", "मंदिर", "आदमी", "औरत", "लड़का", "लड़की", "बच्चा", "माता",
    "पिता", "भाई", "बहन", "दोस्त", "काम", "नौकरी", "पैसा", "समय",
    "दिन", "रात", "सुबह", "शाम", "हफ़्ता", "महीना", "साल", "देश",
    "भारत", "दिल्ली", "शहर", "गाँव", "राज्य", "सरकार", "नेता", "चुनाव",
    "पढ़ना", "लिखना", "बोलना", "सुनना", "देखना", "जाना", "आना", "करना",
    "होना", "देना", "लेना", "पीना", "सोना", "उठना", "बैठना", "चलना",
    "दौड़ना", "रुकना", "बढ़ना", "गढ़ना", "किताब", "कलम", "कागज़", "मेज़",
    "कुर्सी", "गाड़ी", "ट्रेन", "हवाई", "रास्ता", "पुल", "सवाल", "जवाब",
    "बात", "कहानी", "गाना", "खेल", "फ़िल्म", "ख़बर", "अख़बार", "तस्वीर",
]

/// Regression guard for the ड़ / ढ़ mapping. These used to phonemize through
/// eSpeak's ASCII mnemonics `r.` and `r.h`, so every one of them emitted a
/// mid-word `.` -- token 4, a sentence break -- in the middle of the word.
@Test(arguments: ["बड़ा", "पढ़ना", "थोड़ा", "लड़की", "सड़क", "बढ़ना", "लड़का", "बढ़िया"])
func hindiRetroflexFlapsEmitNoSentenceBreak(word: String) {
  let phonemes = HindiPhonemizer.phonemize(word)

  #expect(!phonemes.contains("."), "\(word) -> \(phonemes)")
  #expect(phonemes.contains("ɽ"), "\(word) -> \(phonemes)")
}

@Test func hindiRetroflexFlapsUseKokoroTokens() {
  #expect(HindiPhonemizer.phonemize("बड़ा") == "bˈʌɽaː")
  #expect(HindiPhonemizer.phonemize("थोड़ा") == "tʰˈoːɽaː")
  #expect(HindiPhonemizer.phonemize("पढ़ना") == "pˈʌɽʰənˌaː")
  // The nukta may be written precomposed or decomposed; both are one flap.
  #expect(HindiPhonemizer.phonemize("पढ़ना") == HindiPhonemizer.phonemize("पढ़ना"))
}

/// Schwa fronting before `h` is real in कहना, रहना and पहला, where the `h` is
/// followed by another consonant. Word-finally it is not: fronting there gave
/// आग्रह as /aːɡɾɛh/, which is heard as आगरे.
@Test func hindiSchwaFrontingSkipsWordFinalH() {
  #expect(HindiPhonemizer.phonemize("आग्रह") == "ˈaːɡɾəh")
  #expect(HindiPhonemizer.phonemize("प्रवाह") == "pɾəʋˈaːh")
  #expect(HindiPhonemizer.phonemize("उत्साह") == "ʊtsˈaːh")
  #expect(HindiPhonemizer.phonemize("निर्वाह") == "nɪɾʋˈaːh")

  // The words the rule was written for are untouched.
  #expect(HindiPhonemizer.phonemize("कहना") == "kˈɛhnaː")
  #expect(HindiPhonemizer.phonemize("रहना") == "ɾˈɛhnaː")
  #expect(HindiPhonemizer.phonemize("पहला") == "pˈɛhlaː")
  #expect(HindiPhonemizer.phonemize("बहुत") == "bˈʌhʊt")
}

/// Deleting the schwa in वाराणसी strands the ɳ in the coda, where it is heard
/// as nasalization on the vowel before it — वारांसी. The name has four
/// syllables, so the schwa is spelled out.
@Test func hindiKeepsTheSchwaInVaranasi() {
  #expect(HindiPhonemizer.phonemize("वाराणसी") == "ʋaːɾˈaːɳəsiː")
}

/// A Devanagari-spelled acronym is a sequence of letter names, not one word.
@Test func hindiDevanagariAcronymsAreReadLetterByLetter() {
  #expect(HindiPhonemizer.phonemize("एनडीआरएफ") == "ˈeːn ɖˈiː ˈaːɾ ˈeːf")
  #expect(HindiPhonemizer.phonemize("बीजेपी") == "bˈiː ɟˈeː pˈiː")
  #expect(HindiPhonemizer.phonemize("सीबीआई") == "sˈiː bˈiː ˈaːiː")
  #expect(HindiPhonemizer.phonemize("पीएम") == "pˈiː ˈeːm")
}

/// The nukta-less एफ that most copy uses was read as /pʰ/, so एनडीआरएफ ended
/// in "eph" rather than "eff".
@Test(arguments: ["एनडीआरएफ", "एसडीआरएफ", "बीएसएफ", "सीआरपीएफ", "आईएएफ"])
func hindiAcronymsEndingInEfUseTheLabiodental(acronym: String) {
  let phonemes = HindiPhonemizer.phonemize(acronym)

  #expect(phonemes.hasSuffix("ˈeːf"), "\(acronym) -> \(phonemes)")
  #expect(!phonemes.contains("pʰ"), "\(acronym) -> \(phonemes)")
}

@Test(arguments: commonHindiWords)
func hindiPhonemesAreAllKokoroVocabulary(word: String) throws {
  let vocab = try KokoroConfig.loadConfig().vocab
  let phonemes = HindiPhonemizer.phonemize(word)
  let unsupported = phonemes.unicodeScalars.filter { vocab[String($0)] == nil }

  #expect(!phonemes.isEmpty, "\(word) phonemized to nothing")
  #expect(
    unsupported.isEmpty,
    "\(word) -> \(phonemes) emits \(unsupported.map { "U+" + String($0.value, radix: 16) })"
  )
}

@Test(arguments: commonHindiWords)
func hindiPhonemesSurviveTokenization(word: String) throws {
  _ = try KokoroConfig.loadConfig()
  let phonemes = HindiPhonemizer.phonemize(word)

  #expect(
    Tokenizer.tokenize(phonemizedText: phonemes).count == phonemes.unicodeScalars.count
  )
}

/// Space is token 16. A space in front of punctuation, or a doubled space, is
/// a pause the model was never trained to produce there.
@Test(arguments: [
  "यह शब्द है.",
  "क्या यह ठीक है?",
  "रुको!",
  "पहला,  दूसरा और तीसरा.",
  "नमस्ते। धन्यवाद॥",
  "वह बड़ा शहर है, बहुत बड़ा.",
])
func hindiPhonemizerNeverSpacesBeforePunctuation(sentence: String) {
  let phonemes = HindiPhonemizer.phonemize(sentence)

  #expect(!phonemes.contains("  "), "double space in \(phonemes)")
  #expect(!phonemes.contains(" ."), "space before period in \(phonemes)")
  #expect(!phonemes.contains(" ,"), "space before comma in \(phonemes)")
  #expect(!phonemes.contains(" ?"), "space before question mark in \(phonemes)")
  #expect(!phonemes.contains(" !"), "space before exclamation in \(phonemes)")
}

#if canImport(MisakiSwift)
/// The Misaki fallback needs an MLX Metal runtime, so these all stay on the
/// native Hindi path: Devanagari, expanded numbers, acronyms and the
/// transliteration lexicon.
@Test(arguments: [
  "यह 2024 में ₹1,50,000 था.",
  "15% वृद्धि, 25° तापमान.",
  "BJP ने IPL जीता.",
  "मुझे  ATM  से  पैसे  चाहिए.",
  "१५ अगस्त को छुट्टी है!",
])
func hindiG2PNeverSpacesBeforePunctuation(sentence: String) throws {
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)

  let phonemes = try processor.process(input: sentence).0

  #expect(!phonemes.contains("  "), "double space in \(phonemes)")
  #expect(!phonemes.contains(" ."), "space before period in \(phonemes)")
  #expect(!phonemes.contains(" ,"), "space before comma in \(phonemes)")
  #expect(!phonemes.contains(" !"), "space before exclamation in \(phonemes)")
  #expect(!phonemes.hasPrefix(" "), "leading space in \(phonemes)")
  #expect(!phonemes.hasSuffix(" "), "trailing space in \(phonemes)")
}

@Test func hindiG2PReadsAcronymsAsDevanagariLetterNames() throws {
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)

  #expect(
    try processor.process(input: "BJP").0 == HindiPhonemizer.phonemize("बीजेपी")
  )
  #expect(
    try processor.process(input: "IPL").0 == HindiPhonemizer.phonemize("आईपीएल")
  )
  // Seven letters is a word, not an acronym, so it stays with Misaki.
  #expect(try processor.process(input: "यह UPI है.").0
    == HindiPhonemizer.phonemize("यह यूपीआई है."))
}

@Test func hindiG2PSpeaksCommonEnglishTermsInHindi() throws {
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)

  #expect(
    try processor.process(input: "WhatsApp").0 == HindiPhonemizer.phonemize("व्हाट्सऐप")
  )
  #expect(
    try processor.process(input: "मुझे Google पर").0
      == HindiPhonemizer.phonemize("मुझे गूगल पर")
  )
}

/// The transliteration lexicon and the acronym letter names are new
/// Devanagari sources feeding the phonemizer, so they get the same
/// vocabulary guarantee as ordinary Hindi words.
@Test(arguments: [
  "WhatsApp", "Google", "Facebook", "YouTube", "Twitter", "Instagram",
  "online", "mobile", "internet", "computer", "email", "video", "photo",
  "app", "website", "server", "bank", "ATM", "office", "doctor", "hospital",
  "police", "train", "bus", "ticket", "market", "court", "minister",
  "report", "update",
  "BJP", "IPL", "UPI", "GST", "RBI", "CBI", "NDA", "PM", "MLA", "SUV",
  "ABCDEF", "XYZ", "QW",
])
func hindiG2PLatinRenderingsAreAllKokoroVocabulary(word: String) throws {
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)
  let vocab = try KokoroConfig.loadConfig().vocab

  let phonemes = try processor.process(input: word).0
  let unsupported = phonemes.unicodeScalars.filter { vocab[String($0)] == nil }

  #expect(!phonemes.isEmpty, "\(word) phonemized to nothing")
  #expect(
    unsupported.isEmpty,
    "\(word) -> \(phonemes) emits \(unsupported.map { "U+" + String($0.value, radix: 16) })"
  )
}

@Test func hindiG2PDropsSymbolsWithNoKokoroToken() throws {
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)
  let vocab = try KokoroConfig.loadConfig().vocab

  let phonemes = try processor.process(input: "तापमान 25° © है.").0
  let unsupported = phonemes.unicodeScalars.filter { vocab[String($0)] == nil }

  #expect(unsupported.isEmpty, "\(phonemes)")
}

@Test func hindiG2PExpandsNumbersOntoTheHindiPath() throws {
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)

  #expect(
    try processor.process(input: "यह 2024 में था.").0
      == HindiPhonemizer.phonemize("यह दो हज़ार चौबीस में था.")
  )
}
#endif
