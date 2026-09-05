import Foundation
import Testing
@testable import KokoroSwift

// Final-pass regression coverage.
//
// Names follow this package's convention — descriptive, no `test` prefix.
// Evidence: Artifacts/sanskrit/diagnostics/final-refinement-analysis.md
//
// Nothing here was added to make audio sound better. Every assertion pins a
// frontend property that a diagnostic run proved correct, so a later change
// cannot "fix" an acoustic symptom by corrupting the phonemes.

private func analyze(_ text: String, _ options: SanskritOptions = .default)
  -> SanskritPhonemizer.Result
{ SanskritPhonemizer.analyze(text, options: options) }

private func phonemes(_ text: String) -> String { SanskritPhonemizer.phonemize(text) }
private func tokens(_ text: String) -> [Int] { SanskritTokenAudit.audit(text: text).tokenIDs }
private func decoded(_ text: String) -> [String] { SanskritTokenAudit.audit(text: text).decoded }

// MARK: - Every vowel contrast, at every stage

/// Four stages for each pair: canonical, IPA, token ids, decoded symbols.
private func assertDistinct(_ a: String, _ b: String, _ label: String) {
  #expect(analyze(a).canonical != analyze(b).canonical, "\(label): canonical collapsed")
  #expect(phonemes(a) != phonemes(b), "\(label): IPA collapsed")
  #expect(tokens(a) != tokens(b), "\(label): tokens collapsed")
  #expect(decoded(a) != decoded(b), "\(label): decoded symbols collapsed")
}

@Test func previousSanskritVowelFixesRemainStable() {
  for (e, i) in [("के", "की"), ("ते", "ती"), ("मे", "मी"), ("से", "सी"),
                 ("ले", "ली"), ("वे", "वी"), ("रे", "री"), ("पे", "पी")] {
    assertDistinct(e, i, "\(e)/\(i)")
    #expect(phonemes(e).contains("eː"))
    #expect(!phonemes(e).contains("iː"))
  }
  for (word, wrong) in [("क्षेत्रे", "क्षेत्री"), ("समवेता", "समवीता"),
                        ("फलेषु", "फलीषु"), ("अधिकारस्ते", "अधिकारस्ती"),
                        ("कुरुक्षेत्रे", "कुरुक्षेत्री")] {
    assertDistinct(word, wrong, "\(word)/\(wrong)")
  }
  #expect(phonemes("क्षेत्रे") == "kʂeːtɾeː")
  #expect(phonemes("समवेता") == "samaʋeːtaː")
  #expect(phonemes("फलेषु") == "pʰaleːʂu")
  #expect(phonemes("अधिकारस्ते") == "adʰikaːɾasteː")
}

/// The four contrasts the brief adds this pass, beyond ए/ई.
@Test func everySanskritVowelContrastSurvivesTheWholePipeline() {
  assertDistinct("चै", "चे", "ऐ/ए")          // ऐ != ए
  assertDistinct("को", "कू", "ओ/ऊ")          // ओ != ऊ
  assertDistinct("क", "का", "अ/आ")           // आ != अ
  assertDistinct("कु", "कू", "उ/ऊ")          // ऊ != उ
  assertDistinct("के", "की", "ए/ई")          // ए != ई

  #expect(phonemes("चै") == "caɪ")
  #expect(phonemes("चे") == "ceː")
  #expect(phonemes("को") == "koː")
  #expect(phonemes("कू") == "kuː")
  #expect(phonemes("क") == "ka")
  #expect(phonemes("का") == "kaː")
  #expect(phonemes("कु") == "ku")

  // All fourteen vowels produce fourteen different readings on the same onset.
  let all = ["क", "का", "कि", "की", "कु", "कू", "कृ", "कॄ", "कॢ", "कॣ",
             "के", "कै", "को", "कौ"]
  #expect(Set(all.map(phonemes)).count == all.count, "two vowels collapsed")
}

/// चैव specifically: the ऐ must not flatten to ए.
@Test func chaivaPreservesAi() {
  #expect(phonemes("चैव") == "caɪʋa")
  #expect(phonemes("चैव") != phonemes("चेव"))
  #expect(analyze("चैव").canonical == "cEva")
  #expect(phonemes("पाण्डवाश्चैव").contains("caɪ"))
  #expect(!phonemes("पाण्डवाश्चैव").contains("ceː"))
}

// MARK: - Visarga

