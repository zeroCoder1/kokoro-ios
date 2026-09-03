import Foundation

/// A light metrical description of a verse, for diagnostics.
///
/// Deliberately **not** a Sanskrit metrics engine. It reports what the
/// syllabifier found — how many syllables per pāda, their guru/laghu pattern
/// and the mātrā total — and flags anything that looks unusual against the
/// anuṣṭubh śloka the Bhagavad Gita is mostly written in.
///
/// It never modifies phonemes to fit an expected pattern. An unusual count is
/// evidence that the parse or the source needs looking at, and is reported as
/// such; the text stays authoritative.
struct SanskritMeterAnalysis {
  /// One pāda — the stretch between daṇḍas, or between the halves a śloka is
  /// conventionally printed on.
  struct Pada {
    var syllables: [SanskritSyllable]
    var weights: [SanskritSyllableWeight] { syllables.map(\.weight) }
    var matraCount: Int { syllables.reduce(0) { $0 + $1.matras } }
    var syllableCount: Int { syllables.count }
    /// `GLGL…`, the form metrical descriptions are usually written in.
    var pattern: String { syllables.map { $0.weight == .guru ? "G" : "L" }.joined() }
    var slp1: String { syllables.map(\.slp1).joined(separator: "-") }
  }

  var padas: [Pada] = []
  var warnings: [String] = []

  var syllables: [SanskritSyllable] { padas.flatMap(\.syllables) }
  var matraCount: Int { padas.reduce(0) { $0 + $1.matraCount } }
  var padaSyllableCounts: [Int] { padas.map(\.syllableCount) }

  /// The anuṣṭubh śloka has four pādas of eight syllables. Used only as a
  /// sanity check on the parse — a mismatch is reported, never corrected.
  static let anushtubhPadaSyllables = 8
}

enum SanskritMeter {
  /// Analyses a verse.
  ///
  /// A pāda break is a daṇḍa or a double daṇḍa. A śloka printed on two lines
  /// has two of those and therefore two half-verses; where the source also
  /// breaks lines, each half is checked against **two** anuṣṭubh pādas of
  /// eight, since the internal break between them is not written.
  static func analyze(
    _ text: String,
    options: SanskritOptions = .default
  ) -> SanskritMeterAnalysis {
    var analysis = SanskritMeterAnalysis()
    let normalized = SanskritNormalizer.normalize(text)
    let units = SanskritAksharaParser.parse(normalized.text).units

    // Split the units at pause boundaries; each stretch is a pāda group.
    var stretch: [SanskritUnit] = []
    var stretches: [[SanskritUnit]] = []
    for unit in units {
      if case let .boundary(boundary) = unit, boundary.isPause {
        stretch.append(unit)
        if !stretch.isEmpty { stretches.append(stretch); stretch = [] }
        continue
      }
      stretch.append(unit)
    }
    if !stretch.contains(where: { if case .akshara = $0 { return true }; return false }) == false {
      stretches.append(stretch)
    }

    for group in stretches {
      // The last syllable of a pāda is metrically heavy by position.
      let syllabified = SanskritSyllabifier.syllabify(
        group, options: options, lineFinalIsHeavy: true
      )
      guard !syllabified.syllables.isEmpty else { continue }
      analysis.padas.append(SanskritMeterAnalysis.Pada(syllables: syllabified.syllables))
      analysis.warnings += syllabified.warnings
    }

    // Sanity check, not enforcement. A half-verse of a śloka carries two
    // anuṣṭubh pādas, so sixteen syllables, and a quarter carries eight.
    let expected = SanskritMeterAnalysis.anushtubhPadaSyllables
    for (index, pada) in analysis.padas.enumerated() {
      let count = pada.syllableCount
      let isHalf = count > expected + 2
      let target = isHalf ? expected * 2 : expected
      if abs(count - target) > 1 {
        analysis.warnings.append(
          "PADA_SYLLABLE_COUNT_UNUSUAL: pāda \(index + 1) has \(count) syllables, "
            + "expected about \(target) for anuṣṭubh — check the parse or the source"
        )
      }
    }
    return analysis
  }

  /// A printable report, used by the diagnostics tooling.
  static func report(_ text: String, title: String = "") -> String {
    let analysis = analyze(text)
    var lines: [String] = []
    if !title.isEmpty { lines.append("## \(title)") ; lines.append("") }
    lines.append("SOURCE")
    for line in text.split(separator: "\n") { lines.append("  \(line)") }
    lines.append("")

    for (index, pada) in analysis.padas.enumerated() {
      lines.append("PĀDA \(index + 1)")
      lines.append("  syllables:  \(pada.syllables.map(\.slp1).joined(separator: " · "))")
      lines.append("  weights:    \(pada.pattern)")
      lines.append("  mātrās:     \(pada.syllables.map { String($0.matras) }.joined(separator: " "))"
        + "   total \(pada.matraCount)")
      lines.append("  count:      \(pada.syllableCount)")
      let held = pada.syllables.filter(\.holdClosingConsonant)
      if !held.isEmpty {
        lines.append("  holding:    \(held.map(\.slp1).joined(separator: " "))")
      }
      lines.append("")
    }

    lines.append("TOTALS")
    lines.append("  syllables per pāda: \(analysis.padaSyllableCounts.map(String.init).joined(separator: " + "))")
    lines.append("  mātrās:             \(analysis.matraCount)")
    lines.append("")
    lines.append("WARNINGS")
    if analysis.warnings.isEmpty {
      lines.append("  none")
    } else {
      for warning in analysis.warnings { lines.append("  \(warning)") }
    }
    lines.append("")
    lines.append("CANONICAL PHONEMES")
    lines.append("  \(SanskritPhonemizer.analyze(text).canonical)")
    return lines.joined(separator: "\n")
  }
}
