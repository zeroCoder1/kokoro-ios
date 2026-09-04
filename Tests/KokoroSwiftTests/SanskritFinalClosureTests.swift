import Foundation
import Testing
@testable import KokoroSwift

// Word-final closure: no consonant may gain an inherent vowel, no short final
// vowel may lengthen, and no visarga may become a syllable.
//
// Names follow this package's convention — descriptive, no `test` prefix.
// Evidence: Artifacts/sanskrit/diagnostics/word-final-closure-audit.md
//
// These assert the *frontend*. Where the audit found the model adding a vowel
// anyway, the test still pins the correct token sequence, so a later change
// cannot "fix" an acoustic symptom by corrupting the phonemes.

private func analyze(_ text: String) -> SanskritPhonemizer.Result {
  SanskritPhonemizer.analyze(text)
}
private func phonemes(_ text: String) -> String { SanskritPhonemizer.phonemize(text) }
private func tokens(_ text: String) -> [Int] { SanskritTokenAudit.audit(text: text).tokenIDs }
private func decoded(_ text: String) -> [String] { SanskritTokenAudit.audit(text: text).decoded }

/// Every vowel symbol Kokoro has. Used to assert a string ends on a consonant.
private let vowelScalars = Set("aeiouɑɐɒæɔəɛɜɨɪɯøœʊʌɤ".unicodeScalars)

private func endsOnConsonant(_ ipa: String) -> Bool {
  guard let last = ipa.unicodeScalars.last else { return false }
  return !vowelScalars.contains(last) && last != "ː"
}

// MARK: - Virāma closes the syllable

@Test func finalViramaRemovesTheInherentVowel() {
  for (open, closed) in [("क", "क्"), ("त", "त्"), ("म", "म्"), ("न", "न्"),
                         ("र", "र्"), ("प", "प्"), ("य", "य्")] {
    #expect(phonemes(open) != phonemes(closed), "\(open)/\(closed) collapsed")
    #expect(endsOnConsonant(phonemes(closed)), "\(closed) kept a vowel: \(phonemes(closed))")
    #expect(!endsOnConsonant(phonemes(open)), "\(open) lost its inherent vowel")
    #expect(tokens(open) != tokens(closed))
  }
  #expect(phonemes("क") == "ka")
  #expect(phonemes("क्") == "k")
}

@Test func finalConsonantsDoNotGainAnInherentVowel() {
  let cases: [(String, String)] = [
    ("अहम्", "aham"), ("भगवान्", "bʰaɡaʋaːn"), ("तत्", "tat"), ("कृत्", "kɾɪt"),
    ("अभ्युत्थानम्", "abʰjuttʰaːnam"), ("सृजाम्यहम्", "sɾɪɟaːmjaham"),
    ("तदात्मानम्", "tadaːtmaːnam"), ("ब्रह्मन्", "bɾahman"),
    ("कम्", "kam"), ("कन्", "kan"), ("कत्", "kat"), ("कर्", "kaɾ"),
  ]
  for (word, expected) in cases {
    let produced = phonemes(word)
    #expect(produced == expected, "\(word) gave \(produced)")
    #expect(endsOnConsonant(produced), "\(word) gained a final vowel: \(produced)")
    // The decoded tokens end on the same consonant the IPA does.
    #expect(decoded(word).last == String(produced.unicodeScalars.last!))
  }
}

/// Each closed form against the open form it must not become.
@Test func finalMNTRRemainClosed() {
  let pairs: [(String, String, String)] = [
    ("अहम्", "अहम", "final म्"),
    ("भगवान्", "भगवान", "final न्"),
    ("तत्", "तत", "final त्"),
    ("कर्", "कर", "final र्"),
    ("मम्", "मम", "final म्"),
    ("कन्", "कन", "final न्"),
  ]
  for (closed, open, label) in pairs {
    #expect(phonemes(closed) != phonemes(open), "\(label): \(closed)/\(open) collapsed")
    #expect(tokens(closed) != tokens(open), "\(label): tokens collapsed")
    #expect(decoded(closed) != decoded(open), "\(label): decoded collapsed")
    #expect(endsOnConsonant(phonemes(closed)), "\(label): \(closed) gained a vowel")
    #expect(phonemes(open).hasSuffix("a"), "\(open) lost its inherent vowel")
  }
}

