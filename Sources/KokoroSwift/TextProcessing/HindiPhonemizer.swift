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
    /// Set when a virama is written, as opposed to an inherent schwa that
    /// deletion removed later. espeak distinguishes the two for र.
    var hasWrittenVirama = false
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
  /// dotted retroflex consonants are the stops `ɖ` and `ɖʰ`, as ड and ढ are.
  ///
  /// Settled by ear, after three mappings that read well on paper. Speakers
  /// hear this letter as d-like rather than r-like: बड़ा is "bada" against
  /// बरा "bara", करोड़ ends like "road", and पढ़ना is "padhna". `ɖ` and `ɖʰ`
  /// give exactly that, and are among the best-trained consonants in the voice
  /// because ड and ढ are common.
  ///
  /// What was tried before, and why each failed: `ɽ` is the accurate IPA, but
  /// espeak emits it for no language Kokoro supports, so the embedding is
  /// untrained and it was heard as nasalization. A literal `r` is what espeak's
  /// `r.` mnemonic leaves in the labels, but only ever followed by the `.`, and
  /// without it the model renders something else. `ɾ` is the well-trained
  /// rhotic, but it is a rhotic, and this letter is not heard as one — it also
  /// merged ड़ with र, which Hindi distinguishes.
  ///
  /// The merger that remains is ड़ with ड, which costs far less: ड़ never
  /// begins a word, so the pair barely contrasts outside spelling.
  private static let consonants: [UnicodeScalar: String] = [
    "क": "k", "ख": "kʰ", "ग": "ɡ", "घ": "ɡʰ", "ङ": "ŋ",
    "च": "c", "छ": "cʰ", "ज": "ɟ", "झ": "ɟʰ", "ञ": "ɲ",
    "ट": "ʈ", "ठ": "ʈʰ", "ड": "ɖ", "ढ": "ɖʰ", "ण": "ɳ",
    "त": "t", "थ": "tʰ", "द": "d", "ध": "dʰ", "न": "n",
    "प": "p", "फ": "pʰ", "ब": "b", "भ": "bʰ", "म": "m",
    "य": "j", "र": "ɾ", "ल": "l", "व": "ʋ", "श": "ʃ", "ष": "ʂ",
    "स": "s", "ह": "h", "ऩ": "n", "ऱ": "ɾ", "ळ": "l", "ऴ": "l",
    "क़": "q", "ख़": "x", "ग़": "ɣ", "ज़": "z", "ड़": "ɖ", "ढ़": "ɖʰ",
    "फ़": "f", "य़": "j",
  ]

  private static let nuktaConsonants: [UnicodeScalar: String] = [
    "क": "q", "ख": "x", "ग": "ɣ", "ज": "z", "ड": "ɖ", "ढ": "ɖʰ",
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
  /// Words the general rules cannot reach. Deliberately tiny: a systematic
  /// failure means a rule is wrong, and belongs in the rule rather than here.
  /// Each entry says why normal G2P cannot handle it.
  ///
  /// Six entries were removed once the anusvara rules were corrected —
  /// में, मे, मुंबई, मुम्बई, दुनिया and यह are all produced correctly by the
  /// general path now, and are covered by regression tests instead.
  private static let pronunciationOverrides: [String: String] = [
    // Not a spelling the akshara parser can read: ॐ is a single ligature
    // scalar with no consonant or vowel parts, so without an entry it
    // phonemizes to nothing at all.
    "ॐ": "ˈo\u{0303}m",
    // MODEL_COMPATIBILITY. espeak deletes this schwa and so does our rule,
    // but the current voices render the stranded ɳ as nasalization on the
    // vowel before it, so the name was heard as वारांसी. Reported by ear.
    // Revisit if a Hindi voice is ever trained on labels from this
    // phonemizer, where the deleted form may render correctly.
    "वाराणसी": "ʋaːɾˈaːɳəsi",
    // A one-syllable function word that still carries stress in espeak, and
    // loses its vowel entirely without it. `unstressedWords` is right for
    // the postpositions but wrong for this pronoun.
    "मैं": "mˈɛ\u{0303}",
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

  /// Acronyms are routinely written out in Devanagari in Hindi copy. Phonemized
  /// as one word they receive a single primary stress across every letter and
  /// smear together; a newsreader says each letter name separately. Splitting
  /// them also restores the nukta on एफ़, which is /f/ — the nukta-less एफ that
  /// most copy actually uses was read as /pʰ/, so एनडीआरएफ ended in "eph".
  /// Add a row to extend this.
  private static let devanagariAcronyms: [String: [String]] = [
    "एनडीआरएफ": ["एन", "डी", "आर", "एफ़"],
    "एसडीआरएफ": ["एस", "डी", "आर", "एफ़"],
    "आईएएफ": ["आई", "ए", "एफ़"],
    "बीएसएफ": ["बी", "एस", "एफ़"],
    "सीआरपीएफ": ["सी", "आर", "पी", "एफ़"],
    "आईटीबीपी": ["आई", "टी", "बी", "पी"],
    "बीजेपी": ["बी", "जे", "पी"],
    "सीबीआई": ["सी", "बी", "आई"],
    "एनआईए": ["एन", "आई", "ए"],
    "आरबीआई": ["आर", "बी", "आई"],
    "एसबीआई": ["एस", "बी", "आई"],
    "जीएसटी": ["जी", "एस", "टी"],
    "यूपीआई": ["यू", "पी", "आई"],
    "एटीएम": ["ए", "टी", "एम"],
    "आईपीएल": ["आई", "पी", "एल"],
    "एनडीए": ["एन", "डी", "ए"],
    "यूपीए": ["यू", "पी", "ए"],
    "एमएलए": ["एम", "एल", "ए"],
    "पीएम": ["पी", "एम"],
    "सीएम": ["सी", "एम"],
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

  /// Word-final long high vowels are written long but transcribed short.
  private static let finalHighVowels = ["iː": "i", "uː": "u"]

  /// What a vowel becomes when an anusvara or chandrabindu nasalizes it.
  ///
  /// Nasalization collapses length and tenses the lax vowels, so चांद is
  /// /cˈãd/ rather than /cãːd/, and नींद and बिंदु both give ĩ rather than
  /// ɪ̃. `eː` is the one vowel that keeps its length: केंद्र is /kˈẽːdɾə/.
  /// Appending a tilde to whatever was there produced ãː, ɪ̃ and ʊ̃, which
  /// espeak emits for no Hindi word and the voices were never trained on.
  private static let nasalVowels = [
    "aː": "a\u{0303}", "a": "a\u{0303}",
    "ɪ": "i\u{0303}", "iː": "i\u{0303}", "i": "i\u{0303}",
    "ʊ": "u\u{0303}", "uː": "u\u{0303}", "u": "u\u{0303}",
    "eː": "e\u{0303}ː", "e": "e\u{0303}",
    "ɛː": "ɛ\u{0303}", "ɛ": "ɛ\u{0303}",
    "oː": "o\u{0303}", "o": "o\u{0303}",
    "ɔː": "ɔ\u{0303}", "ɔ": "ɔ\u{0303}",
  ]

  /// The punctuation Kokoro actually has tokens for. Anything else is dropped
  /// rather than passed through: the tokenizer would discard it silently, and
  /// a training label built from it is rejected outright. Hyphens and en
  /// dashes are the ones that turn up in real Hindi copy.
  private static let emittablePunctuation: Set<Character> = [
    ";", ":", ",", ".", "!", "?", "—", "…", "\"", "(", ")", "\u{201C}", "\u{201D}",
  ]

  /// A hyphen written tight between two word characters joins them with no
  /// separator at all: espeak reads साथ-साथ as /sˈaːtʰsˈaːtʰ/. Spaced hyphens
  /// and en dashes are ordinary word breaks, and none of them is ever spoken.
  private static let joiningHyphen: Character = "-"

  static func phonemize(_ text: String) -> String {
    let normalized = text.precomposedStringWithCanonicalMapping
      .replacingOccurrences(of: "॥", with: ".")
      .replacingOccurrences(of: "।", with: ".")
    var result: [String] = []
    var word = ""

    func flushWord() {
      guard !word.isEmpty else { return }
      let phonemes = phonemizeWord(word)
      word.removeAll(keepingCapacity: true)
      guard !phonemes.isEmpty else { return }
      if joinToPrevious, !result.isEmpty {
        result[result.count - 1] += phonemes
        joinToPrevious = false
      } else {
        result.append(phonemes)
      }
    }

    let characters = Array(normalized)
    // Set when a tight hyphen has just been seen, so the word after it is
    // appended to the one before rather than separated by a space.
    var joinToPrevious = false

    func isWordCharacter(_ character: Character) -> Bool {
      character.unicodeScalars.allSatisfy { isHindiWordScalar($0) }
    }

    for (offset, character) in characters.enumerated() {
      if isWordCharacter(character) {
        word.append(character)
        continue
      }

      let hadPendingWord = !word.isEmpty
      flushWord()

      if character == joiningHyphen,
         hadPendingWord || joinToPrevious,
         offset + 1 < characters.count, isWordCharacter(characters[offset + 1]),
         offset > 0, isWordCharacter(characters[offset - 1]) {
        joinToPrevious = true
        continue
      }
      joinToPrevious = false

      // Attach punctuation to the phoneme before it. Joining it as its own
      // element left a space in front of it, and that space is token 16 —
      // a pause the model never saw before a sentence break in training.
      guard emittablePunctuation.contains(character) else { continue }
      if result.isEmpty {
        result.append(String(character))
      } else {
        result[result.count - 1].append(character)
      }
    }
    flushWord()
    return result.joined(separator: " ")
  }

  private static func phonemizeWord(_ word: String) -> String {
    if let pronunciation = pronunciationOverrides[word] { return pronunciation }
    if let components = compoundWords[word] ?? devanagariAcronyms[word] {
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
        // espeak opens a word written with अ on ʌ rather than ə, whether or
        // not the syllable carries stress: अदालत is /ʌdˈaːlət/, अस्पताल is
        // /ˌʌspətˈaːl/. Reading it as ə is why अंतर was heard as इंतर.
        let opensOnA = index == 0 && scalar == "अ"
        units.append(Akshara(onset: "", vowel: opensOnA ? "ʌ" : vowel))
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
          unit.hasWrittenVirama = true
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

    // Only a vowel that actually ends the word shortens. क़ानून keeps its long
    // /uː/ because a consonant follows it; पानी does not.
    let finalVowelIndex: Int? = {
      guard let last = units.indices.last, units[last].isVocalic,
            units[last].coda.isEmpty
      else { return nil }
      return last
    }()

    return units.enumerated().map { index, unit in
      var vowel = unit.vowel ?? ""
      if index == stressIndex, vowel == "ə" { vowel = "ʌ" }
      // espeak never ends a Hindi word on a long high vowel: पानी is
      // /pˈaːni/, भेजी is /bʰˈeːɟi/. Long aː and eː endings are untouched.
      if index == finalVowelIndex, let shortened = finalHighVowels[vowel] {
        vowel = shortened
      }
      // A written virama gives the trill; an inherent schwa that deletion
      // removed keeps the flap. कुर्सी is /kˈʊrsi/, सरकार is /sˌəɾkˈaːɾ/.
      let onset = unit.onset == "ɾ" && unit.hasWrittenVirama ? "r" : unit.onset
      let stress: String
      if index == stressIndex, unit.isVocalic {
        stress = "ˈ"
      } else if secondaryStress.contains(index), unit.isVocalic {
        stress = "ˌ"
      } else {
        stress = ""
      }
      if unit.nasalized && unit.isVocalic {
        if let nasalized = nasalVowels[vowel] {
          vowel = nasalized
        } else if vowel.hasSuffix("ː") {
          // Anything the table does not name keeps the older behaviour.
          vowel.removeLast()
          vowel += "\u{0303}ː"
        } else {
          vowel += "\u{0303}"
        }
      }
      // eSpeak's Hindi IPA places the stress token immediately before the
      // vowel (for example `nəmˈʌsteː`), which is the sequence Kokoro learned.
      return onset + stress + vowel + unit.coda
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
      // Which of the two realizations applies is decided by the vowel the
      // anusvara sits on, not by what follows it. On the short central vowel —
      // the inherent schwa, or a word-initial अ — it is a consonant nasal that
      // assimilates to the following place: संसद is /sˈʌnsəd/, संकट /sˈʌŋkəʈ/.
      // On any other vowel it nasalizes that vowel and adds no consonant, and
      // that holds even before a stop: दांत is /dˈãt/, सांप /sˈãp/, बिंदु
      // /bˈĩdʊ/. Reading every non-stop context as bare nasalization was why
      // संसद, संविधान, संस्कृति and the rest of the सं- news vocabulary lost
      // their nasal consonant.
      if carriesShortCentralVowel(units[units.count - 1]) {
        units[units.count - 1].coda += assimilatedNasal(before: following)
      } else {
        units[units.count - 1].nasalized = true
      }
    case "ँ":
      // The chandrabindu behaves like the anusvara: on a schwa it is still a
      // consonant, which is why अँधेरा is /ʌndʰˈeːɾaː/ and not /ə̃dʰeːɾaː/.
      if carriesShortCentralVowel(units[units.count - 1]) {
        units[units.count - 1].coda += assimilatedNasal(before: following)
      } else {
        units[units.count - 1].nasalized = true
      }
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
  ///
  /// The `h` has to be followed by something. In कहना it is, and the fronting
  /// is real; word-finally it is not, and applying it there turned आग्रह into
  /// /aːɡɾɛh/ — heard as आगरे. Words such as आग्रह, प्रवाह and उत्साह keep
  /// their schwa.
  private static func applyContextualVowels(to units: inout [Akshara]) {
    guard units.count > 2 else { return }
    for index in 0 ..< units.count - 2 where units[index].vowel == "ə" {
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

  /// True when the akshara's vowel is the short central one — the inherent
  /// schwa, or the `ʌ` a word-initial अ is read as. Only there does the
  /// anusvara surface as its own consonant.
  private static func carriesShortCentralVowel(_ unit: Akshara) -> Bool {
    unit.vowel == "ə" || unit.vowel == "ʌ"
  }

  /// The nasal an anusvara becomes, assimilated to the place of what follows.
  ///
  /// The five stop series are homorganic. य is palatal too, so संयुक्त is
  /// /səɲjˈʊkt/ rather than /sənjukt/. Everything else — the fricatives स श ष
  /// ह and the approximants र ल व — takes the dental n, which is what espeak
  /// produces and therefore what the current voices were trained on: संसद,
  /// संहार, संरचना, संलग्न, संवाद.
  private static func assimilatedNasal(before scalar: UnicodeScalar?) -> String {
    guard let scalar else { return "n" }
    switch scalar.value {
    case 0x0915...0x0919: return "ŋ"          // क ख ग घ ङ
    case 0x091A...0x091E: return "ɲ"          // च छ ज झ ञ
    case 0x091F...0x0923: return "ɳ"          // ट ठ ड ढ ण
    case 0x0924...0x0928: return "n"          // त थ द ध न
    case 0x092A...0x092E: return "m"          // प फ ब भ म
    case 0x092F:          return "ɲ"          // य, palatal like the च series
    default:              return "n"
    }
  }

  private static func isDevanagari(_ scalar: UnicodeScalar) -> Bool {
    (0x0900...0x097F).contains(scalar.value)
  }

  private static func isHindiWordScalar(_ scalar: UnicodeScalar) -> Bool {
    isDevanagari(scalar) || scalar.value == 0x200C || scalar.value == 0x200D
  }
}
