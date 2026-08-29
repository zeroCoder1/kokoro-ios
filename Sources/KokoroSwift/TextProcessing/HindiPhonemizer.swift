import Foundation

/// A native, deterministic Hindi phonemizer designed for Kokoro's published
/// IPA vocabulary. It deliberately contains no eSpeak code or data. The rules
/// model Hindi aksharas, internal and final schwa deletion, consonant clusters,
/// and syllable weight so the model receives speech sounds rather than a
/// letter-by-letter Sanskrit-style reading.
enum HindiPhonemizer {
  private struct Akshara {
    var onset: String
    var vowel: String?
    var hasInherentSchwa = false
    var nasalized = false
    var coda = ""

    var isVocalic: Bool { vowel != nil }
  }

  private static let independentVowels: [UnicodeScalar: String] = [
    "ऄ": "ə", "अ": "ə", "आ": "aː", "इ": "ɪ", "ई": "iː",
    "उ": "ʊ", "ऊ": "uː", "ऋ": "ɾɪ", "ॠ": "ɾiː", "ऌ": "lɪ",
    "ॡ": "liː", "ऍ": "ɛ", "ऎ": "e", "ए": "eː", "ऐ": "ɛː",
    "ऑ": "ɔ", "ऒ": "o", "ओ": "oː", "औ": "ɔː", "ॲ": "ɛ",
  ]

  private static let vowelSigns: [UnicodeScalar: String] = [
    "ा": "aː", "ि": "ɪ", "ी": "iː", "ु": "ʊ", "ू": "uː", "ृ": "ɾɪ",
    "ॄ": "ɾiː", "ॢ": "lɪ", "ॣ": "liː", "ॅ": "ɛ", "ॆ": "e",
    "े": "eː", "ै": "ɛː", "ॉ": "ɔ", "ॊ": "o", "ो": "oː",
    "ौ": "ɔː",
  ]

  /// These values follow the Hindi eSpeak IPA stream used to train Kokoro,
  /// rather than substituting similar English phonemes. In particular,
  /// Hindi च/छ and ज/झ are palatal stops (`c`/`ɟ`), while the dotted
  /// retroflex consonants are the flap `ɽ` and its aspirate `ɽʰ`.
  /// Those are real Kokoro tokens; eSpeak's ASCII mnemonics `r.`/`r.h` are
  /// not, and the `.` in them was tokenized as a mid-word sentence break.
  private static let consonants: [UnicodeScalar: String] = [
    "क": "k", "ख": "kʰ", "ग": "ɡ", "घ": "ɡʰ", "ङ": "ŋ",
    "च": "c", "छ": "cʰ", "ज": "ɟ", "झ": "ɟʰ", "ञ": "ɲ",
    "ट": "ʈ", "ठ": "ʈʰ", "ड": "ɖ", "ढ": "ɖʰ", "ण": "ɳ",
    "त": "t", "थ": "tʰ", "द": "d", "ध": "dʰ", "न": "n",
    "प": "p", "फ": "pʰ", "ब": "b", "भ": "bʰ", "म": "m",
    "य": "j", "र": "ɾ", "ल": "l", "व": "ʋ", "श": "ʃ", "ष": "ʂ",
    "स": "s", "ह": "h", "ऩ": "n", "ऱ": "ɾ", "ळ": "l", "ऴ": "l",
    "क़": "q", "ख़": "x", "ग़": "ɣ", "ज़": "z", "ड़": "ɽ", "ढ़": "ɽʰ",
    "फ़": "f", "य़": "j",
  ]

  private static let nuktaConsonants: [UnicodeScalar: String] = [
    "क": "q", "ख": "x", "ग": "ɣ", "ज": "z", "ड": "ɽ", "ढ": "ɽʰ",
    "फ": "f", "य": "j",
  ]

  /// High-frequency grammatical words are naturally unstressed in connected
  /// Hindi. Stressing every short postposition was a major source of choppy,
  /// synthetic delivery.
  private static let unstressedWords: Set<String> = [
    "और", "का", "की", "के", "को", "से", "पर", "ने", "तक", "तो",
    "ही", "भी", "वह", "ये", "वे", "है", "हैं", "था", "थी", "थे",
    "मैं", "हम", "आप", "तुम", "मुझे", "हमें", "उसे", "उन्हें", "कि", "जो",
    "जिस", "जिसे", "जिसका", "जिसकी", "जिसके", "रहा", "रही", "रहे", "हो",
  ]