// MARK: - Final short vowels stay short

/// य carries its inherent अ, and that अ must not lengthen. सञ्जय is not सञ्जया.
@Test func sanjayaDoesNotGainAFinalLongVowel() {
  #expect(phonemes("सञ्जय") == "saɲɟaja")
  #expect(analyze("सञ्जय").canonical == "saYjaya")
  #expect(phonemes("सञ्जय") != phonemes("सञ्जया"))
  #expect(tokens("सञ्जय") != tokens("सञ्जया"))
  #expect(decoded("सञ्जय") != decoded("सञ्जया"))
  // It ends on a short a, not a long one.
  #expect(phonemes("सञ्जय").hasSuffix("a"))
  #expect(!phonemes("सञ्जय").hasSuffix("aː"))
  #expect(phonemes("सञ्जया").hasSuffix("aː"))
  // ...and the palatal nasal is still there.
  #expect(phonemes("सञ्जय").contains("ɲ"))
  #expect(!phonemes("सञ्जय").contains("n"))
}

@Test func kadachanaDoesNotGainAFinalLongVowel() {
  #expect(phonemes("कदाचन") == "kadaːcana")
  #expect(phonemes("कदाचन") != phonemes("कदाचना"))
  #expect(!phonemes("कदाचन").hasSuffix("aː"))
  #expect(phonemes("कदाचना").hasSuffix("aː"))
  #expect(tokens("कदाचन") != tokens("कदाचना"))
  // And the closed form is different again.
  #expect(phonemes("कदाचन्") == "kadaːcan")
  #expect(Set(["कदाचन", "कदाचना", "कदाचन्"].map(phonemes)).count == 3)
}

@Test func karmaniKeepsItsShortFinalI() {
  #expect(phonemes("कर्मणि") == "kaɾmaɳi")
  #expect(phonemes("कर्मणी") == "kaɾmaɳiː")
  #expect(phonemes("कर्मणि") != phonemes("कर्मणी"))
  #expect(tokens("कर्मणि") != tokens("कर्मणी"))
  #expect(decoded("कर्मणि") != decoded("कर्मणी"))
  #expect(!phonemes("कर्मणि").hasSuffix("ː"))
  #expect(phonemes("कर्मणी").hasSuffix("ː"))
  // The retroflex nasal survives in both.
  #expect(phonemes("कर्मणि").contains("ɳ"))
}

@Test func everyFinalShortVowelStaysDistinctFromItsLongForm() {
  for (short, long) in [("कि", "की"), ("ति", "ती"), ("नि", "नी"), ("णि", "णी"),
                        ("भवति", "भवती"), ("स्मरति", "स्मरती"),
                        ("कु", "कू"), ("क", "का")] {
    #expect(phonemes(short) != phonemes(long), "\(short)/\(long) collapsed")
    #expect(tokens(short) != tokens(long))
    #expect(!phonemes(short).hasSuffix("ː"), "\(short) gained length")
    #expect(phonemes(long).hasSuffix("ː"), "\(long) lost length")
  }
}

// MARK: - Visarga

@Test func visargaDoesNotBecomeHaAndGainsNoVowel() {
  for word in ["अः", "कः", "रामः", "नमः", "योगः", "अर्जुनः", "युयुत्सवः",
               "पाण्डवाः", "मामकाः", "पुनः", "श्रेयः"] {
    let produced = phonemes(word)
    #expect(produced.hasSuffix("h"), "\(word) does not end on the visarga: \(produced)")
    #expect(!produced.hasSuffix("ha"), "\(word) became ha")
    #expect(!produced.hasSuffix("haː"), "\(word) became hā")
    #expect(endsOnConsonant(produced))
    #expect(analyze(word).warnings.contains {
      $0.text.hasPrefix("KOKORO_APPROXIMATED_VISARGA")
    }, "\(word) claimed a faithful visarga")
  }
  // ः, ह, ह् and हा stay four distinct things canonically.
  #expect(Set(["कः", "कह", "कह्", "कहा"].map { analyze($0).canonical }).count == 4)
  // The visarga adds a consonant, never a vowel: the vowel count is unchanged.
  for (bare, withVisarga) in [("क", "कः"), ("राम", "रामः"), ("नम", "नमः")] {
    let count = { (s: String) in s.unicodeScalars.filter { vowelScalars.contains($0) }.count }
    #expect(count(phonemes(bare)) == count(phonemes(withVisarga)),
            "\(withVisarga) gained a vowel")
  }
}