/// Canonical visarga is its own element, distinct from every form of ह.
@Test func visargaIsCanonicalAndNonSyllabic() {
  #expect(analyze("कः").canonical == "kaH")
  #expect(analyze("कह").canonical == "kaha")
  #expect(analyze("कह्").canonical == "kah")
  #expect(analyze("कहा").canonical == "kahA")
  #expect(Set(["कः", "कह", "कह्", "कहा"].map { analyze($0).canonical }).count == 4)

  // Non-syllabic: the visarga adds a consonant and never a vowel, so the
  // vowel count is unchanged by writing it.
  for (bare, withVisarga) in [("क", "कः"), ("राम", "रामः"), ("नम", "नमः"),
                              ("योग", "योगः"), ("पुन", "पुनः")] {
    let vowels = { (s: String) in s.filter { "aeiouɪʊɛɔə".contains($0) }.count }
    #expect(vowels(phonemes(bare)) == vowels(phonemes(withVisarga)),
            "\(withVisarga) gained a vowel: \(phonemes(withVisarga))")
  }
}

@Test func visargaDoesNotMapToHaAndGainsNoInherentVowel() {
  for word in ["अः", "कः", "रामः", "अर्जुनः", "योगः", "युयुत्सवः", "नमः",
               "पुनः", "मामकाः", "पाण्डवाः", "काः", "भूः", "धीः", "हरेः", "गुरोः"] {
    let produced = phonemes(word)
    #expect(produced.hasSuffix("h"), "\(word) does not end on the visarga: \(produced)")
    #expect(!produced.hasSuffix("ha"), "\(word) became ha: \(produced)")
    #expect(!produced.hasSuffix("haː"), "\(word) became hā: \(produced)")
    #expect(analyze(word).warnings.contains {
      $0.text.hasPrefix("KOKORO_APPROXIMATED_VISARGA")
    }, "\(word) claimed a faithful visarga")
  }
  // Word-internal: दुःख stays two syllables.
  #expect(phonemes("दुःख") == "duhkʰa")
  #expect(phonemes("अन्तःकरण") == "antahkaɾaɳa")
  #expect(phonemes("दुःख").filter { "aeiou".contains($0) }.count == 2)
}

// MARK: - Long vowels before visarga

@Test func preVisargaLongVowelSurvives() {
  let cases: [(String, String, String)] = [
    ("काः", "kAH", "kaːh"), ("माः", "mAH", "maːh"),
    ("रामाः", "rAmAH", "ɾaːmaːh"), ("पाण्डवाः", "pARqavAH", "paːɳɖaʋaːh"),
    ("मामकाः", "mAmakAH", "maːmakaːh"),
    ("भूः", "BUH", "bʰuːh"), ("धीः", "DIH", "dʰiːh"),
    ("हरेः", "hareH", "haɾeːh"), ("गुरोः", "guroH", "ɡuɾoːh"),
  ]
  for (word, canonical, ipa) in cases {
    let result = analyze(word)
    #expect(result.canonical == canonical, "\(word) gave \(result.canonical)")
    #expect(result.kokoroPhonemes == ipa, "\(word) gave \(result.kokoroPhonemes)")
    // The length mark sits immediately before the h, not after it.
    let scalars = Array(result.kokoroPhonemes.unicodeScalars)
    #expect(scalars.last == "h")
    #expect(scalars.dropLast().last == "ː", "\(word) has ː in the wrong place")
  }
  // The visarga does not consume the vowel: short and long stay apart.
  for (short, long) in [("कः", "काः"), ("मः", "माः"), ("भुः", "भूः"),
                        ("धिः", "धीः"), ("रामः", "रामाः")] {
    assertDistinct(short, long, "\(short)/\(long)")
  }
}

// MARK: - Vocalic ṛ

