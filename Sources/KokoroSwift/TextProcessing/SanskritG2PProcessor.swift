import Foundation
import MLXUtilsLibrary

/// Kokoro's Sanskrit front end.
///
/// Devanagari goes to `SanskritPhonemizer`. Anything else is dropped with a
/// warning rather than guessed at: Classical Sanskrit recitation has no Latin
/// and no digits in it, and there is no defensible way to speak an English
/// word in a Sanskrit voice. This is a deliberate difference from
/// `HindiG2PProcessor`, which mixes scripts because Hindi news does.
///
/// The Hindi engine is not reachable from here, by construction — no schwa
/// deletion, no lexical overrides, no `kʃ`/`ɡj` conjunct readings, no number
/// expansion. See §7 of the brief.
final class SanskritG2PProcessor: G2PProcessor {
  private var configured = false

  /// The disputed rules, so a caller can hear an alternative without editing
  /// the phonemizer. Defaults are argued for in docs/SANSKRIT_G2P_RESEARCH.md.
  var options: SanskritOptions = .default

  func setLanguage(_ language: Language) throws {
    guard language == .sa else { throw G2PProcessorError.unsupportedLanguage }
    configured = true
  }

  /// - Returns: the phoneme string, and `nil` tokens.
  ///
  /// Token timestamps come from Misaki's `MToken` array, which only the
  /// English path produces; `HindiG2PProcessor` returns `nil` here for the
  /// same reason. `KokoroTTS` handles that — it predicts timestamps only
  /// `if let tokenArray` — so returning `nil` leaves every other timing path
  /// working. The mapping a future highlighting feature needs is preserved
  /// instead on `SanskritAkshara.sourceOffsets`, which survives the whole
  /// pipeline on `SanskritPhonemizer.Result.units`.
  func process(input: String) throws -> (String, [MToken]?) {
    guard configured else { throw G2PProcessorError.processorNotInitialized }
    return (SanskritPhonemizer.phonemize(input, options: options), nil)
  }
}
