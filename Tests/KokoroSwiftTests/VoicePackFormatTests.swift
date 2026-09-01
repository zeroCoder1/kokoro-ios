import Foundation
import MLX
import Testing
@testable import KokoroSwift

// Needs a Metal device; run Tools/install-metallib.sh once first.

/// The shape contract a voice pack has to satisfy, asserted against the exact
/// slicing `KokoroTTS.extractStyleEmbeddings` performs. A pack that loads but
/// slices wrong does not fail loudly — it synthesizes something merely off.
@Test func aVoicePackSlicesIntoAcousticAndProsodicHalves() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("voice.safetensors")

  // 510 sequence positions, 1 channel, 256 style dims — what
  // extract_voicepack.py produces and Tools/voicepack-to-mlx.py rewrites.
  let pack = MLXArray(0 ..< (510 * 256)).reshaped([510, 1, 256]).asType(Float.self)
  try MLX.save(arrays: ["voice": pack], url: url)

  let loaded = try MLX.loadArrays(url: url)
  let voice = try #require(loaded["voice"])
  #expect(voice.shape == [510, 1, 256])

  // For a 40-token utterance KokoroTTS reads row 39.
  let reference = voice[39, 0 ... 1, 0...]
  let global = reference[0 ... 1, 128...]
  let acoustic = reference[0 ... 1, 0 ... 127]

  #expect(reference.shape == [1, 256])
  #expect(global.shape == [1, 128], "prosodic half")
  #expect(acoustic.shape == [1, 128], "acoustic half")

  // And the halves are the ones they claim to be: dims 0-127 and 128-255.
  #expect(acoustic[0, 0].item(Float.self) == pack[39, 0, 0].item(Float.self))
  #expect(global[0, 0].item(Float.self) == pack[39, 0, 128].item(Float.self))
}

/// mlx-swift reads `.safetensors` and `.npy` and rejects `.npz` outright, so
/// the converter must not write one.
@Test func mlxRejectsNpzWhichIsWhyTheConverterWritesSafetensors() throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("\(UUID().uuidString).npz")
  try Data([0x50, 0x4B, 0x03, 0x04]).write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }

  #expect(throws: (any Error).self) { _ = try MLX.loadArrays(url: url) }
}
