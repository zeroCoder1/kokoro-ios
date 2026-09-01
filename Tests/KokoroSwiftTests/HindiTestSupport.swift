import Testing
@testable import KokoroSwift

#if canImport(MisakiSwift)

// Misaki cannot be invoked under `swift test` in this package.
//
// MLX is linked into both the test binary and libMisakiSwift — the duplicate
// class warnings the runtime prints are not idle — and calling into Misaki
// crashes the process at teardown. One such test on its own is enough to turn
// a green run into exit 1.
//
// It is a packaging problem, not a Hindi one, and it predates this work. The
// response here is to test what is ours: which processor a token is routed to,
// and the phonemes for everything the Hindi path handles. What Misaki does
// with an English word is its own business and is covered by its own package.
//
// `HindiTestSupport.avoidsMisaki` filters a corpus down to the lines that stay
// on the native path; `routesEveryToken` checks the rest by classification.

enum HindiTestSupport {
  /// True when every token in the line is handled natively.
  static func avoidsMisaki(_ line: String) -> Bool {
    line.split(whereSeparator: \.isWhitespace).allSatisfy { token in
      let word = String(token)
      if word.unicodeScalars.contains(where: { (0x0900...0x097F).contains($0.value) }) {
        return true
      }
      let core = word.trimmingCharacters(in: .punctuationCharacters)
      return core.isEmpty || HindiG2PProcessor.hindiRendering(of: core) != nil
    }
  }

  /// Every token is either rendered natively or deliberately left to Misaki.
  /// Nothing is silently dropped.
  static func routesEveryToken(_ line: String) {
    for token in line.split(whereSeparator: \.isWhitespace) {
      let word = String(token)
      if word.unicodeScalars.contains(where: { (0x0900...0x097F).contains($0.value) }) {
        #expect(!HindiPhonemizer.phonemize(word).isEmpty, "\(word) phonemized to nothing")
        continue
      }
      let core = word.trimmingCharacters(in: .punctuationCharacters)
      guard !core.isEmpty else { continue }
      let kind = HindiG2PProcessor.classify(core)
      if HindiG2PProcessor.hindiRendering(of: core) == nil {
        #expect(kind == .english, "\(core) has no rendering but classifies as \(kind.rawValue)")
      } else {
        #expect(kind != .english, "\(core) renders natively but classifies as English")
      }
    }
  }

  static func processor() throws -> HindiG2PProcessor {
    let processor = HindiG2PProcessor()
    try processor.setLanguage(.hi)
    return processor
  }
}

#endif