@Test func vocalicRRemainsCanonical() {
  let cases: [(String, String, String)] = [
    ("ऋ", "f", "ɾɪ"), ("कृ", "kf", "kɾɪ"), ("कृत", "kfta", "kɾɪta"),
    ("कृष्ण", "kfzRa", "kɾɪʂɳa"), ("सृ", "sf", "sɾɪ"), ("सृज", "sfja", "sɾɪɟa"),
    ("सृजामि", "sfjAmi", "sɾɪɟaːmi"), ("सृजाम्यहम्", "sfjAmyaham", "sɾɪɟaːmjaham"),
    ("हृषीकेश", "hfzIkeSa", "hɾɪʂiːkeːʃa"), ("वृत्ति", "vftti", "ʋɾɪtti"),
    ("प्रकृति", "prakfti", "pɾakɾɪti"), ("पृथ्वी", "pfTvI", "pɾɪtʰʋiː"),
    ("मृत्यु", "mftyu", "mɾɪtju"),
  ]
  for (word, canonical, ipa) in cases {
    let result = analyze(word)
    #expect(result.canonical == canonical, "\(word) gave \(result.canonical)")
    #expect(result.kokoroPhonemes == ipa, "\(word) gave \(result.kokoroPhonemes)")
    #expect(result.warnings.contains { $0.text.contains("vocalic ṛ") },
            "\(word) approximated ṛ silently")
  }
  // Never silently turned into any of the forms the brief forbids.
  #expect(analyze("कृ").canonical != analyze("करि").canonical)
  #expect(analyze("कृ").canonical != analyze("करु").canonical)
  #expect(analyze("कृ").canonical != analyze("किर").canonical)
  #expect(analyze("कृ").canonical != analyze("क्री").canonical)
  // Short and long stay apart.
  assertDistinct("कृ", "कॄ", "ऋ/ॠ")
}

// MARK: - Palatal nasal

@Test func palatalNasalRemainsDistinctCanonically() {
  for word in ["सञ्जय", "ज्ञान", "विज्ञान", "पञ्च", "अञ्जलि", "चञ्चल", "यज्ञ"] {
    #expect(analyze(word).canonical.contains("Y"), "\(word) lost its ñ canonically")
    #expect(phonemes(word).contains("ɲ"), "\(word) lost its ɲ: \(phonemes(word))")
    #expect(SanskritTokenAudit.audit(text: word).roundTrips)
  }
  // ñ is not n, ṇ, ṅ, or an anusvāra mark.
  #expect(phonemes("पञ्च") != phonemes("पन्च"))
  #expect(phonemes("पञ्च") != phonemes("पण्च"))
  #expect(phonemes("पञ्च") != phonemes("पङ्च"))
  #expect(Set(["ङ", "ञ", "ण", "न", "म"].map { phonemes($0 + "ा") }).count == 5)
}

@Test func sanjayaDoesNotCollapseToDentalN() {
  #expect(phonemes("सञ्जय") == "saɲɟaja")
  #expect(!phonemes("सञ्जय").contains("n"))
  // No vowel is inserted between ñ and j.
  #expect(!phonemes("सञ्जय").contains("ɲa"))
  #expect(analyze("सञ्जय").canonical == "saYjaya")
}

/// सञ्जय and संजय are genuine Sanskrit homophones: an anusvāra before a
/// palatal stop *is* the palatal nasal. They differ canonically, which is
/// where the spelling lives, and converge in pronunciation, which is correct.
/// Documented here so the convergence can never be mistaken for a collapse.
@Test func sanjayaAndSamjayaAreDocumentedHomophones() {
  #expect(analyze("सञ्जय").canonical == "saYjaya")
  #expect(analyze("संजय").canonical == "saMjaya")
  #expect(analyze("सञ्जय").canonical != analyze("संजय").canonical)
  // ...and deliberately the same sound.
  #expect(phonemes("सञ्जय") == phonemes("संजय"))
  #expect(phonemes("संजय") == "saɲɟaja")
}

// MARK: - Clusters

@Test func shchaClusterDoesNotGainVowel() {
  #expect(phonemes("श्च") == "ʃca")
  #expect(phonemes("श्चै") == "ʃcaɪ")
  #expect(phonemes("श्च") != phonemes("शच"))
  #expect(phonemes("पाण्डवाश्चैव") == "paːɳɖaʋaːʃcaɪʋa")
  // Exactly one vowel in the bare cluster: the inherent a.
  #expect(phonemes("श्च").filter { "aeiouɪʊ".contains($0) }.count == 1)
}

@Test func pandavashchaivaPreservesLongVowels() {
  let produced = phonemes("पाण्डवाश्चैव")
  #expect(produced == "paːɳɖaʋaːʃcaɪʋa")
  #expect(produced.filter { $0 == "ː" }.count == 2, "lost a long vowel: \(produced)")
  #expect(produced.contains("ɳɖ"))       // ण् + ड
  #expect(produced.contains("ʃc"))       // श् + च
  #expect(produced.hasSuffix("ʋa"))      // व not lost
}

