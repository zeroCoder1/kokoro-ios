import Foundation

/// How long a pause each Sanskrit boundary is worth.
///
/// **These are seconds of real silence, and they are not part of G2P.** They
/// exist because Kokoro's punctuation does not deliver a *differentiated*
/// pause. Measured on this model at verse length, with the same phonemes and
/// only the separator changed:
///
///     separator between the two pādas   longest internal silence
///     none (plain space)                   350 ms
///     `,`  (daṇḍa)                         385 ms
///     `.`  (double daṇḍa)                  355 ms
///
/// The model does insert a substantial gap on its own — about 350 ms — but it
/// inserts roughly the same one whether the punctuation is there or not, and
/// `।` and `॥` come out identical. So the phoneme stream still carries `,`
/// and `.`, because the model uses them for intonation and final lengthening,
/// and this layer supplies the *differentiated duration* the model will not.
/// That is the same mechanism `generateContinuousAudio` uses between
/// sentences.
///
/// The defaults are **totals, not additions**: each stretch is trimmed of the
/// decoder's own edge silence first, so the configured value is the whole gap.
/// They are set above the model's natural 350 ms, or configuring a pause would
/// make the verse *less* separated than leaving it alone.
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
    padaPause: TimeInterval = 0.50,
    versePause: TimeInterval = 1.00,
    sentencePause: TimeInterval = 0.50
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

/// A speaking rate paired with the pauses that suit it.
///
/// Sanskrit is not English at 1.0. Measured on BG 1.1's first pāda — identical
/// phonemes and token ids at every rate, only `speed` changed — by counting
/// separately articulated energy nuclei against the 16 syllables the pāda
/// actually has:
///
///     speed   duration   nuclei   mean nucleus
///     0.72     4750 ms     18        106 ms
///     0.78     4420 ms     20         93 ms
///     0.84     3960 ms     19         86 ms
///     0.90     3475 ms     17         85 ms
///     1.00     3255 ms     15         92 ms      ← fewer nuclei than syllables
///
/// At 1.0 the model resolves fewer nuclei than the pāda has syllables, which
/// is syllables merging. From 0.84 down every syllable is separately
/// articulated. That is the evidence for the presets below; it is a measure of
/// articulation, not of how good it sounds, so treat the values as a starting
/// point for listening rather than a settled answer.
struct SanskritDelivery: Equatable {
  var speed: Float
  var prosody: SanskritProsodyConfiguration

  /// Deliberate pace for following along word by word, with long pauses.
  static let learning = SanskritDelivery(
    speed: 0.75,
    prosody: SanskritProsodyConfiguration(padaPause: 0.70, versePause: 1.30)
  )

  /// The default for recitation. The slowest rate at which every syllable
  /// still resolves separately, without sounding laboured.
  static let recitation = SanskritDelivery(
    speed: 0.84,
    prosody: SanskritProsodyConfiguration(padaPause: 0.50, versePause: 1.00)
  )

  /// The voice's own pace. Syllables begin to merge here; kept for review and
  /// for callers who want it, not recommended for recitation.
  static let fast = SanskritDelivery(
    speed: 1.0,
    prosody: SanskritProsodyConfiguration(padaPause: 0.40, versePause: 0.80)
  )
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
