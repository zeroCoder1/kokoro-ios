import Foundation
import Testing
@testable import KokoroSwift

/// Stands in for the real phoneme budget: roughly one token per character,
/// which is enough to exercise the grouping without needing the model.
private func approximateTokens(_ text: String) -> Int { text.count }

@Test func chunkerSplitsOnDevanagariDanda() {
  let sentences = SentenceChunker.sentences(in: "राहत की चौथी उड़ान नेपाल रवाना। उन्होंने कहा कि सहायता भेजी गई।")

  #expect(sentences.count == 2)
  #expect(sentences[0] == "राहत की चौथी उड़ान नेपाल रवाना।")
  #expect(sentences[1] == "उन्होंने कहा कि सहायता भेजी गई।")
}

@Test func chunkerHandlesEveryTerminator() {
  #expect(SentenceChunker.sentences(in: "एक। दो॥ तीन. चार! पाँच?").count == 5)
}

/// A terminator run and a closing quote belong to the sentence they end, not
/// to the next one.
@Test func chunkerKeepsTrailingMarksWithTheirSentence() {
  let sentences = SentenceChunker.sentences(in: #"क्या? हाँ! "ठीक है." अगला।"#)

  #expect(sentences.contains { $0.hasSuffix("?") })
  #expect(sentences.contains { $0.hasSuffix("!") })
  #expect(sentences.allSatisfy { !$0.hasPrefix("\"") || $0.hasSuffix("\"") })
}

@Test func chunkerIgnoresEmptyAndWhitespaceOnlyInput() {
  #expect(SentenceChunker.sentences(in: "").isEmpty)
  #expect(SentenceChunker.sentences(in: "   \n  ").isEmpty)
  #expect(SentenceChunker.chunks(of: "", maxTokens: 100, tokenCount: approximateTokens).isEmpty)
}

/// Short sentences ride together in one chunk rather than each becoming its own
/// synthesis call.
@Test func chunkerPacksSentencesUpToTheBudget() {
  let text = "एक दो। तीन चार। पाँच छह। सात आठ।"
  let chunks = SentenceChunker.chunks(of: text, maxTokens: 1000, tokenCount: approximateTokens)

  #expect(chunks.count == 1)
}

@Test func chunkerStartsANewChunkAtTheBudget() {
  let text = "एक दो। तीन चार। पाँच छह। सात आठ।"
  let chunks = SentenceChunker.chunks(of: text, maxTokens: 16, tokenCount: approximateTokens)

  #expect(chunks.count > 1)
  #expect(chunks.allSatisfy { approximateTokens($0) <= 16 })
}

/// A sentence too long to fit on its own is broken at phrase punctuation.
@Test func chunkerSplitsAnOverlongSentenceAtPhraseBreaks() {
  let text = "पहला भाग, दूसरा भाग, तीसरा भाग, चौथा भाग, पाँचवाँ भाग।"
  let chunks = SentenceChunker.chunks(of: text, maxTokens: 20, tokenCount: approximateTokens)

  #expect(chunks.count > 1)
  #expect(chunks.allSatisfy { approximateTokens($0) <= 20 })
}

/// Nothing may be silently dropped: every chunk together has to still contain
/// all the words that went in.
@Test(arguments: [12, 25, 60, 200])
func chunkerNeverLosesText(budget: Int) {
  let text = """
  राहत की चौथी उड़ान नेपाल रवाना। एनडीआरएफ की टीम ने आग्रह किया, \
  और मानवीय सहायता भेजी गई। उन्होंने कहा कि यह काम जारी रहेगा।
  """
  let chunks = SentenceChunker.chunks(of: text, maxTokens: budget, tokenCount: approximateTokens)

  let original = text.split(whereSeparator: \.isWhitespace).joined()
  let rebuilt = chunks.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined()
  #expect(rebuilt == original, "budget \(budget) lost or reordered text")
}

// MARK: - Segment assembly

private let sampleRate = Double(KokoroTTS.Constants.samplingRate)

@Test func segmentsAreJoinedWithTheRequestedPause() {
  let a = [Float](repeating: 0.5, count: 1000)
  let b = [Float](repeating: 0.5, count: 1000)
  let pause = 0.25

  let joined = AudioSegments.joined([a, b], pause: pause, sampleRate: sampleRate)

  #expect(joined.count == 2000 + Int(pause * sampleRate))
  // The gap really is silent.
  let gap = joined[1000 ..< 1000 + Int(pause * sampleRate)]
  #expect(gap.allSatisfy { $0 == 0 })
}

@Test func joiningIsANoOpForZeroOrOneSegment() {
  let a = [Float](repeating: 0.5, count: 10)

  #expect(AudioSegments.joined([], pause: 0.3, sampleRate: sampleRate).isEmpty)
  #expect(AudioSegments.joined([a], pause: 0.3, sampleRate: sampleRate) == a)
  // Empty segments do not earn a pause of their own.
  #expect(AudioSegments.joined([a, []], pause: 0.3, sampleRate: sampleRate) == a)
}

/// The decoder's own edge silence has to come off, or it stacks on top of the
/// caller's pause and the gap is different every time.
@Test func edgeSilenceIsTrimmedWithAGuardBand() {
  let lead = [Float](repeating: 0, count: 5000)
  let speech = [Float](repeating: 0.4, count: 2000)
  let tail = [Float](repeating: 0, count: 7000)

  let trimmed = AudioSegments.trimmingEdgeSilence(lead + speech + tail, sampleRate: sampleRate)
  let guardSamples = Int(0.01 * sampleRate)

  #expect(trimmed.count == 2000 + 2 * guardSamples)
  #expect(trimmed.contains { abs($0) > 0.3 })
}

@Test func trimmingAnEntirelySilentSegmentYieldsNothing() {
  #expect(AudioSegments.trimmingEdgeSilence([Float](repeating: 0, count: 5000),
                                            sampleRate: sampleRate).isEmpty)
}

/// Trimming must not eat the onset of the first phoneme.
@Test func trimmingKeepsSpeechThatStartsImmediately() {
  let speech = (0 ..< 2000).map { Float(sin(Double($0) * 0.05)) * 0.5 }
  let trimmed = AudioSegments.trimmingEdgeSilence(speech, sampleRate: sampleRate)

  #expect(trimmed.count == speech.count)
}
