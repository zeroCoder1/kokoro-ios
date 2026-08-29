import Foundation

/// Loudness measurement and normalisation to ITU-R BS.1770-4.
///
/// The decoder returns audio at whatever level the voice pack sits at, and the
/// Hindi packs are very quiet — around -29 LUFS, where spoken content is
/// normally delivered near -16. That is a level problem rather than a synthesis
/// problem, so it is fixed here instead of anywhere near the model.
///
/// Raising a quiet signal by gain alone would clip it: speech has a high crest
/// factor, and +13 dB of gain on a -8 dBFS peak lands well above full scale.
/// `normalized(...)` therefore applies the gain and then a look-ahead limiter
/// that provably holds the ceiling.
public enum AudioLoudness {
  /// Broadcast-style target for spoken content.
  public static let defaultTargetLUFS = -16.0

  /// Leaves a little headroom for downstream resampling and encoding.
  public static let defaultPeakCeilingDBFS = -1.0

  // MARK: - Measurement

  /// Integrated loudness in LUFS, gated per BS.1770-4.
  ///
  /// Returns `nil` only for digital silence. Signals shorter than one 400 ms
  /// block are measured ungated rather than rejected, so short utterances
  /// still normalise sensibly.
  public static func integratedLoudness(samples: [Float], sampleRate: Double) -> Double? {
    guard !samples.isEmpty, sampleRate > 0 else { return nil }
    let weighted = kWeighted(samples, sampleRate: sampleRate)

    let blockSize = Int(0.4 * sampleRate)
    let stepSize = Int(0.1 * sampleRate)
    guard blockSize > 0, stepSize > 0, weighted.count >= blockSize else {
      let power = meanSquare(weighted, from: 0, count: weighted.count)
      return power > 0 ? loudness(ofMeanSquare: power) : nil
    }

    var blockPowers: [Double] = []
    var start = 0
    while start + blockSize <= weighted.count {
      blockPowers.append(meanSquare(weighted, from: start, count: blockSize))
      start += stepSize
    }

    // Absolute gate at -70 LUFS drops silence between phrases.
    let absoluteGated = blockPowers.filter { $0 > 0 && loudness(ofMeanSquare: $0) > -70.0 }
    guard !absoluteGated.isEmpty else { return nil }

    // Relative gate at 10 LU below the ungated mean drops the quiet tail.
    let relativeThreshold = loudness(ofMeanSquare: mean(absoluteGated)) - 10.0
    let gated = absoluteGated.filter { loudness(ofMeanSquare: $0) > relativeThreshold }
    guard !gated.isEmpty else { return loudness(ofMeanSquare: mean(absoluteGated)) }

    return loudness(ofMeanSquare: mean(gated))
  }

  /// Highest absolute sample value expressed in dBFS. Returns `-.infinity` for
  /// digital silence.
  public static func peakDBFS(samples: [Float]) -> Double {
    let peak = samples.reduce(0.0) { Swift.max($0, abs(Double($1))) }
    return peak > 0 ? 20.0 * log10(peak) : -.infinity
  }

  // MARK: - Normalisation

  /// Brings `samples` to `targetLUFS`, holding peaks at or below
  /// `peakCeilingDBFS`.
  ///
  /// The returned audio is guaranteed not to exceed the ceiling: the limiter
  /// takes a running minimum of the required gain across a look-ahead window,
  /// so its gain is never above what each sample needs.
  public static func normalized(
    samples: [Float],
    sampleRate: Double = 24000,
    targetLUFS: Double = defaultTargetLUFS,
    peakCeilingDBFS: Double = defaultPeakCeilingDBFS
  ) -> [Float] {
    guard !samples.isEmpty else { return samples }
    guard let measured = integratedLoudness(samples: samples, sampleRate: sampleRate) else {
      return samples
    }

    let gain = pow(10.0, (targetLUFS - measured) / 20.0)
    let amplified = samples.map { Float(Double($0) * gain) }
    return limited(amplified, sampleRate: sampleRate, ceilingDBFS: peakCeilingDBFS)
  }

