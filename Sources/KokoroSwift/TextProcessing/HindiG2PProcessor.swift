#if canImport(MisakiSwift)

import Foundation
import MLXUtilsLibrary

/// Native Hindi front end for Kokoro. Devanagari uses the deterministic Hindi
/// phonemizer while embedded Latin names use the local Misaki English engine.
final class HindiG2PProcessor: G2PProcessor {
  private var english: MisakiG2PProcessor?
  private var isInitialized = false

  func setLanguage(_ language: Language) throws {
    guard language == .hi else {
      throw G2PProcessorError.unsupportedLanguage
    }
    isInitialized = true
  }

  func process(input: String) throws -> (String, [MToken]?) {
    guard isInitialized else {
      throw G2PProcessorError.processorNotInitialized
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
        rendered = try processEnglish(run)
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

  private func processEnglish(_ input: String) throws -> String {
    let processor: MisakiG2PProcessor
    if let english {
      processor = english
    } else {
      let newProcessor = MisakiG2PProcessor()
      try newProcessor.setLanguage(.enUS)
      english = newProcessor
      processor = newProcessor
    }
    return try processor.process(input: input).0
  }
}

#endif
