import Testing
@testable import KokoroSwift

#if canImport(MisakiSwift)

// Paragraph-level regression.
//
// Checks that a multi-sentence passage survives the pipeline intact: every
// token reaches a processor, nothing disappears, each sentence keeps its
// break, and the words known to have regressed before still come out right.
// Whole-paragraph IPA literals are deliberately avoided — they break on any
// change and say nothing about what broke.

private struct Paragraph {
  let name: String
  let sentences: [String]
  /// Words that must appear in the output, with the phonemes they must have.
  let anchors: [String]
}

private let paragraphs = [
  Paragraph(
    name: "government",
    sentences: [
      "प्रधानमंत्री ने आज संसद में संविधान संशोधन पर बयान दिया।",
      "उन्होंने कहा कि केंद्र सरकार इस मुद्दे पर सभी राज्यों से चर्चा करेगी।",
      "संयुक्त राष्ट्र की एक रिपोर्ट का भी बैठक में उल्लेख किया गया।",
    ],
    anchors: ["sˈʌnsəd", "sənʋɪdʰˈaːn", "kˈẽːdɾə", "sˈʌɲjʊkt", "ɾˈaːʂʈɾə"]
  ),
  Paragraph(
    name: "technology",
    sentences: [
      "OpenAI ने आज अपना नया AI मॉडल पेश किया।",
      "कंपनी के अनुसार नया मॉडल mobile और server दोनों platform पर काम कर सकता है।",
      "इस बीच Google और Microsoft ने भी अपने AI products के नए update जारी किए हैं।",
    ],
    anchors: ["ˈeː ˈaːi", "moːbˈaːɪl", "sˈʌɾʋəɾ"]
  ),
  Paragraph(
    name: "sports",
    sentences: [
      "भारत ने FIFA विश्व कप क्वालीफायर में शानदार जीत दर्ज की।",
      "टीम का अगला match रविवार को खेला जाएगा।",
      "इस बीच U19 टीम ने भी tournament के final में जगह बना ली है।",
    ],
    anchors: ["fˈiːfaː", "ʋˈɪʃʋ", "jˈu naːɪnʈˈiːn", "fˈaːɪnəl"]
  ),
  Paragraph(
    name: "economy",
    sentences: [
      "RBI ने आज ब्याज दरों में कोई बदलाव नहीं किया।",
      "भारत की GDP वृद्धि दर 7.2 प्रतिशत रहने का अनुमान है।",
      "शेयर बाजार ने घोषणा के बाद सकारात्मक प्रतिक्रिया दी।",
    ],
    anchors: ["ˈaːɾ bˈi ˈaːi", "ɟˈi ɖˈi pˈi", "sˈaːt dəʃˈʌmləʋ dˈoː"]
  ),
]

private func processor() throws -> HindiG2PProcessor {
  let processor = HindiG2PProcessor()
  try processor.setLanguage(.hi)
  return processor
}

/// Whether a line contains a token that would be handed to Misaki.
///
/// Those lines are checked by classification rather than by running them.
/// MLX is linked into both the test binary and libMisakiSwift, and the
/// duplicate-class warning that produces is not idle — invoking Misaki under
/// `swift test` crashes the process. What Misaki does with a word is its own
/// business anyway; what matters here is that the word reaches it.
private func needsMisaki(_ sentence: String) -> Bool {
  sentence.split(whereSeparator: \.isWhitespace).contains { token in
    let word = String(token)
    let isDevanagari = word.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
    guard !isDevanagari else { return false }
    let core = word.trimmingCharacters(in: .punctuationCharacters)
    return !core.isEmpty && HindiG2PProcessor.hindiRendering(of: core) == nil
  }
}

private let nativeSentences = paragraphs.flatMap(\.sentences).filter { !needsMisaki($0) }

