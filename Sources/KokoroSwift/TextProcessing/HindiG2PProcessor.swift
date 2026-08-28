#if canImport(MisakiSwift)

import Foundation
import MLXUtilsLibrary

/// Native bilingual front end for Kokoro. It lets one loaded TTS model switch
/// between English and Hindi; Devanagari uses the native Hindi phonemizer while
/// embedded Latin names and full English segments use the local Misaki engine.
final class HindiG2PProcessor: G2PProcessor {
  private var english: MisakiG2PProcessor?
  private var configuredEnglishLanguage: Language = .none
  private var activeLanguage: Language = .none

  func setLanguage(_ language: Language) throws {
    guard language == .hi || language == .enUS || language == .enGB else {
      throw G2PProcessorError.unsupportedLanguage
    }
    activeLanguage = language
  }

  func process(input: String) throws -> (String, [MToken]?) {
    guard activeLanguage != .none else {
      throw G2PProcessorError.processorNotInitialized
    }
    if activeLanguage == .enUS || activeLanguage == .enGB {
      return try processEnglish(input, language: activeLanguage)
    }

    var output = ""
    var run = ""
    var runIsDevanagari: Bool?

    func appendRun() throws {
      guard !run.isEmpty else { return }
      let rendered: String
      if runIsDevanagari == true {
        rendered = HindiPhonemizer.phonemize(run)
      } else {
        rendered = try processEnglish(run, language: .enUS).0
      }
      if !output.isEmpty, !output.hasSuffix(" "), !rendered.hasPrefix(" ") {
        output.append(" ")
      }
      output.append(rendered)
      run.removeAll(keepingCapacity: true)
    }

    for character in input {
      let isDevanagari = character.unicodeScalars.contains {
        (0x0900...0x097F).contains($0.value)
      }
      let isNeutral = character.unicodeScalars.allSatisfy {
        CharacterSet.whitespacesAndNewlines.contains($0)
          || CharacterSet.punctuationCharacters.contains($0)
      }
      if isNeutral || runIsDevanagari == nil || runIsDevanagari == isDevanagari {
        run.append(character)
        if !isNeutral { runIsDevanagari = isDevanagari }
      } else {
        try appendRun()
        runIsDevanagari = isDevanagari
        run.append(character)
      }
    }
    try appendRun()
    return (output.replacingOccurrences(of: "  ", with: " "), nil)
  }

  private func processEnglish(
    _ input: String,
    language: Language
  ) throws -> (String, [MToken]?) {
    let processor: MisakiG2PProcessor
    if let english, configuredEnglishLanguage == language {
      processor = english
    } else {
      let newProcessor = MisakiG2PProcessor()
      try newProcessor.setLanguage(language)
      english = newProcessor
      configuredEnglishLanguage = language
      processor = newProcessor
    }
    return try processor.process(input: input)
  }
}

#endif
