import Foundation

/// Orthographic cleanup for Classical Sanskrit in Devanagari.
///
/// Devanagari in, Devanagari out. Nothing here knows about phonemes, SLP1 or
/// Kokoro — this layer only makes the text safe for the akshara parser to
/// read, so that the parser can assume a single spelling for each thing it
/// handles.
///
/// The whole pipeline is:
///
///     Devanagari
///       -> SanskritNormalizer      this file
///       -> SanskritAksharaParser   aksharas
///       -> SanskritPhonology       canonical Sanskrit phonemes
///       -> SanskritKokoroMapper    Kokoro IPA
///
/// Deliberately conservative. A normalizer that rewrites too much destroys
/// evidence: a wrong pronunciation should be traceable to a rule, not to
/// something that quietly vanished before any rule ran.
enum SanskritNormalizer {
  /// What normalization changed, so nothing is silently rewritten.
  struct Result {
    var text: String
    var warnings: [SanskritWarning] = []
  }

  /// `ॐ` is a single ligature scalar with no consonant or vowel parts, so an
  /// akshara parser reading it letter by letter produces nothing at all —
  /// which is exactly what EdgeSanskrit does with it. Sanskrit spells the
  /// same word ओम्, and that parses.
  private static let om: Character = "ॐ"
  private static let omExpansion = "ओम्"

  /// Zero-width joiner and non-joiner choose a glyph shape; they never change
  /// a sound. Removing them also means क्ष and क्‍ष parse identically.
  private static let joinControls: Set<Unicode.Scalar> = ["\u{200C}", "\u{200D}"]

  /// Udatta and anudatta. Vedic accent is out of scope for Classical Sanskrit
  /// (see docs/SANSKRIT.md), but the marks turn up in printed texts and must
  /// not derail the parser. Dropped, and reported.
  private static let vedicAccents: Set<Unicode.Scalar> = ["\u{0951}", "\u{0952}"]

  /// A Latin colon standing in for a visarga. Common in typed and OCR'd
  /// Sanskrit, where `रामः` is entered as `राम:`. Only rewritten when it
  /// directly follows Devanagari, so ordinary punctuation in a mixed-script
  /// line is left alone.
  private static let visarga: Character = "ः"

  static func normalize(_ text: String) -> Result {
    var warnings: [SanskritWarning] = []

    // Canonical composition first, so a vowel sign written as a decomposed
    // sequence is the same string as the composed one before anything looks
    // at it.
    var scalars = Array(text.precomposedStringWithCanonicalMapping.unicodeScalars)

    if scalars.contains(where: { vedicAccents.contains($0) }) {
      warnings.append(.vedicAccentIgnored)
    }
    scalars.removeAll { joinControls.contains($0) || vedicAccents.contains($0) }

    var output = ""
    output.reserveCapacity(scalars.count)
    var previousWasDevanagari = false

    for scalar in scalars {
      let character = Character(scalar)
      if character == om {
        output += omExpansion
        previousWasDevanagari = true
        continue
      }
      if character == ":", previousWasDevanagari {
        output.append(visarga)
        continue
      }
      output.append(character)
      previousWasDevanagari = isDevanagari(scalar)
    }

    return Result(text: collapsingWhitespace(output), warnings: warnings)
  }

  /// One space between tokens, and no leading or trailing space. Newlines
  /// inside a verse are line breaks in the printing, not pauses — the dandas
  /// carry the pauses.
  private static func collapsingWhitespace(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  static func isDevanagari(_ scalar: Unicode.Scalar) -> Bool {
    (0x0900 ... 0x097F).contains(scalar.value)
      || (0xA8E0 ... 0xA8FF).contains(scalar.value)   // Devanagari Extended
      || (0x1CD0 ... 0x1CFF).contains(scalar.value)   // Vedic Extensions
  }
}
