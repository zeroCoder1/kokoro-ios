import Foundation

/// Splits text into sentences, and groups them into chunks small enough to
/// synthesize.
///
/// Kokoro takes at most `KokoroTTS.Constants.maxTokenCount` tokens and throws
/// above it, so a bulletin of any length could not be synthesized at all. It
/// also decides its own pauses from the punctuation tokens, and on the Hindi
/// packs those come out short, so a headline runs straight into the sentence
/// after it. Synthesizing sentence groups separately gives the caller a real
/// pause to set.
enum SentenceChunker {
  /// Ends a sentence. `।` and `॥` are the Devanagari danda and double danda.
  private static let terminators: Set<Character> = [".", "!", "?", "।", "॥", "…"]

  /// Ends a phrase. Used only to break up a sentence that is too long on its
  /// own to fit in one chunk.
  private static let phraseBreaks: Set<Character> = [",", ";", ":", "—"]

  /// Splits `text` into sentences, keeping each terminator with the sentence it
  /// ends. Runs of terminators (`?!`) and a closing bracket or quote after one
  /// stay attached.
  static func sentences(in text: String) -> [String] {
    var sentences: [String] = []
    var current = ""

    func flush() {
      let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { sentences.append(trimmed) }
      current.removeAll(keepingCapacity: true)
    }

    let characters = Array(text)
    var index = 0
    while index < characters.count {
      let character = characters[index]
      current.append(character)
      index += 1
      guard terminators.contains(character) else { continue }

      // Absorb `?!`, `...`, and any closing quote or bracket that follows.
      while index < characters.count,
            terminators.contains(characters[index])
              || characters[index] == "\"" || characters[index] == "”"
              || characters[index] == ")" || characters[index] == "'" {
        current.append(characters[index])
        index += 1
      }
      flush()
    }
    flush()
    return sentences
  }

  /// Groups sentences into chunks that each stay within `maxTokens`.
  ///
  /// `tokenCount` reports how many tokens a candidate chunk would produce, so
  /// the budget is measured against real phonemes rather than characters. A
  /// sentence too long on its own is split at phrase breaks, and failing that
  /// at spaces.
  static func chunks(
    of text: String,
    maxTokens: Int,
    tokenCount: (String) throws -> Int
  ) rethrows -> [String] {
    var chunks: [String] = []
    var current = ""

    func flush() {
      let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { chunks.append(trimmed) }
      current.removeAll(keepingCapacity: true)
    }

    for sentence in sentences(in: text) {
      let joined = current.isEmpty ? sentence : current + " " + sentence
      if try tokenCount(joined) <= maxTokens {
        current = joined
        continue
      }
      // The sentence does not fit alongside what is already buffered.
      flush()
      if try tokenCount(sentence) <= maxTokens {
        current = sentence
      } else {
        chunks.append(contentsOf: try split(sentence, maxTokens: maxTokens, tokenCount: tokenCount))
      }
    }
    flush()
    return chunks
  }

  /// Breaks a single over-long sentence apart, preferring phrase punctuation
  /// and falling back to spaces.
  private static func split(
    _ sentence: String,
    maxTokens: Int,
    tokenCount: (String) throws -> Int
  ) rethrows -> [String] {
    var pieces: [String] = []
    var current = ""

    func flush() {
      let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { pieces.append(trimmed) }
      current.removeAll(keepingCapacity: true)
    }

    for unit in phrases(in: sentence) {
      let joined = current.isEmpty ? unit : current + " " + unit
      if try tokenCount(joined) <= maxTokens {
        current = joined
      } else {
        flush()
        current = unit
      }
    }
    flush()
    // A single unit longer than the budget is emitted as-is; the caller throws
    // on it rather than this silently dropping text.
    return pieces
  }

  /// Phrase-sized units: split at phrase punctuation, then at spaces.
  private static func phrases(in sentence: String) -> [String] {
    var units: [String] = []
    var current = ""
    for character in sentence {
      current.append(character)
      if phraseBreaks.contains(character) {
        units.append(current)
        current.removeAll(keepingCapacity: true)
      }
    }
    if !current.isEmpty { units.append(current) }

    return units.flatMap { unit -> [String] in
      let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return [] }
      return [trimmed]
    }
  }
}