  /// Look-ahead limiter. Attack is instantaneous across the look-ahead window
  /// and release is smoothed, which keeps speech from pumping.
  static func limited(
    _ samples: [Float],
    sampleRate: Double,
    ceilingDBFS: Double
  ) -> [Float] {
    let ceiling = pow(10.0, ceilingDBFS / 20.0)
    guard ceiling > 0, !samples.isEmpty else { return samples }

    let required = samples.map { sample -> Double in
      let magnitude = abs(Double(sample))
      return magnitude > ceiling ? ceiling / magnitude : 1.0
    }
    guard required.contains(where: { $0 < 1.0 }) else { return samples }

    // Look ahead far enough that the gain is already down when the peak lands.
    let lookahead = Swift.max(1, Int(0.002 * sampleRate))
    var target = [Double](repeating: 1.0, count: required.count)
    var window = SlidingMinimum()
    for index in stride(from: required.count - 1, through: 0, by: -1) {
      window.append(required[index], expiringBefore: index, horizon: lookahead)
      target[index] = window.minimum
    }

    // Release: let the gain climb back over ~60 ms, never above what is needed.
    let releaseSamples = Swift.max(1, Int(0.06 * sampleRate))
    let releaseStep = 1.0 / Double(releaseSamples)
    var gain = target.first ?? 1.0
    var output = [Float](repeating: 0, count: samples.count)
    for index in 0 ..< samples.count {
      gain = Swift.min(target[index], gain + releaseStep)
      output[index] = Float(Double(samples[index]) * gain)
    }
    return output
  }

  // MARK: - K-weighting

  /// BS.1770 K-weighting: a high shelf followed by a high pass. The filters are
  /// specified at 48 kHz, so the coefficients are derived from the analog
  /// prototype to stay correct at Kokoro's 24 kHz output.
  private static func kWeighted(_ samples: [Float], sampleRate: Double) -> [Double] {
    let shelf = Biquad.highShelf(frequency: 1681.974450955533,
                                 q: 0.7071752369554196,
                                 gainDB: 3.999843853973347,
                                 sampleRate: sampleRate)
    let highPass = Biquad.highPass(frequency: 38.13547087602444,
                                   q: 0.5003270373238773,
                                   sampleRate: sampleRate)
    return highPass.process(shelf.process(samples.map(Double.init)))
  }

  private static func loudness(ofMeanSquare power: Double) -> Double {
    power > 0 ? -0.691 + 10.0 * log10(power) : -.infinity
  }

  private static func meanSquare(_ values: [Double], from start: Int, count: Int) -> Double {
    guard count > 0 else { return 0 }
    var total = 0.0
    for index in start ..< start + count { total += values[index] * values[index] }
    return total / Double(count)
  }

  private static func mean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
  }
}

/// Minimum over a trailing window, kept in a monotonic deque so the limiter
/// stays linear in the number of samples.
private struct SlidingMinimum {
  private var entries: [(value: Double, index: Int)] = []

  /// The deque increases from front to back, so the front is the smallest
  /// value still inside the window — and it is also the first to expire.
  var minimum: Double { entries.first?.value ?? 1.0 }

  mutating func append(_ value: Double, expiringBefore index: Int, horizon: Int) {
    while let last = entries.last, last.value >= value { entries.removeLast() }
    entries.append((value, index))
    while let first = entries.first, first.index > index + horizon { entries.removeFirst() }
  }
}

/// Direct-form-I biquad.
private struct Biquad {
  let b0, b1, b2, a1, a2: Double

  static func highShelf(frequency: Double, q: Double, gainDB: Double, sampleRate: Double) -> Biquad {
    let k = tan(.pi * frequency / sampleRate)
    let vh = pow(10.0, gainDB / 20.0)
    let vb = pow(vh, 0.4996667741545416)
    let denominator = 1.0 + k / q + k * k
    return Biquad(
      b0: (vh + vb * k / q + k * k) / denominator,
      b1: 2.0 * (k * k - vh) / denominator,
      b2: (vh - vb * k / q + k * k) / denominator,
      a1: 2.0 * (k * k - 1.0) / denominator,
      a2: (1.0 - k / q + k * k) / denominator
    )
  }

  static func highPass(frequency: Double, q: Double, sampleRate: Double) -> Biquad {
    let k = tan(.pi * frequency / sampleRate)
    let denominator = 1.0 + k / q + k * k
    return Biquad(
      b0: 1.0,
      b1: -2.0,
      b2: 1.0,
      a1: 2.0 * (k * k - 1.0) / denominator,
      a2: (1.0 - k / q + k * k) / denominator
    )
  }

  func process(_ input: [Double]) -> [Double] {
    var output = [Double](repeating: 0, count: input.count)
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    for index in 0 ..< input.count {
      let x0 = input[index]
      let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
      output[index] = y0
      x2 = x1; x1 = x0
      y2 = y1; y1 = y0
    }
    return output
  }
}
