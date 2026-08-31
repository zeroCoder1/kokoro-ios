import Foundation

/// How a line should be delivered — pace, pitch movement, emphasis and
/// phrasing.
///
/// Kokoro predicts an F0 (pitch) curve and an energy curve from the text and
/// the voice's style vector, then hands both to the decoder. Those two curves
/// are where delivery lives, and they are ordinary arrays sitting between the
/// two stages, so they can be reshaped before the decoder sees them. F0 is in
/// Hz — the decoder builds a harmonic source from it — which makes a semitone
/// shift and a pitch-range scale both physically meaningful.
///
/// This is prosody shaping, not learned emotion. It rescales the delivery the
/// voice already produces; it cannot add a register the voice never had, and
/// pushed far enough it will sound artificial rather than expressive. The
/// presets stay inside ranges where it does not. Voices graded A and B respond
/// noticeably better than the Grade C packs, so this does more for English than
/// it does for Hindi.
public struct SpeechStyle: Sendable, Equatable {
  /// Speaking rate. 1.0 is the voice's own pace, above 1 is faster.
  public var speed: Float

  /// Shifts the whole pitch contour, in semitones. Small values read as mood;
  /// large ones read as a different speaker, and not a convincing one.
  public var pitchShiftSemitones: Float

  /// Scales how far pitch travels from its own mean. 1.0 keeps the voice's own
  /// intonation, above 1 widens it into something more sung, below 1 flattens
  /// it towards a monotone.
  public var pitchRange: Float

  /// Scales the predicted energy contour, which reads as emphasis.
  public var energy: Float

  /// Silence between sentences, in seconds. Used by
  /// `KokoroTTS.generateContinuousAudio`.
  public var sentencePause: TimeInterval

  public init(
    speed: Float = 1.0,
    pitchShiftSemitones: Float = 0.0,
    pitchRange: Float = 1.0,
    energy: Float = 1.0,
    sentencePause: TimeInterval = 0.35
  ) {
    self.speed = speed
    self.pitchShiftSemitones = pitchShiftSemitones
    self.pitchRange = pitchRange
    self.energy = energy
    self.sentencePause = sentencePause
  }

  // MARK: - Presets

  /// The voice as trained, with no reshaping at all.
  public static let neutral = SpeechStyle()

  /// Bulletin delivery: brisk and level, with pitch held in a narrow band and
  /// a clear gap between items so one story does not run into the next.
  public static let newsreader = SpeechStyle(
    speed: 1.05, pitchShiftSemitones: 0.0, pitchRange: 0.9,
    energy: 1.05, sentencePause: 0.45
  )

  /// Narration: slower, with wider pitch movement and longer pauses to sit on.
  public static let storyteller = SpeechStyle(
    speed: 0.92, pitchShiftSemitones: 0.0, pitchRange: 1.3,
    energy: 1.0, sentencePause: 0.55
  )

  /// Up-tempo and higher, with pitch ranging widely and little air between
  /// sentences.
  public static let excited = SpeechStyle(
    speed: 1.12, pitchShiftSemitones: 1.5, pitchRange: 1.35,
    energy: 1.15, sentencePause: 0.22
  )

  /// Unhurried and level, pitched slightly low.
  public static let calm = SpeechStyle(
    speed: 0.9, pitchShiftSemitones: -0.5, pitchRange: 0.8,
    energy: 0.92, sentencePause: 0.5
  )

  // MARK: - Derived values

  /// Ranges the decoder stays believable across. Values outside them are
  /// admitted but pulled back to the edge, so a caller cannot accidentally ask
  /// for something that only produces artifacts.
  ///
  /// These apply to the style API only. `generateAudio(voice:language:text:speed:)`
  /// predates styles and passes its `speed` through unclamped, so its output is
  /// unchanged by any of this.
  public enum Limits {
    public static let speed: ClosedRange<Float> = 0.5 ... 2.0
    public static let pitchShiftSemitones: ClosedRange<Float> = -6.0 ... 6.0
    public static let pitchRange: ClosedRange<Float> = 0.0 ... 2.5
    public static let energy: ClosedRange<Float> = 0.25 ... 2.5
    public static let sentencePause: ClosedRange<TimeInterval> = 0.0 ... 3.0
  }

  /// The style with every value pulled inside `Limits`.
  public var clamped: SpeechStyle {
    SpeechStyle(
      speed: Swift.min(Swift.max(speed, Limits.speed.lowerBound), Limits.speed.upperBound),
      pitchShiftSemitones: Swift.min(
        Swift.max(pitchShiftSemitones, Limits.pitchShiftSemitones.lowerBound),
        Limits.pitchShiftSemitones.upperBound
      ),
      pitchRange: Swift.min(
        Swift.max(pitchRange, Limits.pitchRange.lowerBound), Limits.pitchRange.upperBound
      ),
      energy: Swift.min(
        Swift.max(energy, Limits.energy.lowerBound), Limits.energy.upperBound
      ),
      sentencePause: Swift.min(
        Swift.max(sentencePause, Limits.sentencePause.lowerBound),
        Limits.sentencePause.upperBound
      )
    )
  }

  /// Semitones expressed as the frequency ratio to multiply F0 by.
  public var pitchRatio: Float { pow(2.0, clamped.pitchShiftSemitones / 12.0) }

  /// Whether this style would leave the predicted curves untouched, so the
  /// work of reshaping them can be skipped.
  var reshapesPitchOrEnergy: Bool {
    let style = clamped
    return style.pitchRange != 1.0 || style.pitchShiftSemitones != 0.0 || style.energy != 1.0
  }
}
