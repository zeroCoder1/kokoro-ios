import Foundation

/// Reads digit runs aloud in Hindi.
///
/// `HindiG2PProcessor` splits text into Devanagari and Latin runs, so bare
/// ASCII digits used to reach the English path and were spoken in American
/// English, while Devanagari digits ०-९ reached `HindiPhonemizer`, matched no
/// table and were dropped entirely. Rewriting numbers into Devanagari words
/// before the split puts them on the Hindi path instead.
enum HindiNumbers {
  /// 0...99 by index. Hindi has a separate word for every value below one
  /// hundred, so this range cannot be composed from smaller parts.
  private static let ones: [String] = [
    "शून्य", "एक", "दो", "तीन", "चार", "पाँच", "छह", "सात", "आठ", "नौ",
    "दस", "ग्यारह", "बारह", "तेरह", "चौदह", "पंद्रह", "सोलह", "सत्रह", "अठारह", "उन्नीस",
    "बीस", "इक्कीस", "बाईस", "तेईस", "चौबीस", "पच्चीस", "छब्बीस", "सत्ताईस", "अट्ठाईस", "उनतीस",
    "तीस", "इकतीस", "बत्तीस", "तैंतीस", "चौंतीस", "पैंतीस", "छत्तीस", "सैंतीस", "अड़तीस", "उनतालीस",
    "चालीस", "इकतालीस", "बयालीस", "तैंतालीस", "चौवालीस", "पैंतालीस", "छियालीस", "सैंतालीस", "अड़तालीस", "उनचास",
    "पचास", "इक्यावन", "बावन", "तिरेपन", "चौवन", "पचपन", "छप्पन", "सत्तावन", "अट्ठावन", "उनसठ",
    "साठ", "इकसठ", "बासठ", "तिरेसठ", "चौंसठ", "पैंसठ", "छियासठ", "सड़सठ", "अड़सठ", "उनहत्तर",
    "सत्तर", "इकहत्तर", "बहत्तर", "तिहत्तर", "चौहत्तर", "पचहत्तर", "छिहत्तर", "सतहत्तर", "अठहत्तर", "उन्यासी",
    "अस्सी", "इक्यासी", "बयासी", "तिरासी", "चौरासी", "पचासी", "छियासी", "सत्तासी", "अट्ठासी", "नवासी",
    "नब्बे", "इक्यानवे", "बानवे", "तिरानवे", "चौरानवे", "पंचानवे", "छियानवे", "सत्तानवे", "अट्ठानवे", "निन्यानवे",
  ]

  /// Indian grouping: hundred, thousand, hundred-thousand, ten-million. There
  /// is deliberately no million or billion step.
  private static let scales: [(value: Int, name: String)] = [
    (10_000_000, "करोड़"),
    (100_000, "लाख"),
    (1_000, "हज़ार"),
  ]

  private static let hundred = "सौ"
  private static let decimalPoint = "दशमलव"
  private static let percentName = "प्रतिशत"
  private static let percentSign: Character = "%"

  /// Currency marks are read after the amount and stripped from the text, so
  /// they never reach a phonemizer that has no token for them.
  private static let currencyNames: [Character: String] = [
    "₹": "रुपये",
    "$": "डॉलर",
  ]

  /// Beyond this a digit run is an identifier rather than a quantity: a
  /// ten-digit run is an Indian mobile number, not a count. Nine digits is
  /// also the largest value the करोड़-headed scale list states without an
  /// अरब term.
  private static let maxCardinalDigits = 9

