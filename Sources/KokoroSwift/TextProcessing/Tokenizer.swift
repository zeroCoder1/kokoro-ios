//
//  Kokoro-tts-lib
//
import Foundation

/// Utility class for tokenizing the phonemized text.
/// Phonemize the text first before calling this method.
/// Returns tokenized array that can then be passed to TTS system.
final class Tokenizer {
  /// Private constructor to prevent instantiation.
  private init() {}

  /// Tokenize the phonemized text.
  /// - Parameters:
  ///   - phonemizedText: Phonemized text to tokenize
  /// - Returns: Tokenized array that can then be passed to TTS system
  static func tokenize(phonemizedText text: String) -> [Int] {
    guard let vocab = KokoroConfig.config?.vocab else { return [] }
    // Kokoro's vocabulary is made of Unicode scalar tokens. Swift `Character`
    // iteration combines a vowel and its nasalization mark into one grapheme
    // (for example `ẽ`), which is not a vocabulary entry and was silently
    // dropping the complete vowel. Scalar iteration preserves both tokens.
    return text.unicodeScalars.compactMap { scalar in
      guard let id = vocab[String(scalar)] else {
        // Release behaviour is unchanged: an unknown scalar is still dropped.
        // The debug warning is so a future phonemizer mistake surfaces here
        // instead of vanishing silently into a shorter token stream.
        #if DEBUG
        print("[Tokenizer] OOV phoneme U+\(String(format: "%04X", scalar.value)) '\(scalar)'")
        #endif
        return nil
      }
      return id
    }
  }
}
