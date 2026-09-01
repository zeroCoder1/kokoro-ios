import Foundation
import MLX
import Testing
@testable import KokoroSwift

// These exercise the one part of the style feature that touches MLX. They need
// a Metal device: `swift test` cannot compile the shaders itself, so run
// Tools/install-metallib.sh once first (see docs).

private func values(_ array: MLXArray) -> [Float] { array.asArray(Float.self) }

/// A voiced curve with a silent stretch in the middle, which is what the
/// predictor actually produces: F0 in Hz, zero where nothing is voiced.
private func pitchCurve() -> MLXArray {
  MLXArray([120, 140, 180, 220, 0, 0, 0, 160, 130, 110] as [Float])
}

private func energyCurve() -> MLXArray {
  MLXArray([0.2, 0.4, 0.8, 1.0, 0.0, 0.0, 0.0, 0.7, 0.5, 0.3] as [Float])
}

@Test func neutralStyleReturnsTheCurvesUntouched() {
  let f0 = pitchCurve(), n = energyCurve()
  let out = ProsodyReshaper.reshape(f0: f0, n: n, to: .neutral)

  #expect(values(out.f0) == values(f0))
  #expect(values(out.n) == values(n))
}

/// The single most important property: the decoder builds a harmonic source
/// from F0, so a silent frame lifted off zero would ring where the voice
/// should be producing no tone at all.
@Test(arguments: [SpeechStyle.newsreader, .storyteller, .excited, .calm])
func unvoicedFramesAreNeverLiftedOffZero(style: SpeechStyle) {
  let out = ProsodyReshaper.reshape(f0: pitchCurve(), n: energyCurve(), to: style)
  let shaped = values(out.f0)

  for index in 4 ... 6 {
    #expect(shaped[index] == 0, "frame \(index) rang at \(shaped[index]) under \(style)")
  }
}

/// Widening the range moves each frame further from the mean without moving
/// the mean itself — that is what keeps it expressive rather than detuned.
@Test func pitchRangeScalesDeviationAndLeavesTheMeanAlone() {
  let f0 = pitchCurve()
  let wide = ProsodyReshaper.reshape(
    f0: f0, n: energyCurve(), to: SpeechStyle(pitchRange: 2.0)
  ).f0
  let flat = ProsodyReshaper.reshape(
    f0: f0, n: energyCurve(), to: SpeechStyle(pitchRange: 0.5)
  ).f0

  let voiced = [0, 1, 2, 3, 7, 8, 9]
  let original = values(f0), widened = values(wide), flattened = values(flat)
  let mean = voiced.map { original[$0] }.reduce(0, +) / Float(voiced.count)

  // The voiced mean is preserved to within rounding.
  let widenedMean = voiced.map { widened[$0] }.reduce(0, +) / Float(voiced.count)
  #expect(abs(widenedMean - mean) < 1.0, "mean moved to \(widenedMean) from \(mean)")

  for index in voiced {
    let before = abs(original[index] - mean)
    #expect(abs(widened[index] - mean) > before - 0.01, "frame \(index) did not widen")
    #expect(abs(flattened[index] - mean) < before + 0.01, "frame \(index) did not flatten")
  }
}

/// F0 is in Hz, so a semitone shift is a multiplication.
@Test func pitchShiftMultipliesTheVoicedFrames() {
  let style = SpeechStyle(pitchShiftSemitones: 6)
  let out = ProsodyReshaper.reshape(f0: pitchCurve(), n: energyCurve(), to: style)
  let original = values(pitchCurve()), shifted = values(out.f0)

  for index in [0, 1, 2, 3, 7, 8, 9] {
    #expect(abs(shifted[index] - original[index] * style.pitchRatio) < 0.05,
            "frame \(index): \(shifted[index]) vs \(original[index] * style.pitchRatio)")
  }
}

@Test func energyScalesTheEnergyCurveOnly() {
  let out = ProsodyReshaper.reshape(
    f0: pitchCurve(), n: energyCurve(), to: SpeechStyle(energy: 1.5)
  )
  let original = values(energyCurve()), scaled = values(out.n)

  for index in original.indices {
    #expect(abs(scaled[index] - original[index] * 1.5) < 1e-5)
  }
  // Energy alone must not disturb pitch.
  #expect(values(out.f0) == values(pitchCurve()))
}

/// Nothing may come out negative — a negative frequency is meaningless to the
/// harmonic source.
@Test(arguments: [SpeechStyle.excited, .calm, SpeechStyle(pitchRange: 2.5),
                  SpeechStyle(pitchShiftSemitones: -6)])
func reshapingNeverProducesANegativeFrequency(style: SpeechStyle) {
  let out = ProsodyReshaper.reshape(f0: pitchCurve(), n: energyCurve(), to: style)

  #expect(values(out.f0).allSatisfy { $0 >= 0 }, "\(values(out.f0))")
  #expect(values(out.f0).allSatisfy { $0.isFinite })
}

/// A curve with no voiced frame at all must not divide by zero.
@Test func anEntirelyUnvoicedCurveIsHandled() {
  let silent = MLXArray([Float](repeating: 0, count: 8))
  let out = ProsodyReshaper.reshape(f0: silent, n: silent, to: .excited)

  #expect(values(out.f0).allSatisfy { $0 == 0 })
  #expect(values(out.f0).allSatisfy { $0.isFinite })
}
