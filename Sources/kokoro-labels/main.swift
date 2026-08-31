import Foundation
import KokoroSwift

/// Builds a StyleTTS2 training manifest for fine-tuning Kokoro on Hindi.
///
/// Run once per speaker and concatenate the results — the speaker column is
/// what separates them, so both voices train in a single run.
///
///     swift run kokoro-labels \
///       --transcripts /data/hindi_female/txt.done.data \
///       --audio-dir /data/hindi_female/wav \
///       --speaker hi_female \
///       --output /data/female.txt
struct Arguments {
  var transcripts: String?
  var audioDirectory: String?
  var speaker: String?
  var output: String?
  var rejectionsPath: String?

  static func parse(_ raw: [String]) -> Arguments {
    var arguments = Arguments()
    var index = 0
    while index + 1 < raw.count {
      let value = raw[index + 1]
      switch raw[index] {
      case "--transcripts": arguments.transcripts = value
      case "--audio-dir": arguments.audioDirectory = value
      case "--speaker": arguments.speaker = value
      case "--output": arguments.output = value
      case "--rejections": arguments.rejectionsPath = value
      default: index -= 1
      }
      index += 2
    }
    return arguments
  }
}

let usage = """
Usage: kokoro-labels --transcripts <file> --audio-dir <dir> --speaker <name> \
--output <file> [--rejections <file>]

Emits StyleTTS2 manifest lines: <audio path>|<phonemes>|<speaker>

Transcripts may be Festival `( id "text" )`, tab-separated, or pipe-separated.
Phonemes come from this package's Hindi phonemizer rather than espeak, so the
fine-tuned model learns the phonemes inference will actually send it. Every
line is checked against the Kokoro vocabulary; anything that would be dropped
at tokenization is rejected rather than quietly trained on.
"""

let arguments = Arguments.parse(Array(CommandLine.arguments.dropFirst()))
guard let transcriptsPath = arguments.transcripts,
      let audioDirectory = arguments.audioDirectory,
      let speaker = arguments.speaker,
      let outputPath = arguments.output
else {
  print(usage)
  exit(2)
}

do {
  let contents = try String(contentsOfFile: transcriptsPath, encoding: .utf8)
  let entries = TranscriptFile.parse(contents)
  guard !entries.isEmpty else {
    FileHandle.standardError.write(Data("No transcripts parsed from \(transcriptsPath)\n".utf8))
    exit(1)
  }

  let report = try HindiTrainingLabels.export(
    entries: entries,
    speaker: speaker,
    audioDirectory: audioDirectory
  )

  try report.manifest.write(toFile: outputPath, atomically: true, encoding: .utf8)
  print("read \(entries.count) transcripts from \(transcriptsPath)")
  print(report.summary)
  print("manifest -> \(outputPath)")

  if let rejectionsPath = arguments.rejectionsPath, !report.rejections.isEmpty {
    let lines = report.rejections.map { "\($0.id)\t\($0.reason.rawValue)\t\($0.detail)" }
    try lines.joined(separator: "\n").write(
      toFile: rejectionsPath, atomically: true, encoding: .utf8
    )
    print("rejections -> \(rejectionsPath)")
  } else if !report.rejections.isEmpty {
    print("(pass --rejections <file> to write the rejected clips out for review)")
  }
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
