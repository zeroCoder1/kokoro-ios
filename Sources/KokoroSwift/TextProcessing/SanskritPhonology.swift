import Foundation

/// Something the front end could not do faithfully, reported rather than
/// hidden. A phoneme with no Kokoro token is dropped silently at tokenization,
/// so an unreported approximation looks like a phonemizer bug forever after.
enum SanskritWarning: Equatable {
  /// Kokoro has no token for this sound at all.
  case kokoroUnsupported(sound: String, detail: String)
  /// Kokoro can say something close, but not the real thing.
  case kokoroApproximation(sound: String, rendered: String, reason: String)
  /// Something the parser cannot read as Classical Sanskrit. The detail says
  /// what happened to it.
  case unknownScalar(String)
  /// Vedic accent marks were present and ignored, per the Classical scope.
  case vedicAccentIgnored
  /// The visarga was written, and is realised as something short of a real
  /// one. Kept separate from the generic approximation so it can never be
  /// claimed as faithful Sanskrit.
  case visargaApproximated(rendered: String, reason: String)
  /// A vowel sign or virama with no consonant in front of it.
  case orphanedMark(String)

  var text: String {
    switch self {
    case let .kokoroUnsupported(sound, detail):
      return "KOKORO_UNSUPPORTED: \(sound) — \(detail)"
    case let .kokoroApproximation(sound, rendered, reason):
      return "KOKORO_APPROXIMATION: \(sound) → \(rendered) (\(reason))"
    case let .unknownScalar(detail):
      return "UNKNOWN_SCALAR: \(detail)"
    case .vedicAccentIgnored:
      return "VEDIC_ACCENT_IGNORED: udatta/anudatta marks dropped (Classical scope, see docs/SANSKRIT.md)"
    case let .visargaApproximated(rendered, reason):
      return "KOKORO_APPROXIMATED_VISARGA: ḥ → \(rendered) (\(reason))"
    case let .orphanedMark(mark):
      return "ORPHANED_MARK: \(mark) — no consonant to attach to, dropped"
    }
  }
}

// MARK: - Canonical inventory

/// Place of articulation, in the traditional order. The homorganic anusvara
/// rule is derived from this rather than tabulated five times.
enum SanskritPlace {
  case velar       // कण्ठ्य
  case palatal     // तालव्य
  case retroflex   // मूर्धन्य
  case dental      // दन्त्य
  case labial      // ओष्ठ्य
  case glottal     // no varga nasal

  /// The nasal of this varga, or nil where the place has none.
  var nasal: SanskritConsonant? {
    switch self {
    case .velar: return .nga
    case .palatal: return .nya
    case .retroflex: return .nna
    case .dental: return .na
    case .labial: return .ma
    case .glottal: return nil
    }
  }
}

/// The fourteen Classical vowels. Raw values are SLP1, which gives one ASCII
/// character per phoneme and makes the canonical form directly comparable
/// against Vagdhenu's output.
enum SanskritVowel: String, CaseIterable, Sendable {
  case a = "a", aa = "A"
  case i = "i", ii = "I"
  case u = "u", uu = "U"
  case vocalicR = "f", vocalicRR = "F"
  case vocalicL = "x", vocalicLL = "X"
  case e = "e", ai = "E"
  case o = "o", au = "O"

  /// Long in the metrical sense: guru on its own, without help from a coda.
  ///
  /// e and o are long even though they are written with a single sign — they
  /// are historically monophthongized diphthongs and are always guru. This is
  /// the distinction EdgeSanskrit loses by writing them short.
  var isLong: Bool {
    switch self {
    case .a, .i, .u, .vocalicR, .vocalicL: return false
    case .aa, .ii, .uu, .vocalicRR, .vocalicLL, .e, .ai, .o, .au: return true
    }
  }

  /// The short vowel a visarga echoes at a pause. रामः is *rāmaha*, हरिः is
  /// *harihi*, गुरुः is *guruhu*.
  var echoVowel: SanskritVowel {
    switch self {
    case .a, .aa: return .a
    case .i, .ii, .e, .ai: return .i
    case .u, .uu, .o, .au: return .u
    case .vocalicR, .vocalicRR: return .i
    case .vocalicL, .vocalicLL: return .i
    }
  }
}

