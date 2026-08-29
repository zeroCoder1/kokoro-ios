import Foundation
import Testing
@testable import KokoroSwift

/// Not a test so much as a dump: writes this phonemizer's output for the
/// comparison corpus so `Tools/espeak-diff.py` can diff it against espeak-ng.
/// Skipped unless KOKORO_PHONEME_DUMP names an output file.
@Test func dumpHindiPhonemesForEspeakDiff() throws {
  guard let destination = ProcessInfo.processInfo.environment["KOKORO_PHONEME_DUMP"] else { return }

  let corpus = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // KokoroSwiftTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // package root
    .appendingPathComponent("Tools/hindi-corpus.txt")

  let words = try String(contentsOf: corpus, encoding: .utf8)
    .split(whereSeparator: \.isNewline)
    .map(String.init)
    .filter { !$0.isEmpty }

  let lines = words.map { "\($0)\t\(HindiPhonemizer.phonemize($0))" }
  try lines.joined(separator: "\n").write(
    toFile: destination, atomically: true, encoding: .utf8
  )
}