@Test func yuyutsavahKeepsItsShortVowelAndClosedCluster() {
  let produced = phonemes("युयुत्सवः")
  #expect(produced == "jujutsaʋah")
  // No vowel inside त्स.
  #expect(produced.contains("tsa"))
  #expect(!produced.contains("tasa"))
  // The vowel before the visarga is SHORT.
  #expect(produced.hasSuffix("ah"))
  #expect(!produced.hasSuffix("aːh"))
  #expect(!produced.hasSuffix("ha"))
  // And it is not वहा.
  #expect(!produced.hasSuffix("ʋaha"))
}

@Test func mamakahPreservesBothLongAVowels() {
  let result = analyze("मामकाः")
  #expect(result.canonical == "mAmakAH")
  #expect(result.kokoroPhonemes == "maːmakaːh")
  // Two long ā, both present.
  #expect(result.kokoroPhonemes.filter { $0 == "ː" }.count == 2)
  // The visarga follows the long ā and does not consume it.
  let scalars = Array(result.kokoroPhonemes.unicodeScalars)
  #expect(scalars.last == "h")
  #expect(scalars[scalars.count - 2] == "ː")
  #expect(scalars[scalars.count - 3] == "a")
  // Not य, not हा, no trailing vowel.
  #expect(!result.kokoroPhonemes.contains("j"))
  #expect(!result.kokoroPhonemes.hasSuffix("ha"))
  // Three syllables: mā-ma-kāḥ.
  let units = SanskritAksharaParser.parse(result.normalized).units
  #expect(SanskritSyllabifier.syllabify(units).syllables.count == 3)
}

// MARK: - Clusters stay closed

@Test func rbhurClusterStaysClosedAtWordEnd() {
  #expect(phonemes("भूर्") == "bʰuːɾ")
  #expect(phonemes("भूर्मा") == "bʰuːɾmaː")
  #expect(phonemes("हेतुर्भूर्मा") == "heːtuɾbʰuːɾmaː")
  let produced = phonemes("हेतुर्भूर्मा")
  #expect(produced.contains("ɾbʰ"), "र् did not attach to भ")
  #expect(produced.contains("bʰuː"), "aspiration or length lost")
  #expect(produced.contains("uːɾm"), "the second र् vanished")
  // No inserted vowel around either र्.
  #expect(!produced.contains("ɾabʰ"))
  #expect(!produced.contains("ɾama"))
  #expect(phonemes("भूर्") != phonemes("भूर"))
}

@Test func denseClustersStayClosedWithNoEpenthesis() {
  let cases: [(String, String)] = [
    ("र्मक्ष", "ɾmakʂa"), ("ण्ये", "ɳjeː"), ("श्चै", "ʃcaɪ"), ("र्भूर्", "ɾbʰuːɾ"),
    ("ङ्गो", "ŋɡoː"), ("स्त्व", "stʋa"), ("भ्युत्थ", "bʰjuttʰa"),
    ("निर्भ", "niɾbʰa"), ("ञ्ज", "ɲɟa"),
  ]
  for (cluster, expected) in cases {
    #expect(phonemes(cluster) == expected, "\(cluster) gave \(phonemes(cluster))")
    #expect(SanskritTokenAudit.audit(text: cluster).roundTrips)
  }
  // Aspiration, place and nasal identity all survive.
  #expect(phonemes("भ्युत्थ").contains("ʰ"))
  #expect(phonemes("ञ्ज").contains("ɲ"))
  #expect(phonemes("ण्ये").contains("ɳ"))
  #expect(phonemes("र्मक्ष").contains("ʂ"))
}

// MARK: - Tokenization inserts nothing