/// The 33 Classical consonants, plus ळ and the two visarga allophones.
/// Raw values are SLP1.
enum SanskritConsonant: String, CaseIterable, Sendable {
  case ka = "k", kha = "K", ga = "g", gha = "G", nga = "N"
  case ca = "c", cha = "C", ja = "j", jha = "J", nya = "Y"
  case tta = "w", ttha = "W", dda = "q", ddha = "Q", nna = "R"
  case ta = "t", tha = "T", da = "d", dha = "D", na = "n"
  case pa = "p", pha = "P", ba = "b", bha = "B", ma = "m"
  case ya = "y", ra = "r", la = "l", va = "v"
  case sha = "S", ssa = "z", sa = "s"
  case ha = "h"
  /// ळ — Vedic and Marathi retroflex lateral. Not in the Classical 33 and not
  /// in Kokoro's vocabulary; carried so it is reported rather than dropped.
  case lla = "L"
  /// Visarga allophones. Not standard SLP1 — the extension follows Vagdhenu.
  case jihvamuliya = "Z"     // before क ख
  case upadhmaniya = "V"     // before प फ
  /// The plain visarga, when neither allophone nor an echo applies.
  case visarga = "H"

  var place: SanskritPlace {
    switch self {
    case .ka, .kha, .ga, .gha, .nga, .jihvamuliya: return .velar
    case .ca, .cha, .ja, .jha, .nya, .ya, .sha: return .palatal
    case .tta, .ttha, .dda, .ddha, .nna, .ra, .ssa, .lla: return .retroflex
    case .ta, .tha, .da, .dha, .na, .la, .sa: return .dental
    case .pa, .pha, .ba, .bha, .ma, .va, .upadhmaniya: return .labial
    case .ha, .visarga: return .glottal
    }
  }

  /// A stop of one of the five vargas. These are the environments where the
  /// anusvara becomes a homorganic nasal consonant, and all three references
  /// agree about them.
  var isVarga: Bool {
    switch self {
    case .ka, .kha, .ga, .gha, .nga,
         .ca, .cha, .ja, .jha, .nya,
         .tta, .ttha, .dda, .ddha, .nna,
         .ta, .tha, .da, .dha, .na,
         .pa, .pha, .ba, .bha, .ma:
      return true
    default:
      return false
    }
  }

  var isNasal: Bool {
    switch self {
    case .nga, .nya, .nna, .na, .ma: return true
    default: return false
    }
  }

  /// य र ल व श ष स ह — the antahstha and ushman. The disputed anusvara
  /// environments, and the ones that decide visarga assimilation.
  var isContinuant: Bool {
    switch self {
    case .ya, .ra, .la, .va, .sha, .ssa, .sa, .ha: return true
    default: return false
    }
  }

  var isSibilant: Bool {
    switch self {
    case .sha, .ssa, .sa: return true
    default: return false
    }
  }

  /// Unvoiced, for the visarga allophone rule.
  var isUnvoiced: Bool {
    switch self {
    case .ka, .kha, .ca, .cha, .tta, .ttha, .ta, .tha, .pa, .pha,
         .sha, .ssa, .sa:
      return true
    default:
      return false
    }
  }
}

// MARK: - Options

/// The rules where the references genuinely disagree, isolated so a decision
/// can be changed and heard rather than argued about.
///
/// Every default is the one argued for in `docs/SANSKRIT_G2P_RESEARCH.md`.
/// None of these exists to make the current voices sound better — see §37 of
/// the brief, and `docs/SANSKRIT.md`.
struct SanskritOptions {
  /// What an anusvara becomes before य र ल व श ष स ह.
  ///
  /// Vagdhenu keeps it a nasal continuant; EdgeSanskrit forces `m`, which
  /// gives *samskṛta* and *samyoga* — readings no reciter uses. Panini's
  /// anusvara here is a nasalized continuant, so the default nasalizes the
  /// vowel, which is the closest thing Kokoro can spell.
  enum AnusvaraBeforeContinuant { case nasalizeVowel, labialNasal }

