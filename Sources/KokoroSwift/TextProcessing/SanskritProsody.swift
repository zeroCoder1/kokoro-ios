import Foundation

/// How long a pause each Sanskrit boundary is worth.
///
/// **These are seconds of real silence, and they are not part of G2P.** They
/// exist because Kokoro's punctuation tokens do not deliver a usable pause.
/// Measured on this model, between two words, with everything else identical:
///
///     separator   total span   internal silence
///     none           865 ms      25 ms
///     space          995 ms      35 ms
///     `,`  (daṇḍa)  1040 ms      30 ms
///     `.`  (verse)   970 ms      30 ms
///
/// The punctuation is indistinguishable from a plain space, and `।` from `॥`.
/// So the phoneme stream still carries `,` and `.` — the model does use them
/// for phrasing and intonation — and this layer supplies the *duration* the
/// model will not, by synthesizing each stretch separately and joining with
/// silence. That is the same mechanism `generateContinuousAudio` already uses
/// between sentences.
///
/// `wordBoundary` defaults to zero: the space token measurably does its job,
/// and pausing between every word would sound like dictation rather than
/// recitation.
struct SanskritProsodyConfiguration: Equatable {
  /// Extra silence at an ordinary word boundary. Zero by default — the space
  /// token already separates words.
  var wordBoundary: TimeInterval
  /// `।` — a pāda or half-verse break.
  var padaPause: TimeInterval
  /// `॥` — the end of a verse.
  var versePause: TimeInterval
  /// Sentence punctuation carried over from the source.
  var sentencePause: TimeInterval

  init(
    wordBoundary: TimeInterval = 0.0,
    padaPause: TimeInterval = 0.32,
    versePause: TimeInterval = 0.65,
    sentencePause: TimeInterval = 0.32
  ) {
    self.wordBoundary = wordBoundary
    self.padaPause = padaPause
    self.versePause = versePause
    self.sentencePause = sentencePause
  }

  /// Recitation pacing: a clear half-verse break and a longer verse break.
  static let `default` = SanskritProsodyConfiguration()

  /// No added silence at all — one call, exactly the previous behaviour.
  /// Use this to hear what the model does on its own.
  static let none = SanskritProsodyConfiguration(
    wordBoundary: 0, padaPause: 0, versePause: 0, sentencePause: 0
  )

  func pause(for boundary: SanskritBoundary) -> TimeInterval {
    switch boundary {
    case .word: return wordBoundary
    case .pada: return padaPause
    case .verse: return versePause
    case .sentence: return sentencePause
    case .elision: return 0
    }
  }
}

/// Splits a Sanskrit text into stretches that are synthesized separately and
/// rejoined with real silence.
///
/// Strictly a **prosody** layer sitting after G2P, not part of it. The
/// phonemes for a given stretch are exactly what `SanskritPhonemizer` produces
/// for it; nothing here changes a phoneme. Splitting is safe because the
/// phonological rules never look across a pause anyway — the anusvāra and
/// visarga lookaheads both stop at one.
enum SanskritProsody {
  struct Segment: Equatable {
    /// What to synthesize.
    let phonemes: String
    /// Silence to append after it, in seconds.
    let pauseAfter: TimeInterval
    /// The boundary that ended this stretch, for diagnostics.
    let boundary: SanskritBoundary?
  }

  /// Splits at every boundary the configuration gives a non-zero pause to.
  /// With `.none` this returns a single segment and the result is identical
  /// to one `generateAudio` call.
  static func segments(
    for text: String,
    options: SanskritOptions = .default,
    configuration: SanskritProsodyConfiguration = .default
  ) -> [Segment] {
    let normalized = SanskritNormalizer.normalize(text)
    let parsed = SanskritAksharaParser.parse(normalized.text)

    var segments: [Segment] = []
    var pending: [SanskritUnit] = []

    func flush(endedBy boundary: SanskritBoundary?) {
      guard !pending.isEmpty else { return }
      let phonology = SanskritPhonology.apply(to: pending, options: options)
      let mapped = SanskritKokoroMapper.map(phonology.segments, options: options)
      pending.removeAll(keepingCapacity: true)
      guard !mapped.phonemes.isEmpty else { return }
      segments.append(Segment(
        phonemes: mapped.phonemes,
        pauseAfter: boundary.map(configuration.pause(for:)) ?? 0,
        boundary: boundary
      ))
    }

    for unit in parsed.units {
      // A boundary the configuration pauses at ends the stretch, and stays in
      // it: the punctuation token still reaches the model, so intonation and
      // final lengthening are the model's own rather than an abrupt cut.
      if case let .boundary(boundary) = unit, configuration.pause(for: boundary) > 0 {
        pending.append(unit)
        flush(endedBy: boundary)
        continue
      }
      pending.append(unit)
    }
    flush(endedBy: nil)
    return segments
  }
}
