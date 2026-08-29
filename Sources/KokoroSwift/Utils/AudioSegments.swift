import Foundation

/// Assembling synthesized chunks into one continuous stream.
enum AudioSegments {
  /// Joins `segments` with `pause` seconds of silence between them.
  static func joined(_ segments: [[Float]], pause: TimeInterval, sampleRate: Double) -> [Float] {
    let nonEmpty = segments.filter { !$0.isEmpty }
    guard let first = nonEmpty.first else { return [] }
    guard nonEmpty.count > 1 else { return first }

    let silence = [Float](repeating: 0, count: Swift.max(0, Int(pause * sampleRate)))
    var output = first
    output.reserveCapacity(nonEmpty.reduce(0) { $0 + $1.count } + silence.count * (nonEmpty.count - 1))
    for segment in nonEmpty.dropFirst() {
      output.append(contentsOf: silence)
      output.append(contentsOf: segment)
    }
    return output
  }

  /// Trims near-silence from both ends of a segment.
  ///
  /// The decoder leaves a variable amount of silence around each utterance.
  /// Left in place it stacks on top of the pause the caller asked for, so the
  /// gap between two sentences is neither predictable nor the same twice. A
  /// guard band of a few milliseconds is kept so nothing clips the onset of
  /// the first phoneme or the release of the last.
  static func trimmingEdgeSilence(
    _ samples: [Float],
    sampleRate: Double,
    thresholdDBFS: Double = -50.0,
    guardSeconds: TimeInterval = 0.01
  ) -> [Float] {
    let threshold = Float(pow(10.0, thresholdDBFS / 20.0))
    guard let firstLoud = samples.firstIndex(where: { abs($0) > threshold }),
          let lastLoud = samples.lastIndex(where: { abs($0) > threshold })
    else { return [] }

    let guardSamples = Swift.max(0, Int(guardSeconds * sampleRate))
    let start = Swift.max(0, firstLoud - guardSamples)
    let end = Swift.min(samples.count, lastLoud + guardSamples + 1)
    return Array(samples[start ..< end])
  }
}