@Test func rbhurPreservesLongUAndFinalR() {
  #expect(phonemes("भु") == "bʰu")
  #expect(phonemes("भू") == "bʰuː")
  #expect(phonemes("भूर्मा") == "bʰuːɾmaː")
  #expect(phonemes("हेतुर्भूर्मा") == "heːtuɾbʰuːɾmaː")
  #expect(phonemes("कर्मफलहेतुर्भूर्मा") == "kaɾmapʰalaheːtuɾbʰuːɾmaː")

  let produced = phonemes("हेतुर्भूर्मा")
  #expect(produced.contains("ɾbʰ"), "र् did not attach to भ")
  #expect(produced.contains("bʰuː"), "भ lost aspiration or ऊ lost length")
  #expect(produced.contains("uːɾm"), "the second र् vanished")
  // No inherent vowel between र् and भ, or after the final र्.
  #expect(!produced.contains("ɾabʰ"))
  #expect(!produced.contains("ɾama"))
}

@Test func stvaDoesNotGainInherentVowels() {
  #expect(phonemes("स्त्व") == "stʋa")
  #expect(phonemes("स्त्व") != phonemes("सतव"))
  #expect(phonemes("स्त्व").filter { "aeiouɪʊ".contains($0) }.count == 1)
  #expect(phonemes("सङ्गोऽस्तु") == "saŋɡoːstu")
  #expect(phonemes("सङ्गोऽस्त्वकर्मणि") == "saŋɡoːstʋakaɾmaɳi")
}

@Test func sangoUsesVelarNasalBeforeG() {
  #expect(phonemes("सङ्गो") == "saŋɡoː")
  #expect(phonemes("सङ्ग") == "saŋɡa")
  #expect(phonemes("सङ्गः") == "saŋɡah")
  #expect(phonemes("सङ्गो").contains("ŋɡ"))
  #expect(!phonemes("सङ्गो").contains("nɡ"))
  // The ओ stays long.
  #expect(phonemes("सङ्गो").contains("oː"))
}

@Test func tthaPreservesAspirationAndBothStops() {
  #expect(phonemes("त्थ") == "ttʰa")
  #expect(phonemes("उत्थ") == "uttʰa")
  #expect(phonemes("त्थ") != phonemes("थ"))       // both stops present
  #expect(phonemes("त्थ") != phonemes("त्त"))     // aspiration present
  #expect(phonemes("त्थ") != phonemes("ततह"))
  #expect(phonemes("त्थ").contains("ʰ"))
}

@Test func bhyaClusterDoesNotGainVowel() {
  #expect(phonemes("भ्य") == "bʰja")
  #expect(phonemes("भ्य") != phonemes("भिया"))
  #expect(phonemes("भ्य") != phonemes("ब्य"))     // aspiration kept
  #expect(phonemes("भ्य").filter { "aeiouɪʊ".contains($0) }.count == 1)
}

@Test func abhyutthanamPreservesShortUAndLongA() {
  let produced = phonemes("अभ्युत्थानम्")
  #expect(produced == "abʰjuttʰaːnam")
  #expect(produced.contains("bʰj"), "भ् + य broken")
  #expect(produced.contains("ju"), "उ is not short")
  #expect(produced.contains("ttʰ"), "त् + थ broken")
  #expect(produced.contains("aːn"), "आ is not long")
  #expect(produced.hasSuffix("m"), "final virāma lost")
}

@Test func dharmakshetreKeepsOneUninterruptedCluster() {
  let result = analyze("धर्मक्षेत्रे")
  #expect(result.kokoroPhonemes == "dʰaɾmakʂeːtɾeː")
  // No vowel after र्, none between म and क्, and क्ष stays k + ṣ.
  #expect(!result.kokoroPhonemes.contains("ɾa"))
  #expect(result.kokoroPhonemes.contains("ɾmak"))
  #expect(result.kokoroPhonemes.contains("kʂ"))
  #expect(phonemes("धर्मक्षेत्रे") != phonemes("धर्म क्षेत्रे"))
  // The source has no space, so neither may the output.
  #expect(!result.kokoroPhonemes.contains(" "))
}