@Test func tokenRoundTripDoesNotInsertVowels() {
  var probes = ["सञ्जय", "कदाचन", "अहम्", "भगवान्", "कर्मणि", "योगः", "मामकाः",
                "युयुत्सवः", "तत्", "कृत्", "अर्जुनः", "रामः", "भूर्मा",
                "सङ्गोऽस्त्वकर्मणि", "अभ्युत्थानम्", "सृजाम्यहम्"]
  for base in ["क", "त", "म"] {
    probes += [base, base + "्", base + "म्", base + "न्", base + "त्", base + "र्", base + "ः"]
  }
  for probe in probes {
    let audit = SanskritTokenAudit.audit(text: probe)
    #expect(audit.roundTrips, "\(probe) did not round trip:\n\(audit.summary)")
    #expect(audit.duplicated.isEmpty, "\(probe) duplicated \(audit.duplicated)")
    // Decoding gives back exactly the phoneme string, so nothing was inserted.
    #expect(audit.decoded.joined() == SanskritPhonemizer.phonemize(probe))
  }
}

// MARK: - Speed and duration never touch identity

@Test func speedDoesNotChangeFinalVowelIdentity() {
  for word in ["सञ्जय", "कदाचन", "कर्मणि", "अहम्", "युयुत्सवः", "मामकाः", "भूर्मा"] {
    let reference = phonemes(word)
    let referenceTokens = tokens(word)
    // Every delivery differs in speed and pause length only.
    for delivery in [SanskritDelivery.learning, .recitation, .fast, .unshaped] {
      _ = SanskritProsody.segments(for: word, configuration: delivery.prosody)
      #expect(phonemes(word) == reference, "\(word): delivery changed the phonemes")
      #expect(tokens(word) == referenceTokens, "\(word): delivery changed the tokens")
    }
  }
}

/// The duration repairs scale time. They must never touch a phoneme, and must
/// never reach a long final vowel or a closed syllable.
@Test func closureRepairsScaleOnlyWhatTheyShould() {
  // A final short vowel is scaled down.
  for word in ["सञ्जय", "कदाचन", "कर्मणि", "भवति"] {
    let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
      phonemes(word), intent: .closureRepairs
    )
    #expect(scale?.last ?? 1 < 1.0, "\(word): the final short vowel was not shortened")
  }
  // A final long vowel is left alone.
  for word in ["कर्मणी", "समवेता", "शरीरा", "भूर्मा"] {
    let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
      phonemes(word), intent: .closureRepairs
    )
    #expect(scale?.allSatisfy { $0 == 1.0 } == true,
            "\(word): a long final vowel was scaled")
  }
  // A closed syllable is left alone.
  for word in ["अहम्", "भगवान्", "तत्", "कृत्"] {
    let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
      phonemes(word), intent: .closureRepairs
    )
    #expect(scale?.allSatisfy { $0 == 1.0 } == true,
            "\(word): a closed syllable was scaled")
  }
  // And no repair alters a phoneme anywhere.
  for word in ["सञ्जय", "कर्मणि", "मामकाः", "युयुत्सवः", "अहम्"] {
    let before = phonemes(word)
    _ = SanskritProsodyPlanner.durationScaleForPhonemes(before, intent: .closureRepairs)
    #expect(phonemes(word) == before)
    #expect(tokens(word) == SanskritTokenAudit.audit(text: word).tokenIDs)
  }
}

// MARK: - The earlier vowel fixes must not regress

@Test func earlierVowelFixesSurviveTheClosureWork() {
  for (a, b) in [("के", "की"), ("चै", "चे"), ("को", "कू"), ("क", "का"),
                 ("कि", "की"), ("कु", "कू")] {
    #expect(phonemes(a) != phonemes(b), "\(a)/\(b) collapsed")
    #expect(tokens(a) != tokens(b))
  }
  #expect(phonemes("क्षेत्रे") == "kʂeːtɾeː")
  #expect(phonemes("समवेता") == "samaʋeːtaː")
  #expect(phonemes("फलेषु") == "pʰaleːʂu")
  #expect(phonemes("अधिकारस्ते") == "adʰikaːɾasteː")
  #expect(phonemes("चैव") == "caɪʋa")
  #expect(phonemes("कर्मणि") == "kaɾmaɳi")
  #expect(phonemes("धर्मक्षेत्रे") == "dʰaɾmakʂeːtɾeː")
}
