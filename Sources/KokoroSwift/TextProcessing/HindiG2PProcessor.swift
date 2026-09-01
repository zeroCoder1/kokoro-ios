#if canImport(MisakiSwift)

import Foundation
import MLXUtilsLibrary

/// Native bilingual front end for Kokoro. It lets one loaded TTS model switch
/// between English and Hindi.
///
/// Input is prepared, then split into script runs. `HindiNumbers` rewrites
/// digit runs as Devanagari words so they are spoken in Hindi rather than
/// American English, and symbols with no Kokoro token are dropped. Devanagari
/// runs go to the native `HindiPhonemizer`. In a Latin run, acronyms and a
/// small transliteration lexicon are rendered as Devanagari and phonemized in
/// Hindi; everything else falls back to the local Misaki engine.
final class HindiG2PProcessor: G2PProcessor {
  private var english: MisakiG2PProcessor?
  private var configuredEnglishLanguage: Language = .none
  private var activeLanguage: Language = .none

  /// Latin letter names as a Hindi speaker reads them out of an acronym, so
  /// BJP becomes बीजेपी rather than an American English spelling-out.
  private static let latinLetterNames: [Character: String] = [
    "A": "ए", "B": "बी", "C": "सी", "D": "डी", "E": "ई", "F": "एफ़",
    "G": "जी", "H": "एच", "I": "आई", "J": "जे", "K": "के", "L": "एल",
    "M": "एम", "N": "एन", "O": "ओ", "P": "पी", "Q": "क्यू", "R": "आर",
    "S": "एस", "T": "टी", "U": "यू", "V": "वी", "W": "डब्ल्यू", "X": "एक्स",
    "Y": "वाई", "Z": "ज़ेड",
  ]

  /// How a Latin run is read aloud. Hindi news mixes all of these in one
  /// sentence, and they need different treatment: NDRF is spelled out, FIFA is
  /// a word, 5G is both, mobile is said with Hindi phonology, and OpenAI is
  /// best left to the English engine.
  enum LatinTokenKind: String {
    /// An acronym speakers say as a word: FIFA, NATO, ISRO, AIIMS.
    case spokenAcronym = "SPOKEN_ACRONYM"
    /// An acronym spelled out letter by letter: BJP, NDRF, RBI, UPI.
    case spelledAcronym = "SPELLED_ACRONYM"
    /// Letters and digits together: G20, 5G, U19, COVID-19, B2B, Web3.
    case alphanumeric = "ALPHANUMERIC_ACRONYM"
    /// An everyday English word said with Hindi phonology: mobile, report.
    case hinglish = "HINGLISH"
    /// Anything else, left to the English engine: OpenAI, iPhone, Netflix.
    case english = "ENGLISH_NATIVE"
  }

  /// Acronyms pronounced as words rather than spelled out. Everything not
  /// listed here is spelled, which is the commoner case in Hindi news.
  private static let spokenAcronyms: [String: String] = [
    "fifa": "फीफा",
    "nato": "नाटो",
    "isro": "इसरो",
    "aiims": "एम्स",          // said "AIIMS" as एम्स, not A-I-I-M-S
    "nasa": "नासा",
    "unesco": "यूनेस्को",
    "unicef": "यूनिसेफ़",
    "opec": "ओपेक",
    "saarc": "सार्क",
    "brics": "ब्रिक्स",
    "covid": "कोविड",
    "aids": "एड्स",
    "sim": "सिम",
    "atm": "एटीएम",
    "web": "वेब",
  ]

  /// HINGLISH: everyday English words a Hindi speaker says with Hindi
  /// phonology. Sending these to Misaki gives a correct American rendering
  /// wedged into a Hindi sentence, which is the wrong kind of correct.
  ///
  /// Deliberately common nouns and brand names with settled Devanagari forms.
  /// Anything not here goes to Misaki, which is the right default — this is a
  /// list of exceptions, not a dictionary, and it should not grow without a
  /// word actually sounding wrong.
  private static let transliterations: [String: String] = [
    // Brands with established Hindi forms
    "whatsapp": "व्हाट्सऐप", "google": "गूगल", "facebook": "फ़ेसबुक",
    "youtube": "यूट्यूब", "twitter": "ट्विटर", "instagram": "इंस्टाग्राम",
    "android": "एंड्रॉयड",
    // Technology
    "online": "ऑनलाइन", "mobile": "मोबाइल", "internet": "इंटरनेट",
    "computer": "कंप्यूटर", "email": "ईमेल", "video": "वीडियो",
    "photo": "फ़ोटो", "app": "ऐप", "website": "वेबसाइट", "server": "सर्वर",
    "network": "नेटवर्क", "digital": "डिजिटल", "data": "डेटा",
    "camera": "कैमरा", "model": "मॉडल", "software": "सॉफ़्टवेयर",
    "platform": "प्लेटफ़ॉर्म", "feature": "फ़ीचर", "update": "अपडेट",
    // Everyday life and news
    "bank": "बैंक", "office": "ऑफ़िस", "doctor": "डॉक्टर",
    "hospital": "हॉस्पिटल", "police": "पुलिस", "train": "ट्रेन",
    "bus": "बस", "ticket": "टिकट", "market": "मार्केट", "court": "कोर्ट",
    "minister": "मिनिस्टर", "report": "रिपोर्ट",
    // Sport
    "final": "फ़ाइनल", "match": "मैच", "team": "टीम", "phone": "फ़ोन",
    "film": "फ़िल्म", "score": "स्कोर", "captain": "कैप्टन",
  ]