  /// Small, independent corrections for very common words where spelling
  /// alone does not expose the learned stress pattern reliably. These are
  /// authored phonemes, not copied eSpeak rules or data.
  private static let pronunciationOverrides: [String: String] = [
    "दुनिया": "dˈʊnɪjˌaː",
    // Kokoro needs the learned stress marker to hold these short words
    // clearly; the generic unstressed path reduced or swallowed their vowel.
    "यह": "jˈʌh",
    "मैं": "mˈɛ\u{0303}ː",
    "में": "mˈe\u{0303}ː",
    "मे": "mˈeː",
    // Treat both common spellings as the same three-syllable place name.
    // Generic anusvara assimilation reduced मुंबई to a clipped /mumbiː/.
    "मुंबई": "mˈʊmbəˌi",
    "मुम्बई": "mˈʊmbəˌi",
    "ॐ": "ˈoːm",
  ]

  /// Orthography alone does not expose morpheme boundaries, yet those
  /// boundaries decide whether an internal schwa survives. Keeping this list
  /// deliberately small fixes common news vocabulary without turning the G2P
  /// into an unbounded dictionary or changing unknown-word behaviour.
  private static let compoundWords: [String: [String]] = [
    "प्रधानमंत्री": ["प्रधान", "मंत्री"],
    "मुख्यमंत्री": ["मुख्य", "मंत्री"],
    "राष्ट्रपति": ["राष्ट्र", "पति"],
    "उपराष्ट्रपति": ["उप", "राष्ट्रपति"],
    "लोकसभा": ["लोक", "सभा"],
    "राज्यसभा": ["राज्य", "सभा"],
    "विधानसभा": ["विधान", "सभा"],
  ]

  /// Hindi publishing commonly omits the nukta from Persian and English
  /// loanwords even though speakers retain /f/. This deliberately small news
  /// lexicon restores that sound without turning native फल, फूल or फिर into
  /// /f/ words. Stems cover ordinary inflections such as फैसले and फिल्मों.
  private static let labiodentalFStems = [
    "फैसल", "फोन", "फिल्म", "फोटो", "फाइल", "फाइनल", "फाइनेंस",
    "फेसबुक", "फीस", "फीफा", "फर्ज", "फर्जी", "फंड", "फॉर्म",
    "फ्रांस", "फ्रेंच", "फौज", "फायद", "फैक्टर", "फैक्टरी",
    "फार्म", "फारसी", "फरवरी", "फैशन", "फर्नीचर", "फसल",
    "फतवा", "फरार", "अफसर", "ऑफिस", "कॉफी", "सॉफ्ट", "टॉफी",
  ]

  static func phonemize(_ text: String) -> String {
    let normalized = text.precomposedStringWithCanonicalMapping
      .replacingOccurrences(of: "॥", with: ".")
      .replacingOccurrences(of: "।", with: ".")
    var result: [String] = []
    var word = ""

    func flushWord() {
      guard !word.isEmpty else { return }
      let phonemes = phonemizeWord(word)
      if !phonemes.isEmpty { result.append(phonemes) }
      word.removeAll(keepingCapacity: true)
    }

    for character in normalized {
      if character.unicodeScalars.allSatisfy({ isHindiWordScalar($0) }) {
        word.append(character)
      } else {
        flushWord()
        if character.isPunctuation {
          // Attach punctuation to the phoneme before it. Joining it as its own
          // element left a space in front of it, and that space is token 16 —
          // a pause the model never saw before a sentence break in training.
          if result.isEmpty {
            result.append(String(character))
          } else {
            result[result.count - 1].append(character)
          }
        }
      }
    }
    flushWord()
    return result.joined(separator: " ")
  }

