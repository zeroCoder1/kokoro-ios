import Foundation

/// A prosodic boundary in the source. Kept structured rather than collapsed
/// to punctuation, because the daṇḍa distinction is richer than Kokoro's
/// token stream can carry and a later prosody-aware path will want it.
enum SanskritBoundary: Equatable {
  /// A space between words.
  case word
  /// `।` — a pāda or half-verse break. A moderate pause.
  case pada
  /// `॥` — the end of a verse. A stronger pause.
  case verse
  /// Sentence punctuation carried over from the source.
  case sentence(Character)
  /// `ऽ` avagraha. Silent, but a real morpheme boundary: it marks an initial
  /// अ elided after a preceding e or o, as in सोऽहम् and नरोऽपराणि. Distinct
  /// from `none` and from `word`: it neither joins the two sides seamlessly
  /// nor separates them as words.
  case elision
  /// A line break in the *source file*, which is a typographic fact and not a
  /// metrical one.
  ///
  /// A śloka is conventionally printed on two lines, but the daṇḍa is what
  /// marks the pāda — the newline merely follows it. Treating a newline as a
  /// pause would let a UI re-wrap change pronunciation, so this carries no
  /// pause and no phonological effect at all. The Sanskrit text stays
  /// authoritative.
  case displayLineBreak

  /// Whether this ends a breath group. A word boundary does not; a daṇḍa does.
  /// This is what decides whether a visarga takes its echo vowel.
  var isPause: Bool {
    switch self {
    case .pada, .verse, .sentence: return true
    case .word, .elision, .displayLineBreak: return false
    }
  }

  var slp1: String {
    switch self {
    case .word: return " "
    case .pada: return " | "
    case .verse: return " || "
    case .sentence(let character): return String(character)
    case .elision: return "'"
    case .displayLineBreak: return " "
    }
  }
}

/// One akṣara: a consonant cluster with the vowel that closes it, plus the
/// marks written on it.
struct SanskritAkshara: Equatable {
  /// The written consonant cluster, in order. `क्ष` gives `[ka, ssa]`.
  /// Empty for an independent vowel.
  var onset: [SanskritConsonant] = []
  /// The vowel, or `nil` when a virāma closed the cluster — `क्` is `k`
  /// with no vowel at all.
  var vowel: SanskritVowel?
  var anusvara = false
  var chandrabindu = false
  var visarga = false

  /// Offsets into the normalized text this akṣara was parsed from, so a
  /// source word can eventually be traced through to its Kokoro tokens.
  /// Preserved for the highlighting path described in §32 of the brief; no
  /// forced alignment is implemented yet.
  var sourceOffsets: Range<Int> = 0 ..< 0
}

enum SanskritUnit: Equatable {
  case akshara(SanskritAkshara)
  case boundary(SanskritBoundary)
}

/// Reads normalized Devanagari into akṣaras.
///
/// The parse is compositional: a consonant, then optionally a virāma binding
/// it to the next consonant, then optionally a vowel sign. Conjuncts of any
/// depth fall out of that rule, so `क्ष`, `क्त्व` and `स्त्र` need no table
/// and no glyph-level special case. This is what §14 asks for and it is what
/// both Sanskrit references do.
///
/// **The inherent vowel is always kept.** A consonant with no vowel sign and
/// no virāma carries `a`. There is no schwa deletion anywhere in this file,
/// at word end or inside a word, and there must never be: it is the single
/// point on which Sanskrit and Hindi part company.
enum SanskritAksharaParser {
  struct Result {
    var units: [SanskritUnit] = []
    var warnings: [SanskritWarning] = []
  }

  private static let independentVowels: [Unicode.Scalar: SanskritVowel] = [
    "अ": .a, "आ": .aa, "इ": .i, "ई": .ii, "उ": .u, "ऊ": .uu,
    "ऋ": .vocalicR, "ॠ": .vocalicRR, "ऌ": .vocalicL, "ॡ": .vocalicLL,
    "ए": .e, "ऐ": .ai, "ओ": .o, "औ": .au,
  ]

