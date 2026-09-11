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
  /// Sanskrit, where `रामः` is entered as `राम:`.
  ///
  /// Rewritten only after a scalar that can actually **bear** a visarga: a
  /// vowel, a vowel sign, or a consonant carrying its inherent a. "Follows
  /// Devanagari" was too broad — the block also holds digits, the daṇḍas, the
  /// virāma, the anusvāra and the visarga itself, none of which a visarga can
  /// follow, so `अध्याय १:`, `रामः:` and `राम।:` all gained one.
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
    // Whether a visarga could attach to whatever was last written out.
    var previousCanBearVisarga = false

    for scalar in scalars {
      let character = Character(scalar)
      if character == om {
        output += omExpansion
        // ओम् ends in a virāma, which cannot carry a visarga.
        previousCanBearVisarga = false
        continue
      }
      if character == ":" {
        if previousCanBearVisarga {
          output.append(visarga)
          // A visarga cannot follow a visarga, so the *next* colon is not a
          // typed visarga however it was written. Without this reset राम::
          // became रामःः — two visargas, two `h` tokens, and a syllable that
          // is not in the source.
          previousCanBearVisarga = false
          continue
        }
        // A colon anywhere else is not Sanskrit. It is in Kokoro's
        // vocabulary, so left alone it would reach the model as a stray
        // punctuation token with nothing said about it — the silent kind of
        // loss this pipeline reports everywhere else.
        warnings.append(.unknownScalar("':' is not a visarga here; dropped"))
        previousCanBearVisarga = false
        continue
      }
      output.append(character)
      previousCanBearVisarga = canBearVisarga(scalar)
    }

    return Result(text: collapsingWhitespace(output), warnings: warnings)
  }

  /// One space between tokens, and no leading or trailing space. Newlines
  /// inside a verse are line breaks in the printing, not pauses — the dandas
  /// carry the pauses.
  private static func collapsingWhitespace(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// Whether a visarga may follow this scalar.
  ///
  /// A visarga closes a syllable, so it attaches to that syllable's vowel:
  /// an independent vowel, a dependent vowel sign, or a consonant carrying
  /// its inherent a. Everything else in the Devanagari block is excluded by
  /// name below, because getting this wrong invents a phoneme.
  static func canBearVisarga(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    // Marks that are not vowels: inverted candrabindu, candrabindu,
    // anusvāra, and the visarga itself. Nothing may take a second one.
    case 0x0900 ... 0x0903: return false
    // Independent vowels, अ through औ, plus vocalic ॠ and ॡ.
    case 0x0904 ... 0x0914, 0x0960 ... 0x0961: return true
    // Consonants क through ह, and the nukta forms क़ through य़.
    case 0x0915 ... 0x0939, 0x0958 ... 0x095F: return true
    // Dependent vowel signs.
    case 0x093A ... 0x093B, 0x093E ... 0x094C,
         0x094E ... 0x094F, 0x0962 ... 0x0963: return true
    // Nukta and avagraha: a nukta modifies the consonant before it and an
    // avagraha marks an elision. Neither is a syllable to close.
    case 0x093C, 0x093D: return false
    // Virāma. It removes the inherent vowel, so there is nothing left to
    // carry a visarga — क् is not कः.
    case 0x094D: return false
    // ॐ, accents and other combining marks.
    case 0x0950 ... 0x0957: return false
    // Daṇḍa and double daṇḍa: punctuation, and a syllable boundary already.
    case 0x0964 ... 0x0965: return false
    // Devanagari digits.
    case 0x0966 ... 0x096F: return false
    // Additional consonants at the end of the block.
    case 0x0979 ... 0x097F: return true
    default: return false
    }
  }

  static func isDevanagari(_ scalar: Unicode.Scalar) -> Bool {
    (0x0900 ... 0x097F).contains(scalar.value)
      || (0xA8E0 ... 0xA8FF).contains(scalar.value)   // Devanagari Extended
      || (0x1CD0 ... 0x1CFF).contains(scalar.value)   // Vedic Extensions
  }
}