  private static func phonemizeWord(_ word: String) -> String {
    if let pronunciation = pronunciationOverrides[word] { return pronunciation }
    if let components = compoundWords[word] {
      return components.map(phonemizeWord).joined(separator: " ")
    }

    // Join controls change glyph shaping, not pronunciation. Removing them
    // also lets the conjunct recognizer handle both क्ष and क्‍ष identically.
    let scalars = Array(word.unicodeScalars.filter {
      $0.value != 0x200C && $0.value != 0x200D
    })
    // Compare scalars because a following vowel sign belongs to the same Swift
    // grapheme as the stem's final consonant ("फैसल" is therefore not a
    // Character-prefix of "फैसला").
    let usesLabiodentalF = labiodentalFStems.contains {
      word.unicodeScalars.starts(with: $0.unicodeScalars)
    }
    var units: [Akshara] = []
    var index = 0

    while index < scalars.count {
      let scalar = scalars[index]
      if let vowel = independentVowels[scalar] {
        units.append(Akshara(onset: "", vowel: vowel))
        index += 1
        continue
      }

      guard var onset = consonants[scalar] else {
        applyModifier(scalar, to: &units, following: nextConsonant(in: scalars, after: index))
        index += 1
        continue
      }

      if scalar == "फ", usesLabiodentalF {
        onset = "f"
      }

      if index + 1 < scalars.count, scalars[index + 1] == "़" {
        onset = nuktaConsonants[scalar] ?? onset
        index += 1
      }

      // Modern Hindi pronounces these inherited conjuncts as /kʃ/ and /ɡj/.
      if index + 2 < scalars.count, scalars[index + 1] == "्" {
        let joined = scalars[index + 2]
        if scalar == "क", joined == "ष" {
          onset = "kʃ"
          index += 2
        } else if scalar == "ज", joined == "ञ" {
          onset = "ɡj"
          index += 2
        }
      }

      var unit = Akshara(onset: onset, vowel: "ə", hasInherentSchwa: true)
      if index + 1 < scalars.count {
        let next = scalars[index + 1]
        if next == "्" {
          unit.vowel = nil
          unit.hasInherentSchwa = false
          index += 1
        } else if let vowel = vowelSigns[next] {
          unit.vowel = vowel
          unit.hasInherentSchwa = false
          index += 1
        }
      }
      units.append(unit)
      index += 1
    }

    collapseGemination(in: &units)
    applySchwaDeletion(to: &units)
    applyContextualVowels(to: &units)
    let stressIndex = unstressedWords.contains(word) ? nil : primaryStressIndex(in: units)
    let secondaryStress = stressIndex.map {
      secondaryStressIndices(in: units, primary: $0)
    } ?? []

    return units.enumerated().map { index, unit in
      var vowel = unit.vowel ?? ""
      if index == stressIndex, vowel == "ə" { vowel = "ʌ" }
      let stress: String
      if index == stressIndex, unit.isVocalic {
        stress = "ˈ"
      } else if secondaryStress.contains(index), unit.isVocalic {
        stress = "ˌ"
      } else {
        stress = ""
      }
      if unit.nasalized && unit.isVocalic {
        if vowel.hasSuffix("ː") {
          vowel.removeLast()
          vowel += "\u{0303}ː"
        } else {
          vowel += "\u{0303}"
        }
      }
      // eSpeak's Hindi IPA places the stress token immediately before the
      // vowel (for example `nəmˈʌsteː`), which is the sequence Kokoro learned.
      return unit.onset + stress + vowel + unit.coda
    }.joined()
  }

  private static func applyModifier(
    _ scalar: UnicodeScalar,
    to units: inout [Akshara],
    following: UnicodeScalar?
  ) {
    guard !units.isEmpty else { return }
    switch scalar {
    case "ं":
      if let nasal = assimilatedNasal(before: following) {
        units[units.count - 1].coda += nasal
      } else {
        units[units.count - 1].nasalized = true
      }
    case "ँ":
      units[units.count - 1].nasalized = true
    case "ः":
      units[units.count - 1].coda += "h"
    case "ऽ":
      if let vowel = units[units.count - 1].vowel, !vowel.hasSuffix("ː") {
        units[units.count - 1].vowel = vowel + "ː"
      }
    default:
      break
    }
  }

  private static func collapseGemination(in units: inout [Akshara]) {
    guard units.count > 1 else { return }
    var index = 0
    while index + 1 < units.count {
      if units[index].vowel == nil,
         units[index].onset == units[index + 1].onset,
         !units[index].onset.isEmpty {
        units[index + 1].onset += "ː"
        units.remove(at: index)
      } else {
        index += 1
      }
    }
  }