/// A cluster inside a word never earns a pause: the prosody layer splits only
/// at boundaries, and there is none inside an orthographic word.
@Test func wordInternalClustersDoNotReceivePause() {
  for word in ["धर्मक्षेत्रे", "कर्मण्येवाधिकारस्ते", "सङ्गोऽस्त्वकर्मणि",
               "अभ्युत्थानमधर्मस्य", "ग्लानिर्भवति"] {
    let segments = SanskritProsody.segments(for: word)
    #expect(segments.count == 1, "\(word) was split into \(segments.count) segments")
    #expect(segments[0].pauseAfter == 0)
  }
}

// MARK: - Avagraha

@Test func avagrahaIsSilentButBoundaryAware() {
  for (word, expected) in [("सोऽहम्", "soːham"), ("कोऽपि", "koːpi"),
                           ("सङ्गोऽस्तु", "saŋɡoːstu"),
                           ("सङ्गोऽस्त्वकर्मणि", "saŋɡoːstʋakaɾmaɳi")] {
    #expect(phonemes(word) == expected, "\(word) gave \(phonemes(word))")
    #expect(!phonemes(word).contains(" "), "\(word) gained a word break")
    #expect(analyze(word).units.contains(.boundary(.elision)), "\(word) lost the boundary")
  }
  // Distinct from no boundary at all, from a space, and from a daṇḍa.
  #expect(SanskritBoundary.elision != SanskritBoundary.word)
  #expect(SanskritBoundary.elision != SanskritBoundary.pada)
  #expect(SanskritBoundary.elision.isPause == false)
  #expect(SanskritProsodyConfiguration.default.pause(for: .elision) == 0)
  // It is not spoken, so removing it from the source changes nothing audible.
  #expect(phonemes("सोऽहम्") == phonemes("सोहम्"))
}

// MARK: - Daṇḍa

@Test func padaPauseLongerThanWordBoundaryAndVerseLongerStill() {
  let configuration = SanskritProsodyConfiguration.default
  #expect(configuration.pause(for: .word) < configuration.pause(for: .pada))
  #expect(configuration.pause(for: .pada) < configuration.pause(for: .verse))
  for delivery in [SanskritDelivery.learning, .recitation, .traditional, .fast] {
    #expect(delivery.prosody.padaPause > delivery.prosody.wordBoundary)
    #expect(delivery.prosody.versePause > delivery.prosody.padaPause)

    // The configured value is divided by speed at render time, so what has to
    // be defensible is the gap in seconds, not the number in the struct. It
    // used to be asserted above 0.35 on the reasoning that a pause shorter
    // than Kokoro's own ~350 ms gap would make splitting worse than doing
    // nothing. That reasoning holds only at fast rates: the model's gap grows
    // as it slows — 390–460 ms at 0.80 against 550–1150 ms at 0.30 — so at a
    // slow pace it over-pauses, and the split path is what shortens it.
    //
    // The reciter's half-verse break is 410 ms, median over the 292 anuṣṭubh
    // verses that take one. Every delivery has to land in a range that break
    // could plausibly sit in.
    let gap = delivery.prosody.padaPause / Double(delivery.speed)
    #expect(gap > 0.30, "\(delivery.speed): \(gap)s is below any measured break")
    #expect(gap < 1.20, "\(delivery.speed): \(gap)s is longer than the model's own gap")
  }
}

/// A pause changes timing, never phonemes — including the visarga in front of
/// it, which must not acquire a vowel because a break follows.
@Test func dandaDoesNotModifyPhonemes() {
  #expect(phonemes("युयुत्सवः ।") == "jujutsaʋah,")
  #expect(phonemes("युयुत्सवः ॥") == "jujutsaʋah.")
  #expect(phonemes("युयुत्सवः").hasSuffix("h"))
  for suffix in [" ।", " ॥", ""] {
    let produced = phonemes("मामकाः" + suffix)
    #expect(produced.hasPrefix("maːmakaːh"), "\(suffix) changed the word: \(produced)")
    #expect(!produced.contains("ha"), "visarga gained a vowel before a pause")
  }
  // Segmenting does not rewrite the phonemes either.
  let verse = "धर्मक्षेत्रे कुरुक्षेत्रे ।\nमामकाः सञ्जय ॥"
  let joined = SanskritProsody.segments(for: verse).map(\.phonemes).joined(separator: " ")
  #expect(joined.contains("dʰaɾmakʂeːtɾeː"))
  #expect(joined.contains("maːmakaːh"))
}

// MARK: - Speed, tokens, alignment