  /// Acronyms are spelled out at these lengths. Beyond six letters a Latin run
  /// is a word, not an initialism.
  private static let acronymLengths = 2...6

  /// Digits inside an alphanumeric term are read with their English names, as
  /// speakers do: 5G is "फाइव जी" and G20 is "जी ट्वेंटी", not "पाँच जी" or
  /// "जी बीस". `HindiNumbers` is for quantities and stays out of this.
  private static let englishNumberNames: [Int: String] = [
    0: "ज़ीरो", 1: "वन", 2: "टू", 3: "थ्री", 4: "फ़ोर", 5: "फ़ाइव",
    6: "सिक्स", 7: "सेवन", 8: "एट", 9: "नाइन", 10: "टेन",
    11: "इलेवन", 12: "ट्वेल्व", 13: "थर्टीन", 14: "फ़ोर्टीन",
    15: "फ़िफ़्टीन", 16: "सिक्सटीन", 17: "सेवनटीन", 18: "एटीन",
    19: "नाइनटीन", 20: "ट्वेंटी", 30: "थर्टी", 40: "फ़ोर्टी",
    50: "फ़िफ़्टी", 100: "हंड्रेड",
  ]

  func setLanguage(_ language: Language) throws {
    guard language == .hi || language == .enUS || language == .enGB else {
      throw G2PProcessorError.unsupportedLanguage
    }
    activeLanguage = language
  }

  func process(input: String) throws -> (String, [MToken]?) {
    guard activeLanguage != .none else {
      throw G2PProcessorError.processorNotInitialized
    }
    if activeLanguage == .enUS || activeLanguage == .enGB {
      return try processEnglish(input, language: activeLanguage)
    }

    // Numbers first, so a digit run becomes Devanagari words and joins the
    // Hindi run instead of being read out in American English. The danda is
    // normalised here rather than only inside HindiPhonemizer: it is neutral
    // to the run splitter, so it flushes straight to the output and never
    // reaches the phonemizer's own conversion. U+0964 has no Kokoro token, so
    // it was dropped at tokenization and the sentence break vanished with it.
    let prepared = droppingUnmappedSymbols(
      HindiNumbers.expand(normalizingDanda(input))
    )

    var output = ""
    var run = ""
    var neutrals = ""
    var runIsDevanagari: Bool?

    func appendRun() throws {
      guard !run.isEmpty else { return }
      let rendered: String
      if runIsDevanagari == true {
        rendered = HindiPhonemizer.phonemize(run)
      } else {
        rendered = try processLatin(run)
      }
      run.removeAll(keepingCapacity: true)
      guard !rendered.isEmpty else { return }
      if !output.isEmpty, !output.hasSuffix(" "), !rendered.hasPrefix(" ") {
        output.append(" ")
      }
      output.append(rendered)
    }

    /// Whitespace and punctuation sitting between two scripts belong to
    /// neither phonemizer, so they go straight to the output. Punctuation goes
    /// on flush against the phoneme before it: a space in front of `.` is
    /// token 16, a pause the model never saw before a sentence break.
    func flushNeutrals() {
      for character in neutrals {
        if character.isWhitespace {
          if !output.isEmpty, !output.hasSuffix(" ") { output.append(" ") }
        } else if Self.emittablePunctuation.contains(character) {
          if output.hasSuffix(" ") { output.removeLast() }
          output.append(character)
        }
      }
      neutrals.removeAll(keepingCapacity: true)
    }

    for character in prepared {
      if isNeutral(character) {
        neutrals.append(character)
        continue
      }
      let isDevanagari = character.unicodeScalars.contains {
        (0x0900...0x097F).contains($0.value)
      }
      if runIsDevanagari == isDevanagari {
        // Same script on both sides, so these neutrals are internal to the
        // run. Keeping them lets the run's own phonemizer see whole phrases.
        run += neutrals
        neutrals.removeAll(keepingCapacity: true)
      } else {
        // A script boundary. Close the run before the neutrals so they are not
        // handed to whichever phonemizer happened to run last.
        try appendRun()
        flushNeutrals()
        runIsDevanagari = isDevanagari
      }
      run.append(character)
    }
    try appendRun()
    flushNeutrals()

    // A single `replacingOccurrences(of: "  ", with: " ")` pass is not
    // idempotent: four spaces collapse to two, not one.
    let cleaned = output
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return (cleaned, nil)
  }

