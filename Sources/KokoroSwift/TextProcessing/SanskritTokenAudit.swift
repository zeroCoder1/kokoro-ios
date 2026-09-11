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

  /// Longest-common-subsequence alignment of two symbol sequences.
  ///
  /// Returns one entry per aligned position: both indices for a match, only
  /// `intended` for a symbol that did not survive, only `decoded` for one that
  /// appeared. Sequences here are a phoneme string long, so the quadratic
  /// table is not worth avoiding.
  static func align(
    _ intended: [String], _ decoded: [String]
  ) -> [(intended: Int?, decoded: Int?)] {
    let n = intended.count, m = decoded.count
    var lengths = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
    for i in stride(from: n - 1, through: 0, by: -1) {
      for j in stride(from: m - 1, through: 0, by: -1) {
        lengths[i][j] = intended[i] == decoded[j]
          ? lengths[i + 1][j + 1] + 1
          : Swift.max(lengths[i + 1][j], lengths[i][j + 1])
      }
    }
    var out: [(intended: Int?, decoded: Int?)] = []
    var i = 0, j = 0
    while i < n, j < m {
      if intended[i] == decoded[j] {
        out.append((i, j)); i += 1; j += 1
      } else if lengths[i + 1][j] >= lengths[i][j + 1] {
        out.append((i, nil)); i += 1
      } else {
        out.append((nil, j)); j += 1
      }
    }
    while i < n { out.append((i, nil)); i += 1 }
    while j < m { out.append((nil, j)); j += 1 }
    return out
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

    // Aligned, not compared position by position.
    //
    // A dropped scalar shifts everything after it, so `aɭb` — where only ɭ is
    // unspellable — used to decode as `ab` and report `ɭ → b` as a
    // substitution even though b came back untouched. This report is used as
    // experiment evidence, so a spurious substitution is worse than no report.
    let alignment = align(symbols, decoded)

    var substituted: [(position: Int, intended: String, decoded: String)] = []
    var dropped: [String] = []
    var duplicated: [String] = []
    var index = 0
    while index < alignment.count {
      // Collect the run of unmatched symbols on each side, then pair them off:
      // a pair is a substitution, a leftover intended symbol is a drop, and a
      // leftover decoded symbol is an insertion.
      var onlyIntended: [(Int, String)] = []
      var onlyDecoded: [String] = []
      while index < alignment.count, alignment[index].decoded == nil,
            let i = alignment[index].intended {
        onlyIntended.append((i, symbols[i])); index += 1
      }
      while index < alignment.count, alignment[index].intended == nil,
            let j = alignment[index].decoded {
        onlyDecoded.append(decoded[j]); index += 1
      }
      if onlyIntended.isEmpty, onlyDecoded.isEmpty { index += 1; continue }
      for (offset, entry) in onlyIntended.enumerated() {
        if offset < onlyDecoded.count {
          substituted.append((entry.0, entry.1, onlyDecoded[offset]))
        } else {
          dropped.append(entry.1)
        }
      }
      if onlyDecoded.count > onlyIntended.count {
        duplicated += onlyDecoded[onlyIntended.count...]
      }
    }
    dropped.sort()
    duplicated.sort()

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
