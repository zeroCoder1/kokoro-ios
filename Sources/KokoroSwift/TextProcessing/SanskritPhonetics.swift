import Foundation

// The phonetic feature model for Sanskrit consonants.
//
// Sanskrit consonants are not an unordered alphabet: the varga system is a
// feature matrix, and almost every phonological rule in the language is stated
// over those features rather than over letters. Representing them explicitly
// means the homorganic anusvāra rule, the syllabifier's sparśa test and the
// compatibility audit all read the same source of truth instead of repeating
// a table three times.
//
// Reference: sanskritguide.com/the-consonants-overview — used as a linguistic
// description, not as code. Its statement that aspirated letters are "entirely
// different glyphs, not stop + h" is the one this file most depends on.

/// Voiced or not. Columns 1 and 2 of each varga are voiceless; 3, 4 and the
/// nasal are voiced.
enum SanskritVoicing: Equatable {
  case voiceless
  case voiced
}

/// Aspirated or not. Columns 2 and 4 of each varga are aspirated.
///
/// **Aspiration is a feature of the stop, not a following `ह`.** ख is one
/// phoneme, not क + ह, and the canonical layer must keep those apart — see
/// `SanskritConsonant.isSingleAspiratedPhoneme`.
enum SanskritAspiration: Equatable {
  case unaspirated
  case aspirated
}

/// How the airflow is obstructed.
enum SanskritManner: Equatable {
  /// स्पर्श — a full closure. The four stops of each varga.
  case stop
  /// अनुनासिक — closure released through the nose. One per varga.
  case nasal
  /// अन्तःस्थ — य र ल व.
  case semivowel
  /// ऊष्मन् — श ष स.
  case sibilant
  /// ह, and the visarga allophones.
  case aspirate

  /// स्पर्श: a stop or a nasal.
  ///
  /// This is the class the syllabifier tests. "When a sparśa consonant appears
  /// after a vowel, the syllable ends with that consonant" — which is why
  /// मन्त्र divides *man-tra* and not *mant-ra*.
  var isSparsha: Bool { self == .stop || self == .nasal }
}

extension SanskritConsonant {
  var voicing: SanskritVoicing {
    switch self {
    case .ka, .kha, .ca, .cha, .tta, .ttha, .ta, .tha, .pa, .pha,
         .sha, .ssa, .sa, .jihvamuliya, .upadhmaniya, .visarga:
      return .voiceless
    default:
      return .voiced
    }
  }

  var aspiration: SanskritAspiration {
    switch self {
    case .kha, .gha, .cha, .jha, .ttha, .ddha, .tha, .dha, .pha, .bha:
      return .aspirated
    default:
      return .unaspirated
    }
  }

  var manner: SanskritManner {
    switch self {
    case .ka, .kha, .ga, .gha,
         .ca, .cha, .ja, .jha,
         .tta, .ttha, .dda, .ddha,
         .ta, .tha, .da, .dha,
         .pa, .pha, .ba, .bha:
      return .stop
    case .nga, .nya, .nna, .na, .ma:
      return .nasal
    case .ya, .ra, .la, .va, .lla:
      return .semivowel
    case .sha, .ssa, .sa:
      return .sibilant
    case .ha, .jihvamuliya, .upadhmaniya, .visarga:
      return .aspirate
    }
  }

  /// स्पर्श — a stop or a nasal. The class the syllabifier and the anusvāra
  /// rule both test.
  var isSparsha: Bool { manner.isSparsha }

  /// True for the ten aspirated stops.
  ///
  /// The canonical layer models these as **one** phoneme with an aspiration
  /// feature. ख is not क + ह. Only `SanskritKokoroMapper` splits them, and only
  /// because Kokoro has no single token for an aspirated stop — that is a
  /// model compromise, recorded there and nowhere else.
  var isSingleAspiratedPhoneme: Bool { aspiration == .aspirated && manner == .stop }

  /// The unaspirated stop at the same place, or `nil` when there is none.
  /// ख -> क, घ -> ग.
  var unaspiratedCounterpart: SanskritConsonant? {
    switch self {
    case .kha: return .ka
    case .gha: return .ga
    case .cha: return .ca
    case .jha: return .ja
    case .ttha: return .tta
    case .ddha: return .dda
    case .tha: return .ta
    case .dha: return .da
    case .pha: return .pa
    case .bha: return .ba
    default: return nil
    }
  }

  /// A one-line feature description, for diagnostics.
  var featureDescription: String {
    var parts = ["\(place)"]
    if manner == .stop || manner == .nasal {
      parts.append("\(voicing)")
    }
    if manner == .stop {
      parts.append("\(aspiration)")
    }
    parts.append("\(manner)")
    return parts.joined(separator: " / ")
  }
}

extension SanskritVowel {
  /// Whether this vowel alone makes its syllable heavy.
  ///
  /// "A syllable is short if and only if it ends in a short vowel (a, i, u, ṛ
  /// or ḷ)." So ā ī ū ṝ ḹ are heavy, and so are e ai o au: these four are
  /// historically diphthongs and are always guru, whatever a Latin
  /// transcription without macrons might suggest.
  var isProsodicallyLong: Bool { isLong }

  /// Mātrās the nucleus contributes on its own, before any coda is counted.
  var nucleusMatras: Int { isLong ? 2 : 1 }
}
