import Foundation

/// Turns canonical Sanskrit phonemes into the IPA Kokoro was trained on.
///
/// This is the only layer that knows Kokoro exists. Everything above it is
/// model-independent, so retargeting a different acoustic model means writing
/// a new mapper and leaving the phonology alone.
///
/// Two rules govern this file.
///
/// **Nothing is spelled with a token the model does not have.** Kokoro's
/// vocabulary is 114 entries and `Tokenizer` maps one Unicode scalar to one
/// token, dropping anything unknown *silently*. A sound we cannot spell would
/// not degrade, it would vanish and take its syllable with it. So every long
/// vowel is written `a` + `ː`, every aspirate `k` + `ʰ`, every nasal vowel
/// `a` + `◌̃` — sequences of tokens the base weights actually trained.
/// IndicVoice added `aː`, `kʰ` and `ã` as single tokens, but it retrained the
/// model to do it; on stock weights those rows are untrained noise.
///
/// **Nothing is approximated silently.** Where Kokoro cannot say the real
/// thing, the nearest sound goes out *and* a warning is recorded naming the
/// substitution. See §30 of the brief and `docs/SANSKRIT_KOKORO_COMPATIBILITY.md`.
enum SanskritKokoroMapper {
  struct Result {
    var phonemes: String = ""
    var warnings: [SanskritWarning] = []
  }

  /// Combining tilde, Kokoro token 17. `Tokenizer` iterates Unicode scalars
  /// rather than Characters precisely so this survives as its own token
  /// instead of being folded into the vowel as one unmappable grapheme.
  private static let nasalMark = "\u{0303}"
  private static let lengthMark = "ː"

  static func map(
    _ segments: [SanskritPhonology.Segment],
    options: SanskritOptions = .default
  ) -> Result {
    var result = Result()
    var seenApproximations: Set<String> = []

    // Prominence, when asked for. Sanskrit has no stress accent, so this is an
    // accommodation to Kokoro and belongs here rather than in the phonology —
    // see SanskritOptions.markStressOnHeavySyllables for the measurements and
    // for why it is off by default.
    let stressed: Set<Int> = options.markStressOnHeavySyllables
      ? stressedVowelIndices(in: segments)
      : []
    var vowelIndex = -1

    /// One warning per distinct approximation per line, not one per syllable.
    func warnOnce(_ warning: SanskritWarning) {
      guard seenApproximations.insert(warning.text).inserted else { return }
      result.warnings.append(warning)
    }

    for segment in segments {
      switch segment {
      case let .vowel(vowel, nasalized):
        vowelIndex += 1
        let (ipa, warning) = self.ipa(for: vowel, options: options)
        if let warning { warnOnce(warning) }
        // eSpeak places the stress token immediately before the vowel, which
        // is the sequence Kokoro learned.
        if stressed.contains(vowelIndex) { result.phonemes += "ˈ" }
        result.phonemes += nasalize(ipa, if: nasalized)

      case let .consonant(consonant):
        let (ipa, warning) = self.ipa(for: consonant, options: options)
        if let warning { warnOnce(warning) }
        result.phonemes += ipa

      case let .boundary(boundary):
        result.phonemes += self.ipa(for: boundary)
      }
    }

    result.phonemes = tidied(result.phonemes)
    return result
  }

  // MARK: Prominence

