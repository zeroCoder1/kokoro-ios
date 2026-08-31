import Foundation
import Testing
@testable import KokoroSwift

// MARK: - Transcript parsing

/// Indic-TTS ships Festival-style transcripts.
@Test func transcriptParserReadsFestivalLayout() {
  let entries = TranscriptFile.parse("""
  ( hindi_f_00001 "यह एक वाक्य है" )
  ( hindi_f_00002 "राहत की चौथी उड़ान नेपाल रवाना" )
  """)

  #expect(entries.count == 2)
  #expect(entries[0].id == "hindi_f_00001")
  #expect(entries[0].text == "यह एक वाक्य है")
  #expect(entries[1].id == "hindi_f_00002")
}

@Test func transcriptParserReadsTabAndPipeLayouts() {
  #expect(TranscriptFile.parse("clip_1\tयह एक वाक्य है")[0].text == "यह एक वाक्य है")
  #expect(TranscriptFile.parse("clip_1|यह एक वाक्य है")[0].id == "clip_1")
}

@Test func transcriptParserSkipsBlanksAndComments() {
  let entries = TranscriptFile.parse("""
  # a comment

  ( clip_1 "पहला" )
  """)

  #expect(entries.count == 1)
  #expect(entries[0].id == "clip_1")
}

/// A transcript containing quotes must not truncate at the first one.
@Test func transcriptParserKeepsQuotesInsideTheText() {
  let entries = TranscriptFile.parse(#"( clip_1 "उसने कहा "ठीक है" फिर चला गया" )"#)

  #expect(entries.count == 1)
  #expect(entries[0].text.contains("ठीक है"))
}

// MARK: - Label export

private func testVocab() throws -> [String: Int] { try KokoroConfig.loadConfig().vocab }

@Test func exportedLinesUseTheStyleTTS2Layout() throws {
  let report = HindiTrainingLabels.export(
    entries: [("clip_1", "यह एक वाक्य है")],
    speaker: "hi_female",
    audioDirectory: "/data/wav",
    vocab: try testVocab()
  )

  #expect(report.labels.count == 1)
  let line = report.labels[0].manifestLine
  #expect(line.hasPrefix("/data/wav/clip_1.wav|"))
  #expect(line.hasSuffix("|hi_female"))
  #expect(line.split(separator: "|").count == 3)
}

@Test func exportNormalisesATrailingSlashOnTheAudioDirectory() throws {
  let report = HindiTrainingLabels.export(
    entries: [("clip_1", "नमस्ते")],
    speaker: "hi_male",
    audioDirectory: "/data/wav/",
    vocab: try testVocab()
  )

  #expect(report.labels[0].audioPath == "/data/wav/clip_1.wav")
}

/// Numbers have to be expanded in the labels exactly as they are at inference,
/// or the model is trained against words the digits never became.
@Test func exportExpandsNumbersTheWayInferenceDoes() throws {
  let report = HindiTrainingLabels.export(
    entries: [("clip_1", "यह 2024 में हुआ")],
    speaker: "hi_female",
    audioDirectory: "/data/wav",
    vocab: try testVocab()
  )

  #expect(report.labels.count == 1)
  #expect(report.labels[0].phonemes == HindiTrainingLabels.phonemes(for: "यह दो हज़ार चौबीस में हुआ"))
}

/// The German recipe had to remap ʏ because it has no Kokoro token. A phoneme
/// like that is dropped at tokenization, so training on it teaches the model
/// audio it cannot account for. It must be a rejection, not a warning.
@Test func exportRejectsPhonemesWithNoKokoroToken() {
  let report = HindiTrainingLabels.export(
    entries: [("clip_1", "नमस्ते")],
    speaker: "hi_female",
    audioDirectory: "/data/wav",
    vocab: ["n": 56]   // deliberately missing almost everything
  )

  #expect(report.labels.isEmpty)
  #expect(report.rejections.count == 1)
  #expect(report.rejections[0].reason == .outOfVocabulary)
  // The report names the offending code point so it can be fixed.
  #expect(report.rejections[0].detail.contains("U+"))
}

/// Punctuation phonemizes to real vocabulary tokens, so "..." is non-empty and
/// valid — and still contains no speech. It must not become a training pair.
@Test func exportRejectsEmptyAndPunctuationOnlyTranscripts() throws {
  let report = HindiTrainingLabels.export(
    entries: [("a", ""), ("b", "   "), ("c", "..."), ("d", "।"), ("e", "?!")],
    speaker: "hi_female",
    audioDirectory: "/data/wav",
    vocab: try testVocab()
  )

  #expect(report.labels.isEmpty)
  #expect(report.rejections.count == 5)
}

/// Latin text would go to Misaki at inference — a different engine with its own
/// conventions. It gets flagged for review rather than silently mixed in.
@Test func exportSetsAsideLatinScriptForReview() throws {
  let report = HindiTrainingLabels.export(
    entries: [("a", "यह WhatsApp पर है"), ("b", "यह ठीक है")],
    speaker: "hi_female",
    audioDirectory: "/data/wav",
    vocab: try testVocab()
  )

  #expect(report.labels.count == 1)
  #expect(report.rejections.count == 1)
  #expect(report.rejections[0].reason == .containsLatinScript)
}

@Test func exportRejectsClipsPastTheContextLimit() throws {
  let long = String(repeating: "यह एक बहुत लंबा वाक्य है ", count: 60)
  let report = HindiTrainingLabels.export(
    entries: [("clip_1", long)],
    speaker: "hi_female",
    audioDirectory: "/data/wav",
    vocab: try testVocab()
  )

  #expect(report.labels.isEmpty)
  #expect(report.rejections[0].reason == .tooManyTokens)
}

/// Nothing reaches the manifest that the tokenizer would not preserve intact.
@Test func everyExportedLabelSurvivesTokenization() throws {
  let vocab = try testVocab()
  let corpus = [
    "राहत की चौथी उड़ान नेपाल रवाना",
    "एनडीआरएफ की टीम ने आग्रह किया",
    "उन्होंने कहा कि मानवीय सहायता भेजी गई",
    "वाराणसी में 15 प्रतिशत की बढ़ोतरी हुई",
    "यह दुनिया की आज की खबर है",
  ]
  let report = HindiTrainingLabels.export(
    entries: corpus.enumerated().map { ("clip_\($0.offset)", $0.element) },
    speaker: "hi_female",
    audioDirectory: "/data/wav",
    vocab: vocab
  )

  #expect(report.labels.count == corpus.count)
  for label in report.labels {
    #expect(
      Tokenizer.tokenize(phonemizedText: label.phonemes).count
        == label.phonemes.unicodeScalars.count,
      "\(label.phonemes)"
    )
  }
}

@Test func theSummaryCountsWhatHappened() throws {
  let report = HindiTrainingLabels.export(
    entries: [("a", "नमस्ते"), ("b", ""), ("c", "यह WhatsApp है")],
    speaker: "hi_female",
    audioDirectory: "/data/wav",
    vocab: try testVocab()
  )

  #expect(report.summary.contains("accepted: 1"))
  #expect(report.summary.contains("rejected: 2"))
}