  /// What a word-internal visarga becomes.
  ///
  /// `aspirate` is a plain h: दुःख is *duhkha*, two syllables. Vagdhenu
  /// instead resolves to jihvamuliya before क/ख and upadhmaniya before प/फ,
  /// which Kokoro can spell (`x` and `ɸ` are both in the vocabulary) — but
  /// their own A/B testing preferred the plain form, so that is the default.
  enum InternalVisarga { case aspirate, placeAssimilated }

  /// Which realization of vocalic ऋ/ॠ. Regional, not right-or-wrong: `ri` is
  /// North Indian (*kṛṣṇa* -> "krishna"), `ru` South Indian ("krushna").
  /// Both are one light syllable, so both are metrically correct.
  enum VocalicLiquid { case ri, ru }

  /// श as `ʃ` or the more accurate palatal `ɕ`. `ɕ` is in Kokoro's vocabulary
  /// but reaches it only through Japanese and Chinese, so it is thinly
  /// conditioned in an Indic voice. Either way श ष स stay three-way distinct.
  enum PalatalSibilant { case postalveolar, alveoloPalatal }

  /// च छ ज झ as palatal stops or as affricates. The tradition calls them
  /// तालव्य, and Kokoro's Hindi trained `c`/`ɟ` in an Indic context;
  /// EdgeSanskrit writes `tʃ`/`dʒ`.
  enum PalatalStops { case stops, affricates }

  var anusvaraBeforeContinuant: AnusvaraBeforeContinuant = .nasalizeVowel
  var internalVisarga: InternalVisarga = .aspirate
  var vocalicLiquid: VocalicLiquid = .ri
  var palatalSibilant: PalatalSibilant = .postalveolar
  var palatalStops: PalatalStops = .stops

  /// Whether a visarga at a pause takes its echo vowel.
  ///
  /// **Off, and this is a correction.** Both Sanskrit references do apply the
  /// echo, and traditional recitation does have one — but it is a *brief,
  /// voiceless* echo, and Kokoro cannot spell that. `h` plus a vowel is a full
  /// voiced vowel token and the model renders a full syllable. Measured on
  /// this model:
  ///
  ///     ɾaːma    585 ms   3 energy nuclei
  ///     ɾaːmah   565 ms   3 energy nuclei     ← plain h adds no syllable
  ///     ɾaːmaha  735 ms   6 energy nuclei     ← the echo adds one
  ///
  /// So रामः came out *rā-ma-ha*, three syllables, where Sanskrit has two and
  /// a light aspiration. Turning the echo on is turning that defect back on;
  /// it stays available because the underlying phonology is real and a future
  /// Sanskrit-trained voice may render it correctly.
  var visargaEchoAtPause: Bool = false

  /// Marks prominence by syllable weight, as an accommodation to the acoustic
  /// model rather than a claim about Sanskrit.
  ///
  /// Classical Sanskrit has no stress accent — recitation is governed by
  /// mātrā — so this is **off**, and the phonology layer never sees it: the
  /// mark is added by `SanskritKokoroMapper`, which is the layer that exists
  /// to accommodate Kokoro.
  ///
  /// What the evidence says, so the decision can be made on it. `ˈ` is the
  /// most frequent token in Kokoro's whole training distribution — 8542
  /// occurrences across all nine training languages in an espeak scan, 285 in
  /// Hindi alone — and Sanskrit emits none of it. Switching this on lengthens
  /// vowels by about 10% (क्षेत्रे's final ए goes from 114 ms to 126 ms
  /// against 156 ms for the same vowel in isolation). It does **not** change
  /// vowel quality: `kˈeː` is as centralized as `keː`, so it does not address
  /// the ए-sounds-like-ई complaint.
  ///
  /// Left off because gaining 10% duration by asserting a stress accent the
  /// language does not have is the trade §37 of the brief forbids. It is
  /// implemented, rather than the dead flag it used to be, so the alternative
  /// can be heard.
  ///
  /// The rule when enabled is the weight-based one Western Sanskritists use
  /// (Whitney, Macdonell): the penultimate if heavy, else the antepenultimate,
  /// else the first syllable. A syllable is heavy if its vowel is long or a
  /// consonant cluster closes it.
  var markStressOnHeavySyllables: Bool = false