  /// Hindi deletes a written inherent schwa at word end and often internally
  /// before a legal two-consonant cluster. Blocking three-consonant clusters
  /// keeps words such as “नमस्ते” from being over-compressed.
  private static func applySchwaDeletion(to units: inout [Akshara]) {
    guard units.count > 1 else { return }
    let final = units.count - 1
    // A final य that completes a written conjunct normally keeps its schwa:
    // मुख्य /mukʰjə/, योग्य /joːɡjə/, वाक्य /ʋaːkjə/. Treating it like an
    // ordinary final consonant produces the clipped pronunciation users hear.
    let finalCompletesYaConjunct = units[final].onset == "j"
      && units[final - 1].vowel == nil
    if units[final].hasInherentSchwa, !finalCompletesYaConjunct {
      units[units.count - 1].vowel = nil
      units[units.count - 1].hasInherentSchwa = false
    }

    guard units.count > 2 else { return }
    for candidate in stride(from: units.count - 2, through: 1, by: -1) {
      guard units[candidate].hasInherentSchwa,
            units[..<candidate].contains(where: \.isVocalic)
      else { continue }

      // The inherent vowel after an aspirated flap stays audible before
      // another consonant in words such as पढ़ना, बढ़ना and गढ़वाल.
      // Deleting it makes Kokoro receive the clipped sequence `ɽʰn`/`ɽʰʋ`.
      if units[candidate].onset == "ɽʰ" { continue }

      // Preserve the vowel after an explicit conjunct. It is required in
      // words such as मुख्य, विश्व and स्वतंत्रता. The old broad deletion
      // rule flattened these into unnatural three-consonant runs.
      if units[candidate - 1].vowel == nil { continue }

      var next = candidate + 1
      var consonantCount = 1
      while next < units.count, units[next].vowel == nil {
        consonantCount += 1
        next += 1
      }
      guard next < units.count else { continue }
      consonantCount += 1
      guard consonantCount <= 2 else { continue }

      units[candidate].vowel = nil
      units[candidate].hasInherentSchwa = false
    }
  }

  /// Delhi Hindi fronts schwa before an `h` whose own schwa was deleted, as
  /// in कहना, रहना and पहला. Applying this after deletion keeps the rule
  /// narrow and avoids changing words such as बहुत, शहर and महिला.
  private static func applyContextualVowels(to units: inout [Akshara]) {
    guard units.count > 1 else { return }
    for index in 0 ..< units.count - 1 where units[index].vowel == "ə" {
      let following = units[index + 1]
      if following.onset == "h", following.vowel == nil {
        units[index].vowel = "ɛ"
      }
    }
  }

  private static func primaryStressIndex(in units: [Akshara]) -> Int? {
    let vocalic = units.indices.filter { units[$0].isVocalic }
    guard !vocalic.isEmpty else { return nil }
    if vocalic.count == 1 { return vocalic[0] }

    let weighted = vocalic.map { ($0, syllableWeight(at: $0, in: units)) }
    if let superheavy = weighted.last(where: { $0.1 >= 3 }) { return superheavy.0 }

    let nonfinal = weighted.dropLast()
    let heaviest = nonfinal.map(\.1).max() ?? 1
    // With no heavier syllable to break the tie, connected Hindi favours the
    // earlier foot. Choosing the last light syllable made words such as
    // “दुनिया” and “महिला” sound clipped and foreign.
    if heaviest == 1 { return nonfinal.first?.0 ?? vocalic[0] }
    return nonfinal.last(where: { $0.1 == heaviest })?.0 ?? vocalic[0]
  }

  private static func secondaryStressIndices(
    in units: [Akshara],
    primary: Int
  ) -> Set<Int> {
    let vocalic = units.indices.filter { units[$0].isVocalic }
    guard vocalic.count >= 3,
          let primaryPosition = vocalic.firstIndex(of: primary),
          let final = vocalic.last,
          primaryPosition + 1 < vocalic.count - 1,
          units[final].vowel?.contains("ː") == true
    else { return [] }
    return [final]
  }

  private static func syllableWeight(at index: Int, in units: [Akshara]) -> Int {
    guard let vowel = units[index].vowel else { return 0 }
    var weight = vowel.contains("ː") ? 2 : 1
    if units[index].nasalized || !units[index].coda.isEmpty { weight += 1 }

    let following = index + 1
    if following < units.count, units[following].vowel == nil {
      weight += 1
    }
    return min(weight, 3)
  }

  private static func nextConsonant(
    in scalars: [UnicodeScalar],
    after index: Int
  ) -> UnicodeScalar? {
    scalars.dropFirst(index + 1).first(where: { consonants[$0] != nil })
  }

  private static func assimilatedNasal(before scalar: UnicodeScalar?) -> String? {
    guard let scalar else { return nil }
    switch scalar.value {
    case 0x0915...0x0919: return "ŋ"
    case 0x091A...0x091E: return "ɲ"
    case 0x091F...0x0923: return "ɳ"
    case 0x0924...0x0928: return "n"
    case 0x092A...0x092E: return "m"
    default: return nil
    }
  }

  private static func isDevanagari(_ scalar: UnicodeScalar) -> Bool {
    (0x0900...0x097F).contains(scalar.value)
  }

  private static func isHindiWordScalar(_ scalar: UnicodeScalar) -> Bool {
    isDevanagari(scalar) || scalar.value == 0x200C || scalar.value == 0x200D
  }
}