  /// Which vowels take `ˈ`, counted over the whole segment stream.
  ///
  /// One per orthographic word, by the weight rule Western Sanskritists use:
  /// the penultimate syllable if it is heavy, otherwise the antepenultimate,
  /// otherwise the first. A syllable is heavy when its vowel is long or when
  /// more than one consonant follows it before the next vowel.
  ///
  /// Only reachable when `markStressOnHeavySyllables` is set. Sanskrit has no
  /// stress accent and the default is off.
  private static func stressedVowelIndices(
    in segments: [SanskritPhonology.Segment]
  ) -> Set<Int> {
    var stressed: Set<Int> = []
    // (index into the vowel numbering, whether the syllable is heavy)
    var word: [(index: Int, heavy: Bool)] = []
    var vowelIndex = -1
    var consonantsSinceVowel = 0

    func closeWord() {
      defer { word.removeAll(keepingCapacity: true) }
      guard !word.isEmpty else { return }
      if word.count == 1 { stressed.insert(word[0].index); return }
      let penult = word[word.count - 2]
      if penult.heavy {
        stressed.insert(penult.index)
      } else if word.count >= 3 {
        stressed.insert(word[word.count - 3].index)
      } else {
        stressed.insert(word[0].index)
      }
    }

    /// A vowel is heavy if it is long, or if a cluster closes its syllable.
    func settleWeight() {
      guard let last = word.indices.last else { return }
      if consonantsSinceVowel >= 2 { word[last].heavy = true }
      consonantsSinceVowel = 0
    }

    for segment in segments {
      switch segment {
      case let .vowel(vowel, _):
        settleWeight()
        vowelIndex += 1
        word.append((vowelIndex, vowel.isLong))
      case .consonant:
        consonantsSinceVowel += 1
      case let .boundary(boundary):
        settleWeight()
        if boundary != .elision { closeWord() }
      }
    }
    settleWeight()
    closeWord()
    return stressed
  }

  // MARK: Vowels

  /// The nasal mark goes after the vowel quality but before the length mark,
  /// so `ā̃` is `a` `◌̃` `ː` — the order Hindi already uses and the voices
  /// have heard.
  private static func nasalize(_ ipa: String, if nasalized: Bool) -> String {
    guard nasalized else { return ipa }
    if ipa.hasSuffix(lengthMark) {
      return String(ipa.dropLast()) + nasalMark + lengthMark
    }
    return ipa + nasalMark
  }

  private static func ipa(
    for vowel: SanskritVowel,
    options: SanskritOptions
  ) -> (String, SanskritWarning?) {
    switch vowel {
    case .a: return ("a", nil)
    case .aa: return ("aː", nil)
    case .i: return ("i", nil)
    case .ii: return ("iː", nil)
    case .u: return ("u", nil)
    case .uu: return ("uː", nil)

    // ए and ओ are inherently long in Sanskrit — always guru, and metre
    // depends on it. EdgeSanskrit writes them short, which is the error this
    // length mark exists to avoid.
    case .e: return ("eː", nil)
    case .o: return ("oː", nil)

    // The vrddhi diphthongs. `aɪ` and `aʊ` are the best-conditioned
    // diphthong sequences in the model — English *price* and *mouth* — and
    // carry their length in the glide rather than an explicit mark.
    case .ai: return ("aɪ", nil)
    case .au: return ("aʊ", nil)

    // The vocalic liquids: the one real gap. Kokoro has no syllabic
    // diacritic — neither U+0329 nor U+0325 is in the vocabulary — so `r̩`
    // and `l̩` cannot be written at all. Every realization below is one
    // light syllable, so metre survives; the timbre is what is lost.
    case .vocalicR:
      let rendered = options.vocalicLiquid == .ri ? "ɾɪ" : "ɾu"
      return (rendered, .kokoroApproximation(
        sound: "vocalic ṛ (ऋ)",
        rendered: rendered,
        reason: "no syllabic diacritic in the Kokoro vocabulary"
      ))
    case .vocalicRR:
      let rendered = options.vocalicLiquid == .ri ? "ɾiː" : "ɾuː"
      return (rendered, .kokoroApproximation(
        sound: "long vocalic ṝ (ॠ)",
        rendered: rendered,
        reason: "no syllabic diacritic in the Kokoro vocabulary"
      ))
    case .vocalicL:
      return ("lɪ", .kokoroApproximation(
        sound: "vocalic ḷ (ऌ)",
        rendered: "lɪ",
        reason: "no syllabic diacritic in the Kokoro vocabulary"
      ))
    case .vocalicLL:
      return ("liː", .kokoroApproximation(
        sound: "long vocalic ḹ (ॡ)",
        rendered: "liː",
        reason: "no syllabic diacritic in the Kokoro vocabulary"
      ))
    }
  }

  // MARK: Consonants