  private static let vowelSigns: [Unicode.Scalar: SanskritVowel] = [
    "ा": .aa, "ि": .i, "ी": .ii, "ु": .u, "ू": .uu,
    "ृ": .vocalicR, "ॄ": .vocalicRR, "ॢ": .vocalicL, "ॣ": .vocalicLL,
    "े": .e, "ै": .ai, "ो": .o, "ौ": .au,
  ]

  private static let consonants: [Unicode.Scalar: SanskritConsonant] = [
    "क": .ka, "ख": .kha, "ग": .ga, "घ": .gha, "ङ": .nga,
    "च": .ca, "छ": .cha, "ज": .ja, "झ": .jha, "ञ": .nya,
    "ट": .tta, "ठ": .ttha, "ड": .dda, "ढ": .ddha, "ण": .nna,
    "त": .ta, "थ": .tha, "द": .da, "ध": .dha, "न": .na,
    "प": .pa, "फ": .pha, "ब": .ba, "भ": .bha, "म": .ma,
    "य": .ya, "र": .ra, "ल": .la, "व": .va,
    "श": .sha, "ष": .ssa, "स": .sa, "ह": .ha,
    "ळ": .lla,
  ]

  /// Single-scalar letters outside the Classical inventory that a modern text
  /// may still carry. Mapped to their base letter so the word survives, with a
  /// warning so the substitution is visible.
  ///
  /// The nukta letters — क़ ख़ ग़ ज़ ड़ ढ़ फ़ — are deliberately absent. They are
  /// Perso-Arabic sounds borrowed into Hindi and Urdu, they do not occur in
  /// Classical Sanskrit, and Unicode gives them two spellings: a precomposed
  /// scalar and a base letter followed by U+093C. Canonical composition
  /// decomposes the precomposed form, so matching on it would catch neither
  /// reliably. The nukta is handled as a modifier in `parse` instead, which
  /// reads both spellings.
  private static let nonClassical: [Unicode.Scalar: SanskritConsonant] = [
    "ऩ": .na, "ऱ": .ra, "ऴ": .la,
  ]

  private static let virama: Unicode.Scalar = "्"
  private static let anusvara: Unicode.Scalar = "ं"
  private static let chandrabindu: Unicode.Scalar = "ँ"
  private static let visarga: Unicode.Scalar = "ः"
  private static let avagraha: Unicode.Scalar = "ऽ"
  private static let nukta: Unicode.Scalar = "़"
  private static let danda: Unicode.Scalar = "।"
  private static let doubleDanda: Unicode.Scalar = "॥"

  /// The punctuation Kokoro has tokens for. Anything else would be dropped at
  /// tokenization, taking the pause it stood for with it.
  private static let sentencePunctuation: Set<Character> = [
    ";", ":", ",", ".", "!", "?", "—", "…", "\"", "(", ")", "\u{201C}", "\u{201D}",
  ]

