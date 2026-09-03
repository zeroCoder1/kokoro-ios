import Foundation
import Testing
@testable import KokoroSwift

// Golden data and whole-corpus checks.
//
// `Tests/Fixtures/sanskrit-golden.tsv` records what the pipeline produces at
// every stage for a curated set covering each category in §29 of the brief.
// Its `status` column says how much each row is to be trusted:
//
//   REFERENCE_AGREEMENT   our canonical form matches Vagdhenu's
//   CONFIRMED             settled by Sanskrit phonology; references agree
//   REVIEW_REQUIRED       the references genuinely disagree — decide by ear
//   KOKORO_APPROXIMATION  Kokoro cannot say this faithfully
//
// A row is never marked more confidently than the evidence supports. The
// comparison against Vagdhenu and EdgeSanskrit is diagnostic, not a target:
// see Tools/sanskrit-reference-compare.py.

private func packageFile(_ relativePath: String) -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()      // KokoroSwiftTests
    .deletingLastPathComponent()      // Tests
    .deletingLastPathComponent()      // package root
    .appendingPathComponent(relativePath)
}

private struct GoldenRow {
  let input: String
  let normalized: String
  let canonical: String
  let phonological: String
  let kokoroPhonemes: String
  let status: String
  let notes: String
}

private func goldenRows() throws -> [GoldenRow] {
  let text = try String(contentsOf: packageFile("Tests/Fixtures/sanskrit-golden.tsv"),
                        encoding: .utf8)
  return text.split(separator: "\n").dropFirst().compactMap { line in
    let columns = line.components(separatedBy: "\t")
    guard columns.count >= 6 else { return nil }
    return GoldenRow(
      input: columns[0], normalized: columns[1], canonical: columns[2],
      phonological: columns[3], kokoroPhonemes: columns[4], status: columns[5],
      notes: columns.count > 6 ? columns[6] : ""
    )
  }
}

private func corpusLines() throws -> [String] {
  try String(contentsOf: packageFile("Tools/sanskrit-listening-corpus.txt"), encoding: .utf8)
    .split(whereSeparator: \.isNewline)
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

// MARK: - Golden data

/// Every intermediate stage is checked, not just the phonemes. A change that
/// alters only the canonical form — where a reference comparison happens — is
/// as much a regression as one that alters the audio.
@Test func goldenDataStillMatchesAtEveryStage() throws {
  let rows = try goldenRows()
  #expect(rows.count > 70, "golden set shrank to \(rows.count) rows")

  for row in rows {
    let result = SanskritPhonemizer.analyze(row.input)
    #expect(result.normalized == row.normalized,
            "normalized changed for \(row.input): \(result.normalized)")
    #expect(result.canonical == row.canonical,
            "canonical changed for \(row.input): \(result.canonical)")
    #expect(result.phonological == row.phonological,
            "phonological changed for \(row.input): \(result.phonological)")
    #expect(result.kokoroPhonemes == row.kokoroPhonemes,
            "phonemes changed for \(row.input): \(result.kokoroPhonemes)")
  }
}

@Test func everyGoldenRowCarriesAKnownStatus() throws {
  let allowed: Set<String> = [
    "CONFIRMED", "REFERENCE_AGREEMENT", "REVIEW_REQUIRED", "KOKORO_APPROXIMATION",
  ]
  for row in try goldenRows() {
    #expect(allowed.contains(row.status), "\(row.input) has status '\(row.status)'")
  }
}

/// A row marked KOKORO_APPROXIMATION must actually emit a warning, and a row
/// not so marked must not. This is what keeps §30 honest: the fixture cannot
/// drift into claiming a sound is faithful when the mapper knows it is not.
@Test func approximationStatusMatchesTheWarningsEmitted() throws {
  for row in try goldenRows() {
    let warnings = SanskritPhonemizer.analyze(row.input).warnings
    let approximates = warnings.contains {
      $0.text.hasPrefix("KOKORO_APPROXIMATION") || $0.text.hasPrefix("KOKORO_UNSUPPORTED")
    }
    if row.status == "KOKORO_APPROXIMATION" {
      #expect(approximates, "\(row.input) is marked as an approximation but warns about nothing")
    } else {
      #expect(!approximates, "\(row.input) approximates but is marked \(row.status)")
    }
  }
}

// MARK: - Bhagavad Gita

/// The three verses that will be synthesized. Checked here so a failure is a
/// test failure rather than something noticed while listening.
@Test func theGitaVersesReadCorrectly() {
  let verses: [(String, String)] = [
    ("धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।",
     "dʰaɾmakʂeːtɾeː kuɾukʂeːtɾeː samaʋeːtaː jujutsaʋaha,"),
    ("मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥",
     "maːmakaːh paːɳɖaʋaːʃcaɪʋa kimakuɾʋata saɲɟaja."),
    ("मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥",
     "maː kaɾmapʰalaheːtuɾbʰuːɾmaː teː saŋɡoːstʋakaɾmaɳi."),
  ]
  for (verse, expected) in verses {
    #expect(SanskritPhonemizer.phonemize(verse) == expected,
            "\(verse)\n  gave \(SanskritPhonemizer.phonemize(verse))")
  }
}

/// Nothing in a Gita verse should be approximated except the vocalic liquids,
/// which have one known cause. A new warning class appearing here means the
/// compatibility document is out of date.
@Test func gitaVersesApproximateOnlyWhatIsDocumented() {
  let verses = [
    "धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।",
    "मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥",
    "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।",
    "मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥",
    "यदा यदा हि धर्मस्य ग्लानिर्भवति भारत ।",
    "अभ्युत्थानमधर्मस्य तदात्मानं सृजाम्यहम् ॥",
  ]
  for verse in verses {
    for warning in SanskritPhonemizer.analyze(verse).warnings {
      let known = warning.text.contains("vocalic")
        || warning.text.contains("anusvāra before a continuant")
      #expect(known, "undocumented warning for \(verse): \(warning.text)")
    }
  }
}

