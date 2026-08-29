import Foundation
import Testing
@testable import KokoroSwift

private let sampleRate = Double(KokoroTTS.Constants.samplingRate)

/// Speech-like: bursts with gaps between them, so the signal has a high crest
/// factor and the gating actually has something to gate.
private func speechLikeSignal(seconds: Double, peak: Double) -> [Float] {
  let count = Int(seconds * sampleRate)
  var samples = [Float](repeating: 0, count: count)
  var phase = 0.0
  for index in 0 ..< count {
    let t = Double(index) / sampleRate
    // 0.6 s of voice, 0.2 s of pause.
    let inBurst = t.truncatingRemainder(dividingBy: 0.8) < 0.6
    guard inBurst else { continue }
    phase += 2.0 * .pi * (140.0 + 40.0 * sin(2.0 * .pi * 1.7 * t)) / sampleRate
    let envelope = 0.5 + 0.5 * sin(2.0 * .pi * 3.1 * t)
    let harmonics = sin(phase) + 0.4 * sin(2 * phase) + 0.2 * sin(3 * phase)
    samples[index] = Float(peak * envelope * harmonics / 1.6)
  }
  return samples
}

@Test func loudnessNormalisationHitsItsTarget() {
  let quiet = speechLikeSignal(seconds: 6, peak: 0.05)
  let before = AudioLoudness.integratedLoudness(samples: quiet, sampleRate: sampleRate)
  let loud = AudioLoudness.normalized(samples: quiet, sampleRate: sampleRate, targetLUFS: -16)
  let after = AudioLoudness.integratedLoudness(samples: loud, sampleRate: sampleRate)

  #expect(before != nil)
  #expect(after != nil)
  // Limiting costs a little, so allow a small undershoot but no overshoot.
  #expect((after ?? 0) > -17.5, "landed at \(after ?? 0) LUFS")
  #expect((after ?? 0) < -15.0, "landed at \(after ?? 0) LUFS")
}

/// The reported case: about -29 LUFS, needing 10-12 dB more.
@Test func loudnessNormalisationLiftsAQuietHindiBulletin() {
  var signal = speechLikeSignal(seconds: 8, peak: 0.4)
  let start = AudioLoudness.integratedLoudness(samples: signal, sampleRate: sampleRate) ?? 0
  let toQuiet = pow(10.0, (-29.3 - start) / 20.0)
  signal = signal.map { Float(Double($0) * toQuiet) }

  let measured = AudioLoudness.integratedLoudness(samples: signal, sampleRate: sampleRate) ?? 0
  #expect(abs(measured - (-29.3)) < 0.2, "setup measured \(measured)")

  let normalized = AudioLoudness.normalized(samples: signal, sampleRate: sampleRate)
  let after = AudioLoudness.integratedLoudness(samples: normalized, sampleRate: sampleRate) ?? 0

  #expect(after - measured > 10.0, "only gained \(after - measured) dB")
  #expect(after - measured < 15.0, "gained \(after - measured) dB")
}

/// The limiter takes a running minimum of the required gain, so the ceiling is
/// a guarantee rather than a target.
@Test(arguments: [-1.0, -3.0, -6.0])
func loudnessNormalisationNeverExceedsTheCeiling(ceiling: Double) {
  let signal = speechLikeSignal(seconds: 5, peak: 0.03)
  let normalized = AudioLoudness.normalized(
    samples: signal, sampleRate: sampleRate, targetLUFS: -14, peakCeilingDBFS: ceiling
  )

  #expect(AudioLoudness.peakDBFS(samples: normalized) <= ceiling + 1e-6,
          "peak \(AudioLoudness.peakDBFS(samples: normalized)) over \(ceiling)")
}

@Test func loudnessNormalisationLeavesSilenceAlone() {
  #expect(AudioLoudness.normalized(samples: [], sampleRate: sampleRate).isEmpty)

  let silence = [Float](repeating: 0, count: 24000)
  #expect(AudioLoudness.integratedLoudness(samples: silence, sampleRate: sampleRate) == nil)
  #expect(AudioLoudness.normalized(samples: silence, sampleRate: sampleRate) == silence)
}

/// Anything shorter than one 400 ms block is measured ungated rather than
/// rejected, so one-word utterances still normalise.
@Test func loudnessHandlesClipsShorterThanOneBlock() {
  let short = speechLikeSignal(seconds: 0.2, peak: 0.02)
  let measured = AudioLoudness.integratedLoudness(samples: short, sampleRate: sampleRate)

  #expect(measured != nil)
  let normalized = AudioLoudness.normalized(samples: short, sampleRate: sampleRate)
  #expect(AudioLoudness.peakDBFS(samples: normalized) <= AudioLoudness.defaultPeakCeilingDBFS + 1e-6)
}

/// Gating is what separates loudness from plain RMS: adding silence to the end
/// of a clip must not change how loud it measures.
@Test func loudnessGatingIgnoresTrailingSilence() {
  let signal = speechLikeSignal(seconds: 5, peak: 0.3)
  let padded = signal + [Float](repeating: 0, count: Int(3 * sampleRate))

  let a = AudioLoudness.integratedLoudness(samples: signal, sampleRate: sampleRate) ?? 0
  let b = AudioLoudness.integratedLoudness(samples: padded, sampleRate: sampleRate) ?? 0

  #expect(abs(a - b) < 0.5, "\(a) vs \(b)")
}

/// Look-ahead is the difference between a limiter and a clipper: the gain has
/// to be down *before* the transient lands, not on the sample that hits it.
@Test func loudnessLimiterPullsGainDownAheadOfATransient() {
  let sampleCount = Int(0.5 * sampleRate)
  let transientAt = sampleCount / 2
  var signal = [Float](repeating: 0.05, count: sampleCount)
  for index in transientAt ..< transientAt + 200 { signal[index] = 0.95 }

  let limited = AudioLoudness.limited(signal, sampleRate: sampleRate, ceilingDBFS: -6.0)
  let ceiling = Float(pow(10.0, -6.0 / 20.0))

  // Nothing anywhere is over the ceiling.
  #expect(limited.allSatisfy { abs($0) <= ceiling + 1e-6 })

  // And the quiet run immediately before it is already attenuated.
  let justBefore = limited[transientAt - 10]
  #expect(justBefore < 0.05, "gain had not come down: \(justBefore)")

  // Well before the transient the signal is untouched.
  #expect(abs(limited[transientAt / 2] - 0.05) < 1e-6)
}