  static let `default` = SanskritOptions()
}

// MARK: - Phonological rules

/// Sanskrit phonology, with no knowledge of Kokoro.
///
/// Takes the aksharas the parser produced and resolves the rules that decide
/// *which sounds occur*: what an anusvara becomes in each environment, what a
/// visarga becomes at a pause and inside a word, and how a chandrabindu
/// nasalizes. What those sounds are *spelled as* for a particular acoustic
/// model is `SanskritKokoroMapper`'s problem, deliberately.
enum SanskritPhonology {
  /// One resolved phonological segment.
  enum Segment: Equatable {
    case vowel(SanskritVowel, nasalized: Bool)
    case consonant(SanskritConsonant)
    case boundary(SanskritBoundary)
  }

  struct Result {
    var segments: [Segment] = []
    /// Which unit each segment came from, parallel to `segments`. `nil` for a
    /// boundary, which belongs to no akshara. This is what carries source
    /// alignment through the phonology layer so a token can be traced back to
    /// the character range that produced it.
    var origins: [Int?] = []
    var warnings: [SanskritWarning] = []
    /// SLP1 for the resolved form — anusvara turned into its nasal, visarga
    /// into its echo. Diffable against a reference, and the line the
    /// inspector prints as PHONOLOGICAL OUTPUT.
    var slp1: String {
      Self.render(segments).trimmingCharacters(in: .whitespaces)
    }

    /// Appends a segment together with the unit it came from, so the two
    /// arrays cannot drift apart.
    mutating func append(_ segment: Segment, from origin: Int?) {
      segments.append(segment)
      origins.append(origin)
    }

    static func render(_ segments: [Segment]) -> String {
      var out = ""
      for segment in segments {
        switch segment {
        case let .vowel(vowel, nasalized):
          out += vowel.rawValue + (nasalized ? "~" : "")
        case let .consonant(consonant):
          out += consonant.rawValue
        case let .boundary(boundary):
          out += boundary.slp1
        }
      }
      return out
    }
  }

  static func apply(
    to units: [SanskritUnit],
    options: SanskritOptions = .default
  ) -> Result {
    var result = Result()

    for (index, unit) in units.enumerated() {
      switch unit {
      case let .boundary(boundary):
        result.append(.boundary(boundary), from: nil)

      case let .akshara(akshara):
        // The onset cluster is written as it stands; conjuncts need no
        // special handling because they were parsed compositionally.
        for consonant in akshara.onset {
          result.append(.consonant(consonant), from: index)
        }

        // An anusvara or chandrabindu on a vowelless akshara has nothing to
        // sit on; the parser rejects that case, so a vowel is present here
        // whenever a nasal mark is.
        var nasalizedVowel = akshara.chandrabindu
        var homorganic: SanskritConsonant?

        if akshara.anusvara {
          switch anusvaraRealization(
            after: index, in: units, options: options
          ) {
          case let .nasalConsonant(nasal):
            homorganic = nasal
          case .vowelNasalization:
            nasalizedVowel = true
            result.warnings.append(.kokoroApproximation(
              sound: "anusvāra before a continuant",
              rendered: "vowel nasalisation",
              reason: "Kokoro cannot spell a nasalised approximant"
            ))
          }
        }

        if let vowel = akshara.vowel {
          result.append(.vowel(vowel, nasalized: nasalizedVowel), from: index)
        }
        if let homorganic {
          result.append(.consonant(homorganic), from: index)
        }

        if akshara.visarga {
          appendVisarga(
            for: akshara,
            at: index,
            in: units,
            options: options,
            into: &result
          )
        }
      }
    }

    return result
  }

  // MARK: Anusvara

  private enum AnusvaraRealization {
    case nasalConsonant(SanskritConsonant)
    case vowelNasalization
  }