/// Every native sentence produces phonemes the model has tokens for.
@Test(arguments: nativeSentences)
func paragraphSentencesStayInsideTheVocabulary(sentence: String) throws {
  let vocab = try KokoroConfig.loadConfig().vocab
  let phonemes = try processor().process(input: sentence).0
  let unsupported = phonemes.unicodeScalars
    .filter { vocab[String($0)] == nil }
    .map { "U+" + String($0.value, radix: 16) }

  #expect(!phonemes.isEmpty, "\(sentence)")
  #expect(unsupported.isEmpty, "\(sentence)\n  -> \(phonemes)\n  OOV: \(unsupported)")
}

/// Nothing vanishes between the text and the phonemes. Counted loosely: a
/// Devanagari acronym legitimately becomes several words, but no token may
/// disappear altogether.
@Test(arguments: nativeSentences)
func paragraphSentencesLoseNoTokens(sentence: String) throws {
  let words = sentence.split(whereSeparator: \.isWhitespace).count
  let phonemes = try processor().process(input: sentence).0
  let produced = phonemes.split(whereSeparator: \.isWhitespace).count

  #expect(produced >= words - 1, "\(words) words in, \(produced) out: \(phonemes)")
}

/// Each sentence keeps its own break, so a paragraph is not read as a run-on.
@Test(arguments: ["government"])
func paragraphsKeepASentenceBreakPerSentence(name: String) throws {
  let paragraph = try #require(paragraphs.first { $0.name == name })
  let phonemes = try processor().process(
    input: paragraph.sentences.joined(separator: " ")
  ).0

  #expect(phonemes.filter { $0 == "." }.count == paragraph.sentences.count,
          "\(name): \(phonemes)")
}

/// Words that have regressed before still come out right inside a paragraph,
/// which is where they are actually read.
@Test(arguments: ["government"])
func paragraphAnchorsSurvive(name: String) throws {
  let paragraph = try #require(paragraphs.first { $0.name == name })
  let phonemes = try processor().process(
    input: paragraph.sentences.joined(separator: " ")
  ).0

  for anchor in paragraph.anchors {
    #expect(phonemes.contains(anchor), "\(name): \(anchor) missing from\n  \(phonemes)")
  }
}

/// For the mixed paragraphs, what matters is that each token is routed to the
/// right processor. That is checked without running either of them.
@Test(arguments: paragraphs.flatMap(\.sentences).filter(needsMisaki))
func mixedParagraphsRouteEveryTokenSomewhere(sentence: String) {
  for token in sentence.split(whereSeparator: \.isWhitespace) {
    let word = String(token)
    let isDevanagari = word.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
    if isDevanagari {
      #expect(!HindiPhonemizer.phonemize(word).isEmpty, "\(word) phonemized to nothing")
      continue
    }
    let core = word.trimmingCharacters(in: .punctuationCharacters)
    guard !core.isEmpty else { continue }
    // Either we render it natively, or it is deliberately English. Both are
    // routed; neither is dropped.
    let kind = HindiG2PProcessor.classify(core)
    if HindiG2PProcessor.hindiRendering(of: core) == nil {
      #expect(kind == .english, "\(core) has no rendering but is \(kind.rawValue)")
    } else {
      #expect(kind != .english, "\(core) renders natively but classifies as English")
    }
  }
}

/// The Latin tokens in the mixed paragraphs land where they should.
@Test func mixedParagraphTokensClassifyCorrectly() {
  #expect(HindiG2PProcessor.classify("OpenAI") == .english)
  #expect(HindiG2PProcessor.classify("Microsoft") == .english)
  #expect(HindiG2PProcessor.classify("AI") == .spelledAcronym)
  #expect(HindiG2PProcessor.classify("RBI") == .spelledAcronym)
  #expect(HindiG2PProcessor.classify("GDP") == .spelledAcronym)
  #expect(HindiG2PProcessor.classify("FIFA") == .spokenAcronym)
  #expect(HindiG2PProcessor.classify("U19") == .alphanumeric)
  #expect(HindiG2PProcessor.classify("mobile") == .hinglish)
  #expect(HindiG2PProcessor.classify("server") == .hinglish)
}

#endif
