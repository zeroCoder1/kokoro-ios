import Foundation

/// Builds StyleTTS2 training manifests for fine-tuning Kokoro on Hindi.
///
/// The kikiri-tts recipe generates its phoneme column with misaki's espeak
/// backend. For Hindi that is the path this package exists to replace: espeak
/// leaks its internal `r.` mnemonic for the retroflex flap, and diverges from
/// this phonemizer on about half of common words. Labelling the training data
/// with this phonemizer instead makes the fine-tuned model learn the phonemes
/// that inference will actually send it, which is the whole point of doing the
/// training run.
///
/// Every label is checked against the Kokoro vocabulary before it is emitted.
/// A phoneme with no token is dropped silently at tokenization, so an unnoticed
/// one would train the model against audio it cannot account for — the German
/// recipe hit exactly this and had to remap `ʏ`. Here it is a hard rejection
/// with the offending code point named.
public enum HindiTrainingLabels {
  /// One accepted line of the manifest.
  public struct Label: Sendable, Equatable {
    public let audioPath: String
    public let phonemes: String
    public let speaker: String

    /// StyleTTS2's pipe-delimited layout: audio, phonemes, speaker.
    public var manifestLine: String { "\(audioPath)|\(phonemes)|\(speaker)" }
  }

  /// Why a clip was kept out of the manifest.
  public enum Rejection: String, Sendable {
    /// No transcript text at all.
    case emptyTranscript
    /// The transcript produced no phonemes — usually punctuation only.
    case emptyPhonemes
    /// A phoneme with no Kokoro token. Never train on this.
    case outOfVocabulary
    /// Longer than the model's context.
    case tooManyTokens
    /// Latin script the Hindi phonemizer does not handle on its own. These
    /// need review rather than silent inclusion.
    case containsLatinScript
  }

  public struct Report: Sendable {
    public var labels: [Label] = []
    public var rejections: [(id: String, reason: Rejection, detail: String)] = []

    public var manifest: String { labels.map(\.manifestLine).joined(separator: "\n") }

    public var summary: String {
      var counts: [Rejection: Int] = [:]
      for rejection in rejections { counts[rejection.reason, default: 0] += 1 }
      var lines = ["accepted: \(labels.count)", "rejected: \(rejections.count)"]
      for (reason, count) in counts.sorted(by: { $0.value > $1.value }) {
        lines.append("  \(reason.rawValue): \(count)")
      }
      return lines.joined(separator: "\n")
    }
  }

  /// Phonemes for one transcript, matching what `HindiG2PProcessor` produces
  /// for Devanagari at inference: numbers expanded first, then phonemized.
  public static func phonemes(for text: String) -> String {
    HindiPhonemizer.phonemize(HindiNumbers.expand(text))
  }