  /// Renders a Latin run, sending each word either to the Hindi phonemizer as
  /// Devanagari or on to Misaki. Consecutive Misaki words are handed over as
  /// one chunk so it keeps its phrase context.
  private func processLatin(_ run: String) throws -> String {
    var rendered: [String] = []
    var pendingEnglish: [String] = []

    func flushEnglish() throws {
      guard !pendingEnglish.isEmpty else { return }
      let text = pendingEnglish.joined(separator: " ")
      pendingEnglish.removeAll(keepingCapacity: true)
      let phonemes = try processEnglish(text, language: .enUS).0
      if !phonemes.isEmpty { rendered.append(phonemes) }
    }

    for token in run.split(whereSeparator: \.isWhitespace) {
      let word = String(token)
      let (leading, core, trailing) = splitOffPunctuation(word)
      guard let devanagari = Self.hindiRendering(of: core) else {
        pendingEnglish.append(word)
        continue
      }
      try flushEnglish()
      let phonemes = HindiPhonemizer.phonemize(devanagari)
      if !phonemes.isEmpty { rendered.append(leading + phonemes + trailing) }
    }
    try flushEnglish()
    return rendered.joined(separator: " ")
  }

  /// What kind of Latin token this is. Order matters: the tables are checked
  /// before the shape tests, so a listed word wins over a lucky match.
  static func classify(_ word: String) -> LatinTokenKind {
    let lowered = word.lowercased()
    if spokenAcronyms[lowered] != nil { return .spokenAcronym }
    if transliterations[lowered] != nil { return .hinglish }
    if containsDigit(word), hasLetter(word) { return .alphanumeric }
    if isSpelledAcronym(word) { return .spelledAcronym }
    return .english
  }

  /// The Devanagari a Hindi voice should say for a Latin word, or `nil` to let
  /// Misaki read it as English.
  static func hindiRendering(of word: String) -> String? {
    switch classify(word) {
    case .spokenAcronym:
      return spokenAcronyms[word.lowercased()]
    case .hinglish:
      return transliterations[word.lowercased()]
    case .spelledAcronym:
      return spelledOut(word)
    case .alphanumeric:
      return alphanumericRendering(of: word)
    case .english:
      return nil
    }
  }

  /// All capitals, all letters, and short enough to be an initialism.
  private static func isSpelledAcronym(_ word: String) -> Bool {
    acronymLengths.contains(word.count)
      && word.allSatisfy { $0.isASCII && $0.isLetter && $0.isUppercase }
  }

  /// Letter names, space separated so each gets its own stress: BJP becomes
  /// बी जे पी rather than one long run.
  private static func spelledOut(_ letters: String) -> String? {
    var names: [String] = []
    for character in letters.uppercased() {
      guard let name = latinLetterNames[character] else { return nil }
      names.append(name)
    }
    return names.isEmpty ? nil : names.joined(separator: " ")
  }

  /// Letters and digits together — G20, 5G, U19, COVID-19, B2B, Web3.
  ///
  /// The token is split into runs of letters and runs of digits, and each run
  /// is read in its own right: a listed word if there is one, otherwise letter
  /// names, and English number names for the digits. Separators inside the
  /// token, like the hyphen in COVID-19, are dropped.
  private static func alphanumericRendering(of word: String) -> String? {
    var parts: [String] = []
    var run = ""
    var runIsDigits = false

    func flush() -> Bool {
      guard !run.isEmpty else { return true }
      defer { run = "" }
      if runIsDigits {
        guard let spoken = numberName(run) else { return false }
        parts.append(spoken)
      } else {
        let lowered = run.lowercased()
        if let known = spokenAcronyms[lowered] ?? transliterations[lowered] {
          parts.append(known)
        } else if let letters = spelledOut(run) {
          parts.append(letters)
        } else {
          return false
        }
      }
      return true
    }

    for character in word {
      if character.isASCII, character.isNumber {
        if !runIsDigits, !flush() { return nil }
        runIsDigits = true
        run.append(character)
      } else if character.isASCII, character.isLetter {
        if runIsDigits, !flush() { return nil }
        runIsDigits = false
        run.append(character)
      } else {
        // A separator such as the hyphen in COVID-19 ends the run and is
        // otherwise ignored; it is not spoken.
        if !flush() { return nil }
        runIsDigits = false
      }
    }
    guard flush(), !parts.isEmpty else { return nil }
    return parts.joined(separator: " ")
  }

