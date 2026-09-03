import Foundation

/// Classical Sanskrit in Devanagari, phonemized for Kokoro.
///
/// Deterministic, offline and allocation-light: no network, no model, no
/// Python, no lookup service. The same text always gives the same phonemes.
///
///     Devanagari
///       -> SanskritNormalizer      orthographic cleanup, still Devanagari
///       -> SanskritAksharaParser   aksharas and boundaries
///       -> SanskritPhonology       canonical Sanskrit phonemes (SLP1)
///       -> SanskritKokoroMapper    Kokoro IPA
///       -> Tokenizer               Kokoro token ids
///
/// This shares no code with `HindiPhonemizer` and reaches none of its rules.
/// Sanskrit does not delete schwas, does not read क्ष as `kʃ` or ज्ञ as `ɡj`,
/// has no lexical override table and assigns no stress. See §7 of the brief
/// and `docs/SANSKRIT.md`.
enum SanskritPhonemizer {
  /// Everything the pipeline produced, at every stage. The intermediate forms
  /// are kept because a wrong pronunciation is diagnosed by finding the layer
  /// that introduced it, not by listening harder.
  struct Result {
    /// The text as given.
    var original: String
    /// After orthographic cleanup. Still Devanagari.
    var normalized: String
    /// Aksharas and boundaries, with source offsets.
    var units: [SanskritUnit]
    /// SLP1 straight from the aksharas, marks unresolved (`M`, `H`, `'`).
    /// Directly comparable against Vagdhenu's `to_slp1`.
    var canonical: String
    /// SLP1 after the phonological rules: anusvara resolved to its nasal,
    /// visarga to its echo.
    var phonological: String
    /// What Kokoro is actually sent.
    var kokoroPhonemes: String
    /// Every approximation, unsupported sound and unreadable scalar.
    var warnings: [SanskritWarning]

    /// Kokoro token ids for `kokoroPhonemes`.
    ///
    /// `Tokenizer` returns nothing at all when the model configuration has not
    /// been loaded, which in the inspector reads as "this line produced no
    /// tokens" rather than "the vocabulary is missing". Loading it here means
    /// inspection works in a bare test process, where nothing has constructed
    /// a `KokoroTTS` yet.
    var tokens: [Int] {
      _ = try? KokoroConfig.loadConfig()
      return Tokenizer.tokenize(phonemizedText: kokoroPhonemes)
    }
  }

  static func phonemize(
    _ text: String,
    options: SanskritOptions = .default
  ) -> String {
    analyze(text, options: options).kokoroPhonemes
  }

  /// The full pipeline, keeping every intermediate form.
  static func analyze(
    _ text: String,
    options: SanskritOptions = .default
  ) -> Result {
    let normalized = SanskritNormalizer.normalize(text)
    let parsed = SanskritAksharaParser.parse(normalized.text)
    let phonology = SanskritPhonology.apply(to: parsed.units, options: options)
    let kokoro = SanskritKokoroMapper.map(phonology.segments, options: options)

    return Result(
      original: text,
      normalized: normalized.text,
      units: parsed.units,
      canonical: canonicalSLP1(parsed.units),
      phonological: phonology.slp1,
      kokoroPhonemes: kokoro.phonemes,
      warnings: normalized.warnings + parsed.warnings
        + phonology.warnings + kokoro.warnings
    )
  }

  /// SLP1 with the marks left as marks — `saMskfta`, `rAmaH`, `so'ham`. This
  /// is the traditional canonical form and the one to diff against a
  /// reference; `Result.phonological` is the same text after the rules run.
  static func canonicalSLP1(_ units: [SanskritUnit]) -> String {
    var out = ""
    for unit in units {
      switch unit {
      case let .boundary(boundary):
        out += boundary.slp1
      case let .akshara(akshara):
        for consonant in akshara.onset { out += consonant.rawValue }
        if let vowel = akshara.vowel { out += vowel.rawValue }
        if akshara.anusvara { out += "M" }
        if akshara.chandrabindu { out += "~" }
        if akshara.visarga { out += "H" }
      }
    }
    return out.trimmingCharacters(in: .whitespaces)
  }

  // MARK: - Inspection

  /// A full account of how one line was read, for reviewing pronunciation
  /// without synthesizing it first.
  ///
  ///     Tools/sanskrit-inspect.sh "धर्मक्षेत्रे कुरुक्षेत्रे"
  ///
  /// The reference comparison the brief asks for is deliberately absent here:
  /// Vagdhenu, EdgeSanskrit and eSpeak are development references, not runtime
  /// dependencies, and comparing against them belongs in
  /// `Tools/sanskrit-reference-compare.py`.
  static func inspect(text: String, options: SanskritOptions = .default) -> String {
    let result = analyze(text, options: options)
    var lines: [String] = []

    lines += ["INPUT", "  \(result.original)", ""]
    lines += ["NORMALIZED", "  \(result.normalized)", ""]

    lines.append("AKSHARAS")
    for unit in result.units {
      switch unit {
      case let .boundary(boundary):
        lines.append("  \(describe(boundary))")
      case let .akshara(akshara):
        lines.append("  \(describe(akshara))")
      }
    }
    lines.append("")

    lines += ["CANONICAL SANSKRIT (SLP1)", "  \(result.canonical)", ""]
    lines += ["PHONOLOGICAL OUTPUT (SLP1)", "  \(result.phonological)", ""]
    lines += ["KOKORO PHONEMES", "  \(result.kokoroPhonemes)", ""]

    let tokens = result.tokens
    lines += ["TOKENS (\(tokens.count))", "  \(tokens.map(String.init).joined(separator: " "))", ""]

    lines.append("WARNINGS")
    if result.warnings.isEmpty {
      lines.append("  none")
    } else {
      for warning in result.warnings { lines.append("  \(warning.text)") }
    }

    return lines.joined(separator: "\n")
  }

  private static func describe(_ akshara: SanskritAkshara) -> String {
    var parts: [String] = []
    if !akshara.onset.isEmpty {
      parts.append("onset " + akshara.onset.map(\.rawValue).joined(separator: "+"))
    }
    if let vowel = akshara.vowel {
      parts.append("vowel \(vowel.rawValue)\(vowel.isLong ? " (long)" : "")")
    } else {
      parts.append("no vowel (virāma)")
    }
    if akshara.anusvara { parts.append("anusvāra") }
    if akshara.chandrabindu { parts.append("chandrabindu") }
    if akshara.visarga { parts.append("visarga") }
    var slp1 = akshara.onset.map(\.rawValue).joined()
    slp1 += akshara.vowel?.rawValue ?? ""
    if akshara.anusvara { slp1 += "M" }
    if akshara.chandrabindu { slp1 += "~" }
    if akshara.visarga { slp1 += "H" }
    return slp1.padding(toLength: max(10, slp1.count), withPad: " ", startingAt: 0)
      + parts.joined(separator: ", ")
  }

  private static func describe(_ boundary: SanskritBoundary) -> String {
    switch boundary {
    case .word: return "·          word boundary"
    case .pada: return "|          pāda boundary (daṇḍa) — moderate pause"
    case .verse: return "||         verse boundary (double daṇḍa) — strong pause"
    case .sentence(let character): return "\(character)          sentence punctuation"
    case .elision: return "'          avagraha — silent, elided initial अ"
    }
  }
}
