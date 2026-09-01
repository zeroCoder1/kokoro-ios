import Foundation
import MLX

/// Applies a `SpeechStyle` to the pitch and energy curves the prosody
/// predictor produced, before the decoder sees them.
///
/// Kept out of `KokoroTTS` so it can be exercised without a model. This is the
/// one piece of the style feature that touches MLX, and it needs to be
/// testable on its own.
enum ProsodyReshaper {
  /// Below this, in Hz, a frame is taken to be unvoiced.
  static let voicingFloor: Float = 1.0

  /// Pitch range scales each frame's distance from the curve's own mean, so
  /// the shape of the intonation is kept and only its extent changes. The
  /// semitone shift is then a plain frequency ratio, F0 being in Hz.
  ///
  /// Unvoiced frames come back exactly as they went in. The decoder builds a
  /// harmonic source from F0, so lifting a silent frame off zero would make it
  /// ring where the voice should be producing no tone at all.
  static func reshape(
    f0: MLXArray, n: MLXArray, to style: SpeechStyle
  ) -> (f0: MLXArray, n: MLXArray) {
    guard style.reshapesPitchOrEnergy else { return (f0, n) }

    let voiced = (f0 .> MLXArray(voicingFloor)).asType(Float.self)
    let voicedFrames = MLX.maximum(MLX.sum(voiced), MLXArray(Float(1)))
    let mean = MLX.sum(f0 * voiced) / voicedFrames

    var shaped = (mean + (f0 - mean) * style.pitchRange) * style.pitchRatio
    shaped = MLX.maximum(shaped, MLXArray(Float(0)))
    // Put the unvoiced frames back untouched.
    shaped = shaped * voiced + f0 * (1 - voiced)

    return (shaped, n * style.energy)
  }
}