  private static func ipa(
    for consonant: SanskritConsonant,
    options: SanskritOptions
  ) -> (String, SanskritWarning?) {
    switch consonant {
    case .ka: return ("k", nil)
    case .kha: return ("kʰ", nil)
    case .ga: return ("ɡ", nil)
    case .gha: return ("ɡʰ", nil)
    case .nga: return ("ŋ", nil)

    // तालव्य. Palatal stops rather than affricates: that is the traditional
    // description, and Kokoro trained `c`/`ɟ` through its Hindi, so they are
    // conditioned in an Indic context. EdgeSanskrit writes `tʃ`/`dʒ`.
    case .ca: return (options.palatalStops == .stops ? "c" : "ʧ", nil)
    case .cha: return (options.palatalStops == .stops ? "cʰ" : "ʧʰ", nil)
    case .ja: return (options.palatalStops == .stops ? "ɟ" : "ʤ", nil)
    case .jha: return (options.palatalStops == .stops ? "ɟʰ" : "ʤʰ", nil)
    case .nya: return ("ɲ", nil)

    case .tta: return ("ʈ", nil)
    case .ttha: return ("ʈʰ", nil)
    case .dda: return ("ɖ", nil)
    case .ddha: return ("ɖʰ", nil)
    case .nna: return ("ɳ", nil)

    // Sanskrit त द न are true dentals and Kokoro's are English alveolars.
    // The contrast with the retroflex series survives, which is the phonemic
    // requirement; the exact place is a voice-training matter and must not be
    // "fixed" by moving these somewhere else in the vocabulary.
    case .ta: return ("t", nil)
    case .tha: return ("tʰ", nil)
    case .da: return ("d", nil)
    case .dha: return ("dʰ", nil)
    case .na: return ("n", nil)

    case .pa: return ("p", nil)
    case .pha: return ("pʰ", nil)
    case .ba: return ("b", nil)
    case .bha: return ("bʰ", nil)
    case .ma: return ("m", nil)

    case .ya: return ("j", nil)
    case .ra: return ("ɾ", nil)
    case .la: return ("l", nil)
    // दन्त्योष्ठ्य: an approximant, not the fricative `v`.
    case .va: return ("ʋ", nil)

    // श ष स stay three-way distinct either way. `ɕ` is the more accurate
    // value for तालव्य श and is in the vocabulary, but reaches Kokoro only
    // through Japanese and Chinese, so it is thinly conditioned here.
    case .sha: return (options.palatalSibilant == .postalveolar ? "ʃ" : "ɕ", nil)
    case .ssa: return ("ʂ", nil)
    case .sa: return ("s", nil)

    // Sanskrit ह is breathy `ɦ`, which is not in the base vocabulary — it is
    // one of the tokens IndicVoice had to add.
    case .ha, .visarga: return ("h", nil)

    case .lla:
      return ("l", .kokoroUnsupported(
        sound: "ḷa (ळ)",
        detail: "ɭ (U+026D) is not in the Kokoro vocabulary; read as l"
      ))

    // Both allophones are spellable, and both are off by default.
    case .jihvamuliya: return ("x", nil)
    case .upadhmaniya: return ("ɸ", nil)
    }
  }

  // MARK: Boundaries

  /// Kokoro's only pause control is its punctuation tokens, and there are two
  /// useful strengths. That is exactly enough for pāda against verse, so the
  /// daṇḍa distinction survives into the audio even though the token stream
  /// cannot carry the structure itself — that stays on `Result.units`.
  private static func ipa(for boundary: SanskritBoundary) -> String {
    switch boundary {
    case .word: return " "
    case .pada: return ", "
    case .verse: return ". "
    case .sentence(let character): return String(character)
    // Avagraha is silent. It is not a length mark, which is what EdgeSanskrit
    // makes of it.
    case .elision: return ""
    }
  }

  /// Punctuation sits tight against the phoneme before it. A space in front of
  /// `.` is token 16 — a pause the model never saw before a sentence break in
  /// training.
  private static func tidied(_ phonemes: String) -> String {
    var out = ""
    for character in phonemes {
      if character == " ", out.hasSuffix(" ") { continue }
      if ",.;:!?".contains(character), out.hasSuffix(" ") { out.removeLast() }
      out.append(character)
    }
    return out.trimmingCharacters(in: .whitespaces)
  }
}
