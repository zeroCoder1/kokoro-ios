import Foundation
import Testing
@testable import KokoroSwift

/// The pitch and energy reshaping itself runs on MLX and needs a Metal device,
/// so these cover the parameter maths and the presets — the parts that decide
/// what the reshaping is asked to do.

@Test func neutralStyleChangesNothing() {
  let neutral = SpeechStyle.neutral

  #expect(neutral.speed == 1.0)
  #expect(neutral.pitchRange == 1.0)
  #expect(neutral.energy == 1.0)
  #expect(neutral.pitchShiftSemitones == 0.0)
  // Nothing to do, so the curves are passed straight through.
  #expect(!neutral.reshapesPitchOrEnergy)
}

@Test(arguments: [SpeechStyle.newsreader, .storyteller, .excited, .calm])
func presetsActuallyReshapeSomething(style: SpeechStyle) {
  #expect(style.reshapesPitchOrEnergy || style.speed != 1.0)
}

/// F0 is in Hz, so a semitone shift is a frequency ratio. The limit is a half
/// octave each way, which is as far as this stays believable.
@Test func semitonesConvertToAFrequencyRatio() {
  #expect(abs(SpeechStyle(pitchShiftSemitones: 0).pitchRatio - 1.0) < 1e-6)
  #expect(abs(SpeechStyle(pitchShiftSemitones: 6).pitchRatio - 2.0.squareRoot().float) < 1e-5)
  #expect(abs(SpeechStyle(pitchShiftSemitones: -6).pitchRatio - (1.0 / 2.0.squareRoot()).float) < 1e-5)

  // Equal shifts up and down cancel.
  let up = SpeechStyle(pitchShiftSemitones: 3).pitchRatio
  let down = SpeechStyle(pitchShiftSemitones: -3).pitchRatio
  #expect(abs(up * down - 1.0) < 1e-5)

  // And a shift up really is up.
  #expect(SpeechStyle(pitchShiftSemitones: 2).pitchRatio > 1.0)
  #expect(SpeechStyle(pitchShiftSemitones: -2).pitchRatio < 1.0)
}

private extension Double {
  var float: Float { Float(self) }
}

/// A caller cannot ask for something that only produces artifacts.
@Test func absurdValuesAreClampedToTheBelievableRange() {
  let absurd = SpeechStyle(
    speed: 99, pitchShiftSemitones: 48, pitchRange: 40, energy: -5, sentencePause: 600
  ).clamped

  #expect(absurd.speed == SpeechStyle.Limits.speed.upperBound)
  #expect(absurd.pitchShiftSemitones == SpeechStyle.Limits.pitchShiftSemitones.upperBound)
  #expect(absurd.pitchRange == SpeechStyle.Limits.pitchRange.upperBound)
  #expect(absurd.energy == SpeechStyle.Limits.energy.lowerBound)
  #expect(absurd.sentencePause == SpeechStyle.Limits.sentencePause.upperBound)
}

@Test func clampingLeavesReasonableValuesAlone() {
  for style in [SpeechStyle.neutral, .newsreader, .storyteller, .excited, .calm] {
    #expect(style.clamped == style, "a preset was outside its own limits")
  }
}

/// Clamping the semitone shift has to reach pitchRatio too, or a caller could
/// route around the limit.
@Test func pitchRatioRespectsTheClamp() {
  let extreme = SpeechStyle(pitchShiftSemitones: 240)
  let atLimit = SpeechStyle(pitchShiftSemitones: SpeechStyle.Limits.pitchShiftSemitones.upperBound)

  #expect(extreme.pitchRatio == atLimit.pitchRatio)
}

/// The presets have to be distinguishable from each other, or they are
/// decoration.
@Test func presetsAreDistinct() {
  let all: [SpeechStyle] = [.neutral, .newsreader, .storyteller, .excited, .calm]
  #expect(Set(all.map(\.speed)).count > 3)
  #expect(Set(all.map(\.sentencePause)).count > 3)
}

/// The character of each preset, asserted so a later tweak cannot quietly
/// invert one.
@Test func presetsHaveTheCharacterTheirNamesClaim() {
  // A newsreader is brisk and level; a storyteller is slower and more sung.
  #expect(SpeechStyle.newsreader.speed > SpeechStyle.storyteller.speed)
  #expect(SpeechStyle.newsreader.pitchRange < SpeechStyle.storyteller.pitchRange)

  // Excitement is faster and higher than calm, and leaves less air.
  #expect(SpeechStyle.excited.speed > SpeechStyle.calm.speed)
  #expect(SpeechStyle.excited.pitchShiftSemitones > SpeechStyle.calm.pitchShiftSemitones)
  #expect(SpeechStyle.excited.pitchRange > SpeechStyle.calm.pitchRange)
  #expect(SpeechStyle.excited.sentencePause < SpeechStyle.calm.sentencePause)

  // Narration earns the longest pauses of the lot.
  #expect(SpeechStyle.storyteller.sentencePause >= SpeechStyle.newsreader.sentencePause)
}