  /// An English number name for a digit run, falling back to digit-by-digit
  /// for anything the table does not hold. H1N1 is "एच वन एन वन"; a long run
  /// like 2024 inside a Latin token is read as its digits.
  private static func numberName(_ digits: String) -> String? {
    if let value = Int(digits), let name = englishNumberNames[value] { return name }
    let names = digits.compactMap { $0.wholeNumberValue }.compactMap { englishNumberNames[$0] }
    guard names.count == digits.count else { return nil }
    return names.joined(separator: " ")
  }

  private static func containsDigit(_ word: String) -> Bool {
    word.contains { $0.isASCII && $0.isNumber }
  }

  private static func hasLetter(_ word: String) -> Bool {
    word.contains { $0.isASCII && $0.isLetter }
  }

  private func splitOffPunctuation(
    _ word: String
  ) -> (leading: String, core: String, trailing: String) {
    var core = Substring(word)
    var leading = ""
    var trailing = ""
    while let first = core.first, first.isPunctuation {
      leading.append(first)
      core = core.dropFirst()
    }
    while let last = core.last, last.isPunctuation {
      trailing.insert(last, at: trailing.startIndex)
      core = core.dropLast()
    }
    return (leading, String(core), trailing)
  }

  /// `।` and `॥` end a Hindi sentence, and Kokoro has no token for either.
  /// `.` is the sentence break it was trained on.
  private func normalizingDanda(_ text: String) -> String {
    guard text.contains("।") || text.contains("॥") else { return text }
    return text
      .replacingOccurrences(of: "॥", with: ".")
      .replacingOccurrences(of: "।", with: ".")
  }

  /// The punctuation Kokoro has tokens for. Anything else reaching the output
  /// is dropped at tokenization anyway, and loses the break it stood for.
  private static let emittablePunctuation: Set<Character> = [
    ";", ":", ",", ".", "!", "?", "—", "…", "\"", "(", ")", "\u{201C}", "\u{201D}",
  ]

  private func isNeutral(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy {
      CharacterSet.whitespacesAndNewlines.contains($0)
        || CharacterSet.punctuationCharacters.contains($0)
    }
  }

  /// `₹`, `%`, `°` and `©` are Unicode symbols rather than punctuation, so the
  /// run splitter used to treat them as Latin and let Misaki speak them. The
  /// ones that ride on a number have already been consumed by `HindiNumbers`;
  /// anything still here has no Kokoro token, so drop it.
  private func droppingUnmappedSymbols(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: { CharacterSet.symbols.contains($0) })
    else { return text }
    return String(String.UnicodeScalarView(
      text.unicodeScalars.filter { !CharacterSet.symbols.contains($0) }
    ))
  }

#if DEBUG
  /// A per-token account of how a line was read, for diagnosing pronunciation
  /// without listening to a sample of every change.
  ///
  ///     OpenAI ने नया AI मॉडल लॉन्च किया।
  ///       OpenAI  ENGLISH_NATIVE  -> (Misaki)
  ///       ने      HINDI           -> neː
  ///       AI      SPELLED_ACRONYM -> ˈeː ˈaːi
  ///
  /// DEBUG only, and deliberately not part of the shipped API.
  func trace(_ input: String) throws -> String {
    let prepared = droppingUnmappedSymbols(HindiNumbers.expand(normalizingDanda(input)))
    var lines = ["INPUT:      \(input)"]
    if prepared != input { lines.append("NORMALIZED: \(prepared)") }
    lines.append("TOKENS:")

    for token in prepared.split(whereSeparator: \.isWhitespace) {
      let word = String(token)
      let isDevanagari = word.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
      if isDevanagari {
        lines.append("  \(word)\t HINDI\t-> \(HindiPhonemizer.phonemize(word))")
        continue
      }
      let (leading, core, trailing) = splitOffPunctuation(word)
      let kind = Self.classify(core)
      if let devanagari = Self.hindiRendering(of: core) {
        let phonemes = HindiPhonemizer.phonemize(devanagari)
        lines.append("  \(word)\t \(kind.rawValue)\t-> \(devanagari)\t\(leading)\(phonemes)\(trailing)")
      } else {
        lines.append("  \(word)\t \(kind.rawValue)\t-> (Misaki)")
      }
    }
    lines.append("FINAL:      \(try process(input: input).0)")
    return lines.joined(separator: "\n")
  }
#endif

  private func processEnglish(
    _ input: String,
    language: Language
  ) throws -> (String, [MToken]?) {
    let processor: MisakiG2PProcessor
    if let english, configuredEnglishLanguage == language {
      processor = english
    } else {
      let newProcessor = MisakiG2PProcessor()
      try newProcessor.setLanguage(language)
      english = newProcessor
      configuredEnglishLanguage = language
      processor = newProcessor
    }
    return try processor.process(input: input)
  }
}

#endif