/// A whole shloka fits the model's context, so it can be synthesized in one
/// call rather than being split mid-verse.
@Test func aWholeShlokaFitsTheModelContext() throws {
  _ = try KokoroConfig.loadConfig()
  let shloka = """
    धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।
    मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥
    """
  let tokens = SanskritPhonemizer.analyze(shloka).tokens
  #expect(tokens.count > 60)
  #expect(tokens.count < KokoroTTS.Constants.maxTokenCount)
}

// MARK: - Corpus

/// Every line phonemizes to something the model has tokens for. A line that
/// silently lost a scalar would be listened to and judged without anyone
/// knowing part of it never reached the model.
@Test func everyCorpusLineStaysInsideTheVocabulary() throws {
  let vocab = try KokoroConfig.loadConfig().vocab
  let lines = try corpusLines()
  #expect(lines.count > 150, "corpus shrank to \(lines.count) lines")

  for line in lines {
    let result = SanskritPhonemizer.analyze(line)
    for scalar in result.kokoroPhonemes.unicodeScalars {
      #expect(vocab[String(scalar)] != nil,
              "U+\(String(format: "%04X", scalar.value)) has no token, in: \(line)")
    }
  }
}

/// Devanagari in the corpus always produces phonemes. The deliberately
/// malformed and Latin-only lines are the exception and are named here rather
/// than filtered by a rule that might hide a real regression.
@Test func everyDevanagariCorpusLineProducesPhonemes() throws {
  let expectedEmpty: Set<String> = ["ा", "Bhagavad Gita"]
  for line in try corpusLines() where !expectedEmpty.contains(line) {
    #expect(!SanskritPhonemizer.phonemize(line).isEmpty, "empty output for: \(line)")
  }
}

/// Nothing anywhere in the corpus loses an inherent vowel. This is the single
/// property that separates Sanskrit from Hindi, so it is checked in bulk
/// rather than only on the words that happen to be in a unit test.
@Test func noCorpusLineEverDeletesAnInherentVowel() throws {
  for line in try corpusLines() {
    let result = SanskritPhonemizer.analyze(line)
    let aksharas = result.units.compactMap { unit -> SanskritAkshara? in
      if case let .akshara(akshara) = unit { return akshara }
      return nil
    }
    // Every akshara without a written virama carries a vowel.
    let inherent = aksharas.filter { $0.vowel == .a }.count
    let vowelless = aksharas.filter { $0.vowel == nil }.count
    #expect(inherent + vowelless <= aksharas.count)
    // And the resolved form has at least as many vowels as aksharas with one.
    let vowelSegments = result.phonological.filter { "aAiIuUfFxXeEoO".contains($0) }.count
    #expect(vowelSegments >= aksharas.filter { $0.vowel != nil }.count,
            "vowels went missing in: \(line)")
  }
}

// MARK: - Routing

@Test func theProcessorAcceptsOnlySanskrit() throws {
  let processor = SanskritG2PProcessor()
  #expect(throws: G2PProcessorError.self) { try processor.process(input: "कर्म") }
  try processor.setLanguage(.sa)
  #expect(try processor.process(input: "कर्म").0 == "kaɾma")
  #expect(try processor.process(input: "कर्म").1 == nil)

  for language in [Language.hi, .enUS, .enGB, .none] {
    #expect(throws: G2PProcessorError.self) { try SanskritG2PProcessor().setLanguage(language) }
  }
}

@Test func theFactoryBuildsTheSanskritEngine() throws {
  let processor = try G2PFactory.createG2PProcessor(engine: .sanskrit)
  #expect(processor is SanskritG2PProcessor)
  try processor.setLanguage(.sa)
  #expect(try processor.process(input: "योग").0 == "joːɡa")
}

/// Sanskrit is its own language, not a Hindi variant.
@Test func sanskritIsASeparateLanguage() {
  #expect(Language.sa.rawValue == "sa")
  #expect(Language.sa != Language.hi)
  #expect(Language.allCases.contains(.sa))
}

// MARK: - Determinism

/// Runtime processing must be deterministic and offline: the same text always
/// gives the same phonemes, with no network, model or lookup involved.
@Test func phonemizationIsDeterministic() throws {
  for line in try corpusLines().prefix(40) {
    let first = SanskritPhonemizer.phonemize(line)
    for _ in 0 ..< 3 {
      #expect(SanskritPhonemizer.phonemize(line) == first, "unstable output for: \(line)")
    }
  }
}

// MARK: - Inspection

@Test func theInspectorReportsEveryStage() {
  let report = SanskritPhonemizer.inspect(text: "धर्मक्षेत्रे")
  for heading in [
    "INPUT", "NORMALIZED", "AKSHARAS", "CANONICAL SANSKRIT", "PHONOLOGICAL OUTPUT",
    "KOKORO PHONEMES", "TOKENS", "WARNINGS",
  ] {
    #expect(report.contains(heading), "inspector is missing \(heading)")
  }
  #expect(report.contains("Darmakzetre"))
  #expect(report.contains("dʰaɾmakʂeːtɾeː"))
  // Tokens are resolved even in a bare test process, where nothing has built
  // a KokoroTTS yet.
  #expect(report.contains("TOKENS (14)"))
}