  /// The anusvara's realization is decided by what follows it.
  ///
  /// Before a varga stop it is that varga's nasal, and all three references
  /// agree. Before य र ल व श ष स ह it is a nasal continuant, which Vagdhenu
  /// preserves and EdgeSanskrit flattens to `m`. At a pause or at the end of
  /// the text it is `m`, which everyone agrees on.
  private static func anusvaraRealization(
    after index: Int,
    in units: [SanskritUnit],
    options: SanskritOptions
  ) -> AnusvaraRealization {
    guard let next = nextConsonant(after: index, in: units) else {
      // Word-final or utterance-final: अहं is *aham*.
      return .nasalConsonant(.ma)
    }
    if next.isVarga, let nasal = next.place.nasal {
      return .nasalConsonant(nasal)
    }
    if next.isContinuant {
      switch options.anusvaraBeforeContinuant {
      case .nasalizeVowel: return .vowelNasalization
      case .labialNasal: return .nasalConsonant(.ma)
      }
    }
    return .nasalConsonant(.ma)
  }

  /// The next consonant sound, stopping at a pause. A word boundary is
  /// crossed — sandhi is written into the text, and `संस्कृत` has the
  /// following consonant in the same word anyway — but a danda ends the
  /// search, because nothing assimilates across a verse break.
  private static func nextConsonant(
    after index: Int,
    in units: [SanskritUnit]
  ) -> SanskritConsonant? {
    for unit in units[(index + 1)...] {
      switch unit {
      case let .boundary(boundary):
        if boundary.isPause { return nil }
      case let .akshara(akshara):
        if let first = akshara.onset.first { return first }
        // A vowel-initial akshara: there is no consonant to assimilate to.
        if akshara.vowel != nil { return nil }
      }
    }
    return nil
  }

  // MARK: Visarga

  /// A visarga at a pause takes an echo of the vowel before it — रामः is
  /// *rāmaha*, गुरुः *guruhu*. Inside a word it does not, and that is the
  /// distinction EdgeSanskrit misses: its `duhukʰa` for दुःख is three
  /// syllables where Sanskrit has two, which changes the metre of the pada.
  private static func appendVisarga(
    for akshara: SanskritAkshara,
    at index: Int,
    in units: [SanskritUnit],
    options: SanskritOptions,
    into result: inout Result
  ) {
    let atPause = isAtPause(after: index, in: units)

    if atPause, options.visargaEchoAtPause, let vowel = akshara.vowel {
      result.append(.consonant(.ha), from: index)
      result.append(.vowel(vowel.echoVowel, nasalized: false), from: index)
      result.warnings.append(.visargaApproximated(
        rendered: "h + a full vowel",
        reason: "Kokoro has no short or voiceless vowel, so the echo becomes a whole syllable"
      ))
      return
    }

    if !atPause, options.internalVisarga == .placeAssimilated,
       let next = nextConsonant(after: index, in: units) {
      // Jihvamuliya before an unvoiced velar, upadhmaniya before an unvoiced
      // labial. Both are real Classical allophones and both are spellable in
      // Kokoro, but Vagdhenu's own A/B preferred the plain form, so this is
      // off by default.
      if next.isUnvoiced, next.place == .velar {
        result.append(.consonant(.jihvamuliya), from: index)
        return
      }
      if next.isUnvoiced, next.place == .labial {
        result.append(.consonant(.upadhmaniya), from: index)
        return
      }
    }

    // A plain h. It is not a full visarga — that is a voiceless fricative with
    // a brief echo of the preceding vowel, and Kokoro has neither the
    // voiceless vowel nor a way to shorten one — but it adds no spurious
    // syllable, which the echo does. Reported, never claimed as faithful.
    result.append(.consonant(.ha), from: index)
    result.warnings.append(.visargaApproximated(
      rendered: "h",
      reason: atPause
        ? "the traditional echo vowel is unspellable in Kokoro; h alone avoids a spurious syllable"
        : "word-internal visarga; Kokoro has no voiceless fricative for it"
    ))
  }

  /// Whether what follows is a pause rather than more of the utterance. Only
  /// a danda, sentence punctuation or the end of the text counts; an ordinary
  /// word boundary does not, so a mid-line visarga stays a plain h.
  private static func isAtPause(after index: Int, in units: [SanskritUnit]) -> Bool {
    for unit in units[(index + 1)...] {
      switch unit {
      case let .boundary(boundary):
        if boundary.isPause { return true }
        if boundary == .word { return false }
      case .akshara:
        return false
      }
    }
    return true
  }
}
