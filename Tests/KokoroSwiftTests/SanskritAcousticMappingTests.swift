import Foundation
import Testing
@testable import KokoroSwift

// The experimental acoustic mapper, and the frontend it must not disturb.
//
// Names follow this package's convention — descriptive, no `test` prefix.
// Evidence: Artifacts/sanskrit/acoustic-mapping-v1/

private func analyze(_ text: String, _ options: SanskritOptions = .default)
  -> SanskritPhonemizer.Result
{ SanskritPhonemizer.analyze(text, options: options) }
private func phonemes(_ text: String) -> String { SanskritPhonemizer.phonemize(text) }
private func tokens(_ text: String) -> [Int] { SanskritTokenAudit.audit(text: text).tokenIDs }

private func withProfile(_ profile: SanskritAcousticMappingProfile) -> SanskritOptions {
  var options = SanskritOptions.default
  options.acousticProfile = profile
  return options
}

// MARK: - Valid final vowels are not errors

/// सञ्जय, कदाचन and भारत end in a perfectly valid short a, and समवेता in a
/// long ā. Nothing may delete or suppress them: a vowel that sounds too long
/// is a duration question, never permission to remove it.
@Test func validFinalVowelsAreNeverRemoved() {
  let cases: [(String, String, String)] = [
    ("सञ्जय", "saYjaya", "saɲɟaja"),
    ("कदाचन", "kadAcana", "kadaːcana"),
    ("भारत", "BArata", "bʰaːɾata"),
    ("समवेता", "samavetA", "samaʋeːtaː"),
  ]
  for (word, canonical, ipa) in cases {
    let result = analyze(word)
    #expect(result.canonical == canonical, "\(word) gave \(result.canonical)")
    #expect(result.kokoroPhonemes == ipa, "\(word) gave \(result.kokoroPhonemes)")
    // The final vowel is present in the tokens the model receives.
    let last = result.kokoroPhonemes.unicodeScalars.last!
    #expect("aeiouɪʊː".unicodeScalars.contains(last),
            "\(word) lost its final vowel: \(result.kokoroPhonemes)")
  }
  // समवेता keeps its long ā; the other three keep a short a.
  #expect(phonemes("समवेता").hasSuffix("aː"))
  for word in ["सञ्जय", "कदाचन", "भारत"] {
    #expect(phonemes(word).hasSuffix("a"))
    #expect(!phonemes(word).hasSuffix("aː"), "\(word) gained length")
  }
}

/// The shipped profile leaves those vowels' duration alone too. A blanket rule
/// over every word-final short vowel is a guess, not a repair.
@Test func theShippedProfileDoesNotTouchValidFinalVowels() {
  for word in ["सञ्जय", "कदाचन", "भारत", "कर्मणि", "भवति"] {
    let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
      phonemes(word), intent: .closureRepairs
    )
    #expect(scale == nil || scale?.allSatisfy { $0 == 1.0 } == true,
            "\(word): the shipped profile scaled a valid final vowel")
  }
  #expect(SanskritDelivery.recitation.intent.finalShortVowelScale == 1.0)
  #expect(SanskritDelivery.learning.intent.finalShortVowelScale == 1.0)
  // The experimental profile exists and does apply it, so the option is real.
  #expect(SanskritProsodyIntent.experimentalFinalVowel.finalShortVowelScale < 1.0)
}

// MARK: - Explicit closure

@Test func explicitViramaClosesTheFinalConsonant() {
  for (word, expected) in [("अहम्", "aham"), ("भगवान्", "bʰaɡaʋaːn"),
                           ("तत्", "tat"), ("कृत्", "kɾɪt"),
                           ("ब्रह्मन्", "bɾahman"), ("कदाचित्", "kadaːcit")] {
    #expect(phonemes(word) == expected, "\(word) gave \(phonemes(word))")
    let last = phonemes(word).unicodeScalars.last!
    #expect(!"aeiouɪʊː".unicodeScalars.contains(last),
            "\(word) gained a final vowel")
  }
  // Each against the open form it must not become.
  for (closed, open) in [("अहम्", "अहम"), ("भगवान्", "भगवान"), ("तत्", "तत")] {
    #expect(phonemes(closed) != phonemes(open))
    #expect(tokens(closed) != tokens(open))
  }
}

// MARK: - Contrasts that must survive every experiment