  /// Turns transcripts into manifest lines, rejecting anything unsafe to train
  /// on.
  ///
  /// - Parameters:
  ///   - entries: Clip id and transcript pairs, from `TranscriptFile.parse`.
  ///   - speaker: Value for the manifest's third column, e.g. `hi_female`.
  ///   - audioDirectory: Directory the wav paths are built against.
  ///   - audioExtension: Defaults to `wav`, which is what the recipe wants.
  ///   - vocab: The Kokoro vocabulary to validate phonemes against.
  ///   - maxTokens: Context limit; defaults to the model's own.
  public static func export(
    entries: [(id: String, text: String)],
    speaker: String,
    audioDirectory: String,
    audioExtension: String = "wav",
    vocab: [String: Int],
    maxTokens: Int = KokoroTTS.Constants.maxTokenCount
  ) -> Report {
    var report = Report()
    let directory = audioDirectory.hasSuffix("/") ? String(audioDirectory.dropLast()) : audioDirectory

    for entry in entries {
      let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        report.rejections.append((entry.id, .emptyTranscript, ""))
        continue
      }
      // Latin runs would go to Misaki at inference, which is a different
      // engine with its own phoneme conventions. Mixing that into Hindi
      // training labels is not something to do without looking.
      if text.unicodeScalars.contains(where: { isLatinLetter($0) }) {
        report.rejections.append((entry.id, .containsLatinScript, text))
        continue
      }

      let phonemes = phonemes(for: text)
      // A transcript of nothing but punctuation phonemizes to punctuation
      // tokens, which are real vocabulary entries — non-empty, and valid. It
      // still carries no speech, so pairing it with audio teaches the model
      // that a pause sounds like whatever is in that clip.
      guard phonemes.unicodeScalars.contains(where: isSpeechSound) else {
        report.rejections.append((entry.id, .emptyPhonemes, text))
        continue
      }

      let unsupported = phonemes.unicodeScalars.filter { vocab[String($0)] == nil }
      guard unsupported.isEmpty else {
        let detail = unsupported
          .map { "U+" + String(format: "%04X", $0.value) }
          .joined(separator: " ")
        report.rejections.append((entry.id, .outOfVocabulary, "\(phonemes) [\(detail)]"))
        continue
      }

      guard phonemes.unicodeScalars.count <= maxTokens else {
        report.rejections.append((entry.id, .tooManyTokens, "\(phonemes.unicodeScalars.count) tokens"))
        continue
      }

      report.labels.append(Label(
        audioPath: "\(directory)/\(entry.id).\(audioExtension)",
        phonemes: phonemes,
        speaker: speaker
      ))
    }
    return report
  }

  /// As `export(entries:speaker:audioDirectory:audioExtension:vocab:maxTokens:)`,
  /// but loading the bundled Kokoro vocabulary rather than taking one.
  public static func export(
    entries: [(id: String, text: String)],
    speaker: String,
    audioDirectory: String,
    audioExtension: String = "wav"
  ) throws -> Report {
    try export(
      entries: entries,
      speaker: speaker,
      audioDirectory: audioDirectory,
      audioExtension: audioExtension,
      vocab: KokoroConfig.loadConfig().vocab
    )
  }

  /// Whether a scalar is an actual speech sound, as opposed to punctuation,
  /// spacing or a stress mark.
  private static func isSpeechSound(_ scalar: UnicodeScalar) -> Bool {
    if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
    if CharacterSet.punctuationCharacters.contains(scalar) { return false }
    return scalar != "ˈ" && scalar != "ˌ"
  }

  private static func isLatinLetter(_ scalar: UnicodeScalar) -> Bool {
    (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
  }
}

/// Reads the transcript layouts Indic-TTS and similar corpora ship in.
public enum TranscriptFile {
  /// Parses transcripts, accepting the three layouts these corpora use:
  /// Festival `( id "text" )`, tab-separated, and pipe-separated.
  public static func parse(_ contents: String) -> [(id: String, text: String)] {
    contents.split(whereSeparator: \.isNewline).compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
      return festival(trimmed) ?? delimited(trimmed, by: "\t") ?? delimited(trimmed, by: "|")
    }
  }

  /// `( clip_0001 "यह एक वाक्य है" )` — the Festival layout Indic-TTS uses.
  private static func festival(_ line: String) -> (id: String, text: String)? {
    guard line.hasPrefix("("), line.hasSuffix(")") else { return nil }
    let body = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
    guard let quote = body.firstIndex(of: "\"") else { return nil }
    let identifier = body[..<quote].trimmingCharacters(in: .whitespaces)
    let rest = body[body.index(after: quote)...]
    guard !identifier.isEmpty, let close = rest.lastIndex(of: "\"") else { return nil }
    return (identifier, String(rest[..<close]))
  }

  private static func delimited(_ line: String, by separator: Character) -> (id: String, text: String)? {
    let parts = line.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    let identifier = parts[0].trimmingCharacters(in: .whitespaces)
    let text = parts[1].trimmingCharacters(in: .whitespaces)
    guard !identifier.isEmpty, !text.isEmpty else { return nil }
    return (identifier, text)
  }
}
