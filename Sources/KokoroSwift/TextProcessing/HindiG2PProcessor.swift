#if canImport(MisakiSwift)

import Foundation
import MLXUtilsLibrary

/// Native bilingual front end for Kokoro. It lets one loaded TTS model switch
/// between English and Hindi; Devanagari uses the native Hindi phonemizer while
/// embedded Latin names and full English segments use the local Misaki engine.
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

  private static let acronymLengths = 2...6

  /// Everyday English words a Hindi voice should say in Hindi. A correct
  /// American English rendering wedged into a Hindi sentence sounds more
  /// foreign than the Devanagari form a speaker would actually use. Keys are
  /// matched case-insensitively; extend the table by adding a row.
  private static let transliterations: [String: String] = [
    "whatsapp": "व्हाट्सऐप",
    "google": "गूगल",
    "facebook": "फ़ेसबुक",
    "youtube": "यूट्यूब",
    "twitter": "ट्विटर",
    "instagram": "इंस्टाग्राम",
    "online": "ऑनलाइन",
    "mobile": "मोबाइल",
    "internet": "इंटरनेट",
    "computer": "कंप्यूटर",
    "email": "ईमेल",
    "video": "वीडियो",
    "photo": "फ़ोटो",
    "app": "ऐप",
    "website": "वेबसाइट",
    "server": "सर्वर",
    "bank": "बैंक",
    "atm": "एटीएम",
    "office": "ऑफ़िस",
    "doctor": "डॉक्टर",
    "hospital": "हॉस्पिटल",
    "police": "पुलिस",
    "train": "ट्रेन",
    "bus": "बस",
    "ticket": "टिकट",
    "market": "मार्केट",
    "court": "कोर्ट",
    "minister": "मिनिस्टर",
    "report": "रिपोर्ट",
    "update": "अपडेट",
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
    // Hindi run instead of being read out in American English.
    let prepared = droppingUnmappedSymbols(HindiNumbers.expand(input))

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
        } else {
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

  /// The Devanagari a Hindi voice should say for a Latin word, or `nil` to let
  /// Misaki read it as English.
  private static func hindiRendering(of word: String) -> String? {
    guard !word.isEmpty else { return nil }
    if let known = transliterations[word.lowercased()] { return known }
    guard acronymLengths.contains(word.count),
          word.allSatisfy({ $0.isASCII && $0.isLetter && $0.isUppercase })
    else { return nil }
    var letters = ""
    for character in word {
      guard let name = latinLetterNames[character] else { return nil }
      letters += name
    }
    return letters
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