@Test func vowelAndConsonantContrastsRemainDistinct() {
  for (a, b) in [("के", "की"), ("चै", "चे"), ("को", "कू"),
                 ("क", "का"), ("कि", "की"), ("कु", "कू")] {
    #expect(phonemes(a) != phonemes(b), "\(a)/\(b) collapsed")
    #expect(tokens(a) != tokens(b))
  }
  // ñ ≠ n ≠ ṅ ≠ ṇ, ṣ ≠ ś ≠ s, ṭ ≠ t, ḍ ≠ d
  let nasals = ["ञा", "ना", "ङा", "णा", "मा"].map(phonemes)
  #expect(Set(nasals).count == 5)
  let sibilants = ["शा", "षा", "सा"].map(phonemes)
  #expect(Set(sibilants).count == 3)
  #expect(phonemes("टा") != phonemes("ता"))
  #expect(phonemes("डा") != phonemes("दा"))
  // Aspirated stops are single phonemes, not stop + independent ह.
  #expect(phonemes("था") != phonemes("त्हा"))
  #expect(phonemes("भा") != phonemes("ब्हा"))
  #expect(SanskritConsonant.tha.isSingleAspiratedPhoneme)
  #expect(SanskritConsonant.bha.isSingleAspiratedPhoneme)
}

// MARK: - Canonical phonemes are model-independent

/// The canonical Sanskrit layer never changes because Kokoro lacks a sound.
/// Every experimental profile may alter the IPA and must not alter canonical.
@Test func theExperimentalMapperDoesNotModifyTheCanonicalLayer() {
  let words = ["कृष्ण", "सृजाम्यहम्", "हृषीकेश", "क्षेत्रे", "समवेता",
               "श्रद्धा", "रामः", "सञ्जय", "अभ्युत्थानम्"]
  for profile in SanskritAcousticMappingProfile.allExperimental {
    let options = withProfile(profile)
    for word in words {
      #expect(analyze(word, options).canonical == analyze(word).canonical,
              "\(profile.name) changed the canonical form of \(word)")
      #expect(analyze(word, options).phonological == analyze(word).phonological,
              "\(profile.name) changed the phonological form of \(word)")
    }
  }
}

/// The baseline profile is a true no-op: production output is byte-identical
/// to having no profile mechanism.
@Test func theBaselineProfileRemainsByteIdentical() {
  let words = ["धर्मक्षेत्रे", "कृष्ण", "रामः", "सञ्जय", "अभ्युत्थानम्",
               "समवेता", "युयुत्सवः", "मामकाः", "कर्मणि"]
  let options = withProfile(.baseline)
  for word in words {
    #expect(analyze(word, options).kokoroPhonemes == phonemes(word),
            "\(word): the baseline profile changed the mapping")
    #expect(analyze(word, options).canonical == analyze(word).canonical)
    #expect(SanskritTokenAudit.audit(text: word).roundTrips)
  }
  #expect(SanskritAcousticMappingProfile.baseline.vowels.isEmpty)
  #expect(SanskritAcousticMappingProfile.baseline.consonants.isEmpty)
  #expect(SanskritOptions.default.acousticProfile == .baseline)
}

/// An override is keyed by canonical phoneme, so it fires wherever that sound
/// occurs and nowhere else. A rule keyed to a word would not generalise.
@Test func experimentalOverridesAreScopedByPhonemeNotByWord() {
  let options = withProfile(.vocalicRAsRhoticVowel)
  // Every word containing ऋ changes...
  for word in ["कृष्ण", "सृजाम्यहम्", "हृषीकेश", "वृत्ति", "मृत्यु"] {
    #expect(analyze(word, options).kokoroPhonemes != phonemes(word), "\(word) unchanged")
    #expect(analyze(word, options).kokoroPhonemes.contains("ɚ"))
  }
  // ...and every word without it is untouched.
  for word in ["धर्मक्षेत्रे", "सञ्जय", "रामः", "समवेता", "अभ्युत्थानम्", "कदाचन"] {
    #expect(analyze(word, options).kokoroPhonemes == phonemes(word),
            "\(word) changed but contains no ṛ")
  }
}

/// A non-exact mapping always warns.
@Test func everyNonExactMappingProducesAWarning() {
  let options = withProfile(.vocalicRAsRhoticVowel)
  #expect(analyze("कृष्ण", options).warnings.contains {
    $0.text.hasPrefix("KOKORO_APPROXIMATION")
  })
  // The quality grade is carried, not assumed.
  #expect(SanskritAcousticMappingProfile.vocalicRAsRhoticVowel
    .quality["vocalicR"] == .defensibleApproximation)
  #expect(SanskritAcousticMappingProfile.shaAsAlveoloPalatal
    .quality["sha"] == .exact)
}