  static func parse(_ text: String) -> Result {
    var result = Result()
    let scalars = Array(text.unicodeScalars)
    var index = 0

    /// The akshara currently being built, if a consonant opened one.
    var pending: SanskritAkshara?
    var pendingStart = 0

    /// Unreadable characters are gathered into runs so that a Latin word
    /// reports as one warning rather than one per letter.
    var unreadable = ""

    func flushUnreadable() {
      guard !unreadable.isEmpty else { return }
      result.warnings.append(.unknownScalar("'\(unreadable)' is not Devanagari; dropped"))
      unreadable.removeAll(keepingCapacity: true)
    }

    func flush() {
      flushUnreadable()
      guard let akshara = pending else { return }
      var finished = akshara
      finished.sourceOffsets = pendingStart ..< index
      result.units.append(.akshara(finished))
      pending = nil
    }

    /// A boundary closes whatever akshara was open.
    func appendBoundary(_ boundary: SanskritBoundary) {
      flush()
      // Two spaces, or a space in front of a danda, are one boundary. The
      // stronger one wins so a pause is never weakened by the space beside it.
      if case .some(.boundary(let previous)) = result.units.last {
        if previous == .word, boundary != .word {
          result.units.removeLast()
        } else if previous == boundary || boundary == .word {
          return
        }
      }
      result.units.append(.boundary(boundary))
    }

    while index < scalars.count {
      let scalar = scalars[index]

      // A consonant opens, or continues, an akshara.
      if let consonant = consonants[scalar] ?? nonClassical[scalar] {
        if nonClassical[scalar] != nil, consonants[scalar] == nil {
          result.warnings.append(.unknownScalar(
            "\(Character(scalar)) is not Classical Sanskrit; read as \(consonant.rawValue)"
          ))
        }
        if pending == nil {
          pending = SanskritAkshara()
          pendingStart = index
        }
        pending?.onset.append(consonant)
        index += 1

        // A nukta makes this one of the Perso-Arabic letters, which are not
        // Classical Sanskrit. The base consonant is kept so the word survives,
        // and the substitution is named.
        if index < scalars.count, scalars[index] == nukta {
          result.warnings.append(.unknownScalar(
            "\(Character(scalar))\u{093C} (nukta) is not Classical Sanskrit; "
              + "read as \(consonant.rawValue)"
          ))
          index += 1
        }

        if index < scalars.count, scalars[index] == virama {
          // Bound to whatever comes next. If nothing does, the cluster ends
          // the word with no vowel, which is exactly `क्` and `भगवान्`.
          index += 1
          continue
        }

        // No virama, so this consonant takes a vowel: the sign if one is
        // written, otherwise the inherent `a`. Never deleted.
        if index < scalars.count, let sign = vowelSigns[scalars[index]] {
          pending?.vowel = sign
          index += 1
        } else {
          pending?.vowel = .a
        }
        index = readMarks(scalars, from: index, into: &pending, &result)
        flush()
        continue
      }

      if let vowel = independentVowels[scalar] {
        flush()
        pending = SanskritAkshara(vowel: vowel)
        pendingStart = index
        index = readMarks(scalars, from: index + 1, into: &pending, &result)
        flush()
        continue
      }

      // Everything below is either a boundary or something we cannot read.
      switch scalar {
      case avagraha:
        appendBoundary(.elision)
        index += 1
      case danda:
        appendBoundary(.pada)
        index += 1
      case doubleDanda:
        appendBoundary(.verse)
        index += 1
      case virama, anusvara, chandrabindu, visarga, nukta:
        // A mark with no akshara in front of it — a stranded vowel sign or a
        // doubled virama. Dropped, and named.
        result.warnings.append(.orphanedMark(String(Character(scalar))))
        index += 1
      default:
        let character = Character(scalar)
        if character.isWhitespace {
          appendBoundary(.word)
        } else if vowelSigns[scalar] != nil {
          result.warnings.append(.orphanedMark(String(character)))
        } else if sentencePunctuation.contains(character) {
          appendBoundary(.sentence(character))
        } else if !character.isNewline {
          unreadable.append(character)
        }
        index += 1
      }
    }

    flush()
    // A trailing word boundary carries no information.
    if case .some(.boundary(.word)) = result.units.last { result.units.removeLast() }
    return result
  }

  /// Reads the marks that can sit on a finished akshara. Returns the index
  /// after them.
  private static func readMarks(
    _ scalars: [Unicode.Scalar],
    from start: Int,
    into pending: inout SanskritAkshara?,
    _ result: inout Result
  ) -> Int {
    var index = start
    while index < scalars.count {
      switch scalars[index] {
      case anusvara:
        pending?.anusvara = true
      case chandrabindu:
        pending?.chandrabindu = true
      case visarga:
        pending?.visarga = true
      default:
        return index
      }
      index += 1
    }
    return index
  }
}
