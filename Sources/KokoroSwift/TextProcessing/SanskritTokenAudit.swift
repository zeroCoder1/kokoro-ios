import Foundation

/// Round-trip verification for the last step of the pipeline.
///
/// `Tokenizer.tokenize` maps one Unicode scalar to one token and **drops an
/// unknown scalar silently** in release builds. A phoneme we cannot spell does
/// not degrade — it vanishes, taking its syllable with it, and the audio is
/// then judged in ignorance of the fact that part of the line never reached
/// the model.
///
/// This decodes the token ids back to symbols and compares them against what
/// was sent, so that class of failure is caught by a test rather than by ear:
///
///     desired  eː     tokenized as  iː      → substitution
///     desired  ḥ      tokenized as  h a     → insertion
///     desired  ɭ      tokenized as  (none)  → dropped
///
/// A development and test utility. Nothing in the synthesis path calls it.
enum SanskritTokenAudit {
  struct Report {
    /// What the mapper produced.
    let phonemes: String
    /// The phoneme string split into the units the tokenizer sees: one
    /// Unicode scalar each.
    let symbols: [String]
    let tokenIDs: [Int]
    /// Symbols recovered by looking each token id back up in the vocabulary.
    let decoded: [String]
    /// Symbols with no token at all. These are what get dropped.
    let unknown: [String]
    /// Symbols present in the input but missing from the decoded stream.
    let dropped: [String]
    /// Positions where the decoded symbol differs from the intended one.
    let substituted: [(position: Int, intended: String, decoded: String)]
    /// Symbols appearing more often after the round trip than before.
    let duplicated: [String]

    /// The property the tests assert: everything sent came back unchanged.
    var roundTrips: Bool {
      unknown.isEmpty && dropped.isEmpty && substituted.isEmpty && duplicated.isEmpty
    }

    var summary: String {
      var lines = [
        "PHONEMES   \(phonemes)",
        "SYMBOLS    \(symbols.joined(separator: " "))",
        "TOKENS     \(tokenIDs.map(String.init).joined(separator: " "))",
        "DECODED    \(decoded.joined(separator: " "))",
        "ROUND TRIP \(roundTrips ? "OK" : "FAILED")",
      ]
      if !unknown.isEmpty { lines.append("UNKNOWN    \(unknown.joined(separator: " "))") }
      if !dropped.isEmpty { lines.append("DROPPED    \(dropped.joined(separator: " "))") }
      for change in substituted {
        lines.append("SUBSTITUTED at \(change.position): \(change.intended) → \(change.decoded)")
      }
      if !duplicated.isEmpty { lines.append("DUPLICATED \(duplicated.joined(separator: " "))") }
      return lines.joined(separator: "\n")
    }
  }

  /// Vocabulary keyed by token id, for decoding. Kokoro's vocabulary is a
  /// symbol-to-id map; nothing in the package needed the inverse until now.
  static func reverseVocabulary() -> [Int: String] {
    guard let vocab = try? KokoroConfig.loadConfig().vocab else { return [:] }
    return Dictionary(vocab.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
  }

  static func audit(phonemes: String) -> Report {
    let reverse = reverseVocabulary()
    let vocab = (try? KokoroConfig.loadConfig().vocab) ?? [:]

    // The same unit the tokenizer works in. Scalars, not Characters: a
    // nasalised vowel is one grapheme cluster but two tokens, and splitting
    // by Character would hide exactly the mismatch this audit looks for.
    let symbols = phonemes.unicodeScalars.map(String.init)
    let tokenIDs = Tokenizer.tokenize(phonemizedText: phonemes)
    let decoded = tokenIDs.map { reverse[$0] ?? "<\($0)>" }
    let unknown = symbols.filter { vocab[$0] == nil }

    var substituted: [(position: Int, intended: String, decoded: String)] = []
    for index in 0 ..< min(symbols.count, decoded.count) where symbols[index] != decoded[index] {
      substituted.append((index, symbols[index], decoded[index]))
    }

    func counts(_ values: [String]) -> [String: Int] {
      values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
    let before = counts(symbols)
    let after = counts(decoded)
    let dropped = before.compactMap { symbol, count in
      after[symbol, default: 0] < count ? symbol : nil
    }.sorted()
    let duplicated = after.compactMap { symbol, count in
      count > before[symbol, default: 0] ? symbol : nil
    }.sorted()

    return Report(
      phonemes: phonemes, symbols: symbols, tokenIDs: tokenIDs, decoded: decoded,
      unknown: unknown, dropped: dropped, substituted: substituted, duplicated: duplicated
    )
  }

  /// Audits the phonemes a Sanskrit text produces, so a test can go from
  /// Devanagari to a round-trip verdict in one call.
  static func audit(text: String, options: SanskritOptions = .default) -> Report {
    audit(phonemes: SanskritPhonemizer.phonemize(text, options: options))
  }
}