  /// Rewrites every digit run in `text` as Devanagari words, leaving the rest
  /// of the string untouched.
  static func expand(_ text: String) -> String {
    let characters = Array(stripGroupingCommas(normalizingDevanagariDigits(text)))
    var output = ""
    var index = 0

    while index < characters.count {
      // Digits welded to Latin letters are part of a term, not a quantity: the
      // 20 in G20, the 5 in 5G, the 19 in COVID-19. HindiG2PProcessor reads
      // those with English number names — "जी ट्वेंटी", "फ़ाइव जी" — so the
      // whole run is copied through untouched. Skipping only the first digit
      // would leave the rest to be read as a quantity: G20 became "G2 शून्य".
      if isDigit(characters[index]),
         isBoundToLatinLetter(characters, digitsBeginningAt: index) {
        while index < characters.count, isDigit(characters[index]) {
          output.append(characters[index])
          index += 1
        }
        continue
      }
      guard let match = number(in: characters, at: index) else {
        output.append(characters[index])
        index += 1
        continue
      }
      output.append(match.words)
      index = match.end
    }
    return output
  }

  // MARK: - Scanning

  /// Reads one number starting at `start`, including any currency mark in
  /// front of it and any percent sign behind it.
  private static func number(
    in characters: [Character],
    at start: Int
  ) -> (words: String, end: Int)? {
    var index = start
    var trailingWords: [String] = []

    // A currency mark only counts when it is actually attached to digits.
    if let currency = currencyNames[characters[index]] {
      guard index + 1 < characters.count, isDigit(characters[index + 1]) else {
        return nil
      }
      trailingWords.append(currency)
      index += 1
    }
    guard index < characters.count, isDigit(characters[index]) else { return nil }

    var groups = [digits(in: characters, from: &index)]
    var fraction: String?
    var clockMinutes: String?
    var isGrouped = false

    if index + 1 < characters.count,
       characters[index] == ".",
       isDigit(characters[index + 1]) {
      // Only a `.` with digits on both sides is a decimal point; a `.` that
      // ends a sentence stays a sentence break.
      index += 1
      fraction = digits(in: characters, from: &index)
    } else if index + 1 < characters.count,
              characters[index] == ":",
              isDigit(characters[index + 1]) {
      // A clock time. The colon is a Kokoro token, so leaving it in puts a
      // pause in the middle of "7:30". Read the parts as numbers instead:
      // "सात तीस", with the बजे that follows in the copy doing the rest.
      index += 1
      clockMinutes = digits(in: characters, from: &index)
    } else {
      // `98765-43210` is a phone number, not two quantities.
      while index + 1 < characters.count,
            characters[index] == "-",
            isDigit(characters[index + 1]) {
        index += 1
        groups.append(digits(in: characters, from: &index))
        isGrouped = true
      }
    }

    if index < characters.count, characters[index] == percentSign {
      trailingWords.append(percentName)
      index += 1
    }

    // A scale word written after the digits belongs between the amount and the
    // currency: "₹1,500 करोड़" is पंद्रह सौ करोड़ रुपये, not पंद्रह सौ रुपये
    // करोड़. Consume it here so it lands in the right place.
    var scaleWord: String?
    if !trailingWords.isEmpty, let found = writtenScale(in: characters, at: index) {
      scaleWord = found.word
      index = found.end
    }

    var words: [String]
    if isGrouped {
      words = groups.map(spelledOut)
    } else if let fraction {
      words = [read(groups[0]), decimalPoint, spelledOut(fraction)]
    } else if let clockMinutes {
      words = [read(groups[0]), read(clockMinutes)]
    } else {
      words = [read(groups[0])]
    }
    if let scaleWord { words.append(scaleWord) }
    words.append(contentsOf: trailingWords)
    return (words.joined(separator: " "), index)
  }

  /// Scale words that may follow the digits in ordinary copy, longest first so
  /// a longer one is not cut short by a shorter prefix.
  private static let writtenScales = [
    "करोड़", "करोड़",
    "लाख",
    "हज़ार", "हज़ार",
    "अरब",
  ]

  /// Matches a written scale word at `index`, skipping the space before it.
  private static func writtenScale(
    in characters: [Character], at index: Int
  ) -> (word: String, end: Int)? {
    var start = index
    while start < characters.count, characters[start] == " " { start += 1 }
    guard start > index || start < characters.count else { return nil }
    for scale in writtenScales {
      let scalars = Array(scale.unicodeScalars)
      let tail = Array(String(characters[start...]).unicodeScalars)
      guard tail.count >= scalars.count,
            Array(tail[0 ..< scalars.count]) == scalars
      else { continue }
      return (scale, start + scale.count)
    }
    return nil
  }