@Test func speedDoesNotModifyTokens() {
  // No function on the Sanskrit path takes a speed, which is the structural
  // guarantee. The deliveries differ only in speed and pause length.
  #expect(SanskritDelivery.learning.speed != SanskritDelivery.recitation.speed)
  for verse in ["धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।",
                "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।"] {
    let reference = tokens(verse)
    for delivery in [SanskritDelivery.learning, .recitation, .traditional, .fast] {
      let segmented = SanskritProsody.segments(for: verse, configuration: delivery.prosody)
      #expect(!segmented.isEmpty)
      #expect(tokens(verse) == reference, "tokens moved with delivery")
    }
  }
}

@Test func sanskritTokenizerRoundTripForSpecialPhonemes() {
  var probes = ["रामः", "दुःख", "हुँ", "संस्कृत", "अङ्ग", "क्षेत्रज्ञ", "ॐ", "सोऽहम्",
                "कृष्ण", "हृषीकेश", "सञ्जय", "पाण्डवाश्चैव", "अभ्युत्थानम्",
                "सङ्गोऽस्त्वकर्मणि", "कर्मफलहेतुर्भूर्मा", "ग्लानिर्भवति",
                "ॠकार", "ऌकार", "ॡकार", "काः", "भूः", "धीः", "हरेः", "गुरोः"]
  for sign in ["", "ा", "ि", "ी", "ु", "ू", "ृ", "ॄ", "ॢ", "ॣ", "े", "ै", "ो", "ौ"] {
    probes.append("क" + sign)
  }
  for probe in probes {
    let audit = SanskritTokenAudit.audit(text: probe)
    #expect(audit.roundTrips, "\(probe) did not round trip:\n\(audit.summary)")
  }
}

/// The chain the highlighting feature needs: source characters → akṣara →
/// canonical → phonemes → token indices. These are the pipeline's own spans,
/// not an estimate.
@Test func sourceAlignmentCoversEveryAksharaInOrder() {
  for text in ["मामकाः", "धर्मक्षेत्रे", "सङ्गोऽस्त्वकर्मणि", "कृष्ण",
               "धर्मक्षेत्रे कुरुक्षेत्रे"] {
    let result = analyze(text)
    let aksharas = result.units.filter { if case .akshara = $0 { return true }; return false }
    #expect(result.alignment.count == aksharas.count,
            "\(text): \(result.alignment.count) aligned of \(aksharas.count) akṣaras")

    let tokenCount = result.tokens.count
    var previousSource = -1
    var previousToken = 0
    for entry in result.alignment {
      // In source order, non-overlapping, and inside the string.
      #expect(entry.sourceOffsets.lowerBound > previousSource)
      previousSource = entry.sourceOffsets.lowerBound
      #expect(entry.sourceOffsets.upperBound <= result.normalized.unicodeScalars.count)
      // In token order, and inside the token array.
      #expect(entry.tokenIndices.lowerBound >= previousToken)
      #expect(entry.tokenIndices.upperBound <= tokenCount,
              "\(text): token range past the end")
      previousToken = entry.tokenIndices.lowerBound
      #expect(!entry.phonemes.isEmpty)
      #expect(!entry.canonical.isEmpty)
    }
  }
  // Spot check: काः in मामकाः is the third akṣara and carries kaːh.
  let mamakah = analyze("मामकाः")
  #expect(mamakah.alignment.count == 3)
  #expect(mamakah.alignment[2].canonical == "kAH")
  #expect(mamakah.alignment[2].phonemes == "kaːh")
  #expect(mamakah.alignment.map(\.phonemes).joined() == "maːmakaːh")
}

// MARK: - The mapping outcome is typed

/// A caller cannot read the phonemes and forget the caveat: the outcome says
/// whether Kokoro has the sound, approximates it, or lacks it entirely.
@Test func mappingOutcomesReportTheirFidelity() {
  // An exact sound reports no warning; an approximation always does.
  #expect(analyze("क").warnings.isEmpty)
  #expect(analyze("कृ").warnings.contains { $0.text.hasPrefix("KOKORO_APPROXIMATION") })
  #expect(analyze("कः").warnings.contains { $0.text.hasPrefix("KOKORO_APPROXIMATED_VISARGA") })
  #expect(analyze("ळ").warnings.contains { $0.text.hasPrefix("KOKORO_UNSUPPORTED") })

  let exact = SanskritKokoroMapper.Outcome.exact("k")
  #expect(exact.isExact)
  #expect(exact.warning == nil)
  #expect(exact.phonemes == "k")
}
