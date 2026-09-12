import Foundation

// Experimental acoustic mappings, kept apart from the stable mapper.
//
// The canonical Sanskrit layer never changes because Kokoro lacks a sound.
// When the model cannot say something, that is recorded here — as a candidate
// realisation and a quality grade — and the canonical form stays what Sanskrit
// says it is.
//
// Every override is keyed by **canonical phoneme**, never by word. A rule that
// fires on a particular Gita word is a lookup table pretending to be
// linguistics, and it would not generalise to the other 699 verses.

/// How faithful a Kokoro realisation is to the Sanskrit sound.
enum SanskritAcousticMappingQuality: Equatable, Sendable {
  /// Kokoro has the sound.
  case exact
  /// Not the sound, but the same phonetic category, and defensible on
  /// phonetic grounds rather than on how it happens to sound in one voice.
  case defensibleApproximation
  /// Kokoro does not have the sound at all.
  case unsupported
}

/// A named set of candidate overrides.
///
/// `baseline` is production and holds none: the stable mapper decides
/// everything. An experimental profile overrides individual canonical phonemes
/// so an A/B can change exactly one thing.
struct SanskritAcousticMappingProfile: Equatable, Sendable {
  let name: String
  /// Overrides keyed by canonical vowel.
  var vowels: [SanskritVowel: String] = [:]
  /// Overrides keyed by canonical consonant.
  var consonants: [SanskritConsonant: String] = [:]
  /// The quality claimed for each override, so nothing silently upgrades
  /// itself to "exact" by being written down.
  var quality: [String: SanskritAcousticMappingQuality] = [:]

  /// Production. No overrides at all, so the shipped mapper is untouched and
  /// byte-identical to having no profile mechanism.
  static let baseline = SanskritAcousticMappingProfile(name: "baseline")

  // MARK: Candidates under test

  /// Vocalic ṛ as an r-coloured vowel rather than flap + vowel.
  ///
  /// Sanskrit ṛ is a syllabic rhotic — one light syllable whose nucleus is
  /// r-coloured. `ɾɪ` is a flap followed by a separate vowel, which is two
  /// segments and the North Indian reading convention rather than the sound
  /// itself. `ɚ` is an r-coloured mid-central vowel: a single rhotic nucleus,
  /// the same phonetic category as ṛ.
  ///
  /// It is also the only rhotic-vowel symbol in the vocabulary with real
  /// training behind it — 694 occurrences against 0 for `ɻ` and 1 for `ɽ`,
  /// both of which are the *more* accurate symbols and both untrained.
  ///
  /// Graded `defensibleApproximation`, not exact: `ɚ` is mid-central where
  /// Sanskrit ṛ is retroflex, and Kokoro has no syllabic diacritic to write
  /// the real thing.
  static let vocalicRAsRhoticVowel = SanskritAcousticMappingProfile(
    name: "vocalic-r-rhotic-vowel",
    vowels: [.vocalicR: "ɚ", .vocalicRR: "ɚː"],
    quality: ["vocalicR": .defensibleApproximation,
              "vocalicRR": .defensibleApproximation]
  )

  /// Vocalic ṛ in the South Indian reading. Equally traditional, and the
  /// alternative to the shipped North Indian `ɾɪ`.
  static let vocalicRAsRu = SanskritAcousticMappingProfile(
    name: "vocalic-r-ru",
    vowels: [.vocalicR: "ɾu", .vocalicRR: "ɾuː"],
    quality: ["vocalicR": .defensibleApproximation,
              "vocalicRR": .defensibleApproximation]
  )

  /// ए as a more open mid-front vowel. `ɛ` is better trained than `e`
  /// (1792 against 1171) but is open-mid where Sanskrit ए is close-mid, so
  /// this is a test of whether training weight beats phonetic accuracy.
  static let eAsOpenMid = SanskritAcousticMappingProfile(
    name: "e-open-mid",
    vowels: [.e: "ɛː"],
    quality: ["e": .defensibleApproximation]
  )

  /// श as the alveolo-palatal it properly is. `ɕ` is the accurate symbol for
  /// तालव्य श but reaches Kokoro only through Chinese and Japanese.
  static let shaAsAlveoloPalatal = SanskritAcousticMappingProfile(
    name: "sha-alveolo-palatal",
    consonants: [.sha: "ɕ"],
    quality: ["sha": .exact]
  )

  /// Visarga as a voiceless palatal fricative. Phonetically closer to a real
  /// visarga than `h` in some environments, but `ç` has **one** occurrence in
  /// the whole training scan, so this is expected to fail.
  static let visargaAsPalatalFricative = SanskritAcousticMappingProfile(
    name: "visarga-palatal-fricative",
    consonants: [.visarga: "ç"],
    quality: ["visarga": .defensibleApproximation]
  )

  /// Every profile the experiment harness runs.
  static let allExperimental: [SanskritAcousticMappingProfile] = [
    vocalicRAsRhoticVowel, vocalicRAsRu, eAsOpenMid,
    shaAsAlveoloPalatal, visargaAsPalatalFricative,
  ]
}

extension SanskritOptions {
  /// The acoustic profile in force. `.baseline` in production.
  ///
  /// Stored out of line because `SanskritOptions` is a value type used all
  /// over the tests, and adding a stored property with a non-trivial default
  /// to it would churn every construction site.
  var acousticProfile: SanskritAcousticMappingProfile {
    get { profileStorage ?? .baseline }
    set { profileStorage = newValue }
  }
}