// MARK: - Canonical inventory the experiments must preserve

@Test func canonicalPhonemesForTheTargetSoundsAreUnchanged() {
  // Vocalic ṛ stays `f` canonically whatever the acoustic profile says.
  for profile in SanskritAcousticMappingProfile.allExperimental {
    #expect(analyze("कृष्ण", withProfile(profile)).canonical == "kfzRa")
  }
  #expect(analyze("सञ्जय").canonical.contains("Y"))      // palatal nasal
  #expect(analyze("सङ्ग").canonical.contains("N"))        // velar nasal
  #expect(analyze("कृष्ण").canonical.contains("z"))       // retroflex sibilant
  #expect(analyze("रामः").canonical.contains("H"))        // visarga
  // ...and the visarga survives the phonological layer too, distinct from ह.
  #expect(analyze("रामः").phonological.contains("H"))
  #expect(analyze("कह्").phonological == "kah")
  #expect(analyze("कः").phonological != analyze("कह्").phonological)
}

@Test func denseClustersGainNoVowelsUnderAnyProfile() {
  let clusters = ["र्मक्ष", "ण्ये", "श्चै", "र्भूर्", "ङ्गो",
                  "स्त्व", "भ्युत्थ", "निर्भ", "ञ्ज"]
  for profile in [SanskritAcousticMappingProfile.baseline] +
                 SanskritAcousticMappingProfile.allExperimental {
    let options = withProfile(profile)
    for cluster in clusters {
      let result = analyze(cluster, options)
      #expect(SanskritTokenAudit.audit(phonemes: result.kokoroPhonemes).roundTrips,
              "\(profile.name)/\(cluster) did not round trip")
      // Exactly one vowel: the inherent a the last consonant carries.
      let vowels = result.kokoroPhonemes.unicodeScalars.filter {
        "aeiouɪʊɛɔəɐɚ".unicodeScalars.contains($0)
      }.count
      #expect(vowels <= 2, "\(profile.name)/\(cluster) has \(vowels) vowels")
    }
  }
}

// MARK: - Duration repair safety

@Test func durationRepairsNeverChangeVowelIdentityOrTokens() {
  for word in ["युयुत्सवः", "रामः", "योगः", "नमः"] {
    let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
      phonemes(word), intent: .closureRepairs
    )
    // A short vowel before a visarga is never lengthened.
    #expect(scale?[(scale?.count ?? 1) - 2] == 1.0,
            "\(word): a short vowel before the visarga was scaled")
  }
  for word in ["मामकाः", "पाण्डवाः", "भूः", "धीः"] {
    let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
      phonemes(word), intent: .closureRepairs
    )
    #expect(scale?[(scale?.count ?? 1) - 2] ?? 0 > 1.0,
            "\(word): the long vowel before the visarga was not repaired")
  }
  // No repair alters a phoneme or a token, in any intent.
  for intent in [SanskritProsodyIntent.neutral, .closureRepairs,
                 .experimentalFinalVowel, .recitation] {
    for word in ["सञ्जय", "कर्मणि", "मामकाः", "युयुत्सवः", "अहम्"] {
      let before = phonemes(word)
      let beforeTokens = tokens(word)
      _ = SanskritProsodyPlanner.durationScaleForPhonemes(before, intent: intent)
      #expect(phonemes(word) == before, "\(word): a repair changed the phonemes")
      #expect(tokens(word) == beforeTokens, "\(word): a repair changed the tokens")
    }
  }
}

@Test func tokenRoundTripRemainsValidUnderEveryProfile() {
  let words = ["धर्मक्षेत्रे", "कृष्ण", "रामः", "सञ्जय", "अभ्युत्थानम्",
               "समवेता", "युयुत्सवः", "मामकाः", "सृजाम्यहम्", "हृषीकेश"]
  for profile in [SanskritAcousticMappingProfile.baseline] +
                 SanskritAcousticMappingProfile.allExperimental {
    let options = withProfile(profile)
    for word in words {
      let audit = SanskritTokenAudit.audit(
        phonemes: analyze(word, options).kokoroPhonemes
      )
      #expect(audit.roundTrips, "\(profile.name)/\(word):\n\(audit.summary)")
    }
  }
}