  private static func digits(
    in characters: [Character],
    from index: inout Int
  ) -> String {
    var run = ""
    while index < characters.count, isDigit(characters[index]) {
      run.append(characters[index])
      index += 1
    }
    return run
  }

  // MARK: - Rendering

  private static func read(_ run: String) -> String {
    if readsAsDigits(run) { return spelledOut(run) }
    guard let value = Int(run) else { return spelledOut(run) }
    return cardinal(value)
  }

  /// Long runs, and runs padded with leading zeros, are identifiers, and an
  /// identifier is read one digit at a time.
  private static func readsAsDigits(_ run: String) -> Bool {
    run.count > maxCardinalDigits || (run.count > 1 && run.hasPrefix("0"))
  }

  private static func spelledOut(_ run: String) -> String {
    run.compactMap(\.wholeNumberValue).map { ones[$0] }.joined(separator: " ")
  }

  private static func cardinal(_ value: Int) -> String {
    // Hindi reads this band as hundreds — उन्नीस सौ सैंतालीस, पंद्रह सौ — for
    // years and for plain quantities alike. It applies to the number as a
    // whole, not to a remainder inside a larger one.
    guard (1100...1999).contains(value) else { return composed(value) }
    return joinedHundreds(hundreds: value / 100, rest: value % 100)
  }

  private static func composed(_ value: Int) -> String {
    if value < 100 { return ones[value] }
    if value < 1000 {
      return joinedHundreds(hundreds: value / 100, rest: value % 100)
    }
    for scale in scales where value >= scale.value {
      // The quotient always lands below 100 here, and a quotient of 1 supplies
      // the एक that Hindi requires in front of a scale word.
      let head = composed(value / scale.value) + " " + scale.name
      let rest = value % scale.value
      return rest == 0 ? head : head + " " + composed(rest)
    }
    return ones[0]
  }

  private static func joinedHundreds(hundreds: Int, rest: Int) -> String {
    let head = ones[hundreds] + " " + hundred
    return rest == 0 ? head : head + " " + composed(rest)
  }

  // MARK: - Normalisation

  private static func normalizingDevanagariDigits(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: { (0x0966...0x096F).contains($0.value) })
    else { return text }
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      if (0x0966...0x096F).contains(scalar.value) {
        scalars.append(UnicodeScalar(scalar.value - 0x0966 + 0x30)!)
      } else {
        scalars.append(scalar)
      }
    }
    return String(scalars)
  }

  /// `1,50,000` and `1,500,000` are both one number. A comma without digits on
  /// both sides is ordinary punctuation and survives.
  private static func stripGroupingCommas(_ text: String) -> String {
    guard text.contains(",") else { return text }
    let characters = Array(text)
    var result = ""
    for (offset, character) in characters.enumerated() {
      let isGroupingComma = character == ","
        && offset > 0 && isDigit(characters[offset - 1])
        && offset + 1 < characters.count && isDigit(characters[offset + 1])
      if !isGroupingComma { result.append(character) }
    }
    return result
  }

  /// Whether the digit run starting at `index` touches ASCII letters on either
  /// side, directly or across a single joining hyphen as in COVID-19.
  private static func isBoundToLatinLetter(
    _ characters: [Character], digitsBeginningAt index: Int
  ) -> Bool {
    func isLetter(_ offset: Int) -> Bool {
      characters.indices.contains(offset)
        && characters[offset].isASCII && characters[offset].isLetter
    }
    if isLetter(index - 1) { return true }
    if characters.indices.contains(index - 1), characters[index - 1] == "-",
       isLetter(index - 2) { return true }

    var after = index
    while after < characters.count, isDigit(characters[after]) { after += 1 }
    return isLetter(after)
  }

  private static func isDigit(_ character: Character) -> Bool {
    character.isASCII && character.isNumber
  }
}
