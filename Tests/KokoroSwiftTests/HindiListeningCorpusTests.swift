import Foundation
import Testing
@testable import KokoroSwift

#if canImport(MisakiSwift)

// The listening corpus is for ears, not assertions — Tools/hindi-listening-corpus.txt
// exists so a pronunciation change can be synthesized before and after and
// compared line by line.
//
// What is checked here is only that every line still survives the pipeline:
// nothing asserts how any of it should sound.

private func listeningCorpusLines() throws -> [String] {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()      // KokoroSwiftTests
    .deletingLastPathComponent()      // Tests
    .deletingLastPathComponent()      // package root
    .appendingPathComponent("Tools/hindi-listening-corpus.txt")
  return try String(contentsOf: url, encoding: .utf8)
    .split(whereSeparator: \.isNewline)
    .map(String.init)
    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

/// Every line phonemizes to something the model has tokens for. A line that
/// silently loses a scalar would be listened to and judged without anyone
/// knowing part of it never reached the model.
@Test func listeningCorpusStaysInsideTheVocabulary() throws {
  let vocab = try KokoroConfig.loadConfig().vocab
  let processor = try HindiTestSupport.processor()
  let all = try listeningCorpusLines()
  let lines = all.filter(HindiTestSupport.avoidsMisaki)

  #expect(all.count > 40, "corpus shrank to \(all.count) lines")
  #expect(!lines.isEmpty)

  for line in lines {
    let phonemes = try processor.process(input: line).0
    #expect(!phonemes.isEmpty, "empty output for: \(line)")
    let unsupported = phonemes.unicodeScalars
      .filter { vocab[String($0)] == nil }
      .map { "U+" + String($0.value, radix: 16) }
    #expect(unsupported.isEmpty, "\(line)\n  -> \(phonemes)\n  OOV: \(unsupported)")
  }
}

/// And no line picks up a pause the model was not trained to make.
@Test func listeningCorpusHasNoSpuriousPauses() throws {
  let processor = try HindiTestSupport.processor()

  for line in try listeningCorpusLines().filter(HindiTestSupport.avoidsMisaki) {
    let phonemes = try processor.process(input: line).0
    #expect(!phonemes.contains("  "), "double space: \(line)")
    #expect(!phonemes.contains(" ."), "space before break: \(line)")
    #expect(!phonemes.contains("।"), "danda survived: \(line)")
  }
}

/// The mixed lines are checked by routing instead, since running them would
/// invoke Misaki. See HindiTestSupport.
@Test func listeningCorpusMixedLinesRouteEveryToken() throws {
  let mixed = try listeningCorpusLines().filter { !HindiTestSupport.avoidsMisaki($0) }

  #expect(!mixed.isEmpty, "expected some mixed-language lines")
  for line in mixed { HindiTestSupport.routesEveryToken(line) }
}

#endif
