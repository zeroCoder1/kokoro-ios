import Foundation
import Testing
@testable import KokoroSwift

// Third-pass regression coverage.
//
// The second pass fixed the systematic ए→ई percept and the spurious visarga
// syllable. These tests exist to keep both fixed, and to pin the behaviours
// the third-pass diagnosis proved correct at the frontend so that a later
// change cannot "fix" an acoustic symptom by corrupting the phonemes.
//
// Names follow this package's convention — descriptive, no `test` prefix, as
// swift-testing uses. The mapping to the names in the brief is in the report.
//
// Evidence: Artifacts/sanskrit/diagnostics/v2-refinement-analysis.md

private func analyze(_ text: String, _ options: SanskritOptions = .default)
  -> SanskritPhonemizer.Result
{
  SanskritPhonemizer.analyze(text, options: options)
}

private func phonemes(_ text: String) -> String { SanskritPhonemizer.phonemize(text) }

/// Symbols recovered by decoding the token ids — the end of the pipeline.
private func decoded(_ text: String) -> [String] {
  SanskritTokenAudit.audit(text: text).decoded
}

// MARK: - The ए fix must not come back

/// The v2 correction, locked at all four stages the brief names: canonical
/// form, Kokoro phonemes, token ids, and the symbols decoded back from them.
@Test func sanskritEAndLongIRemainDistinctThroughTheWholePipeline() {
  let pairs: [(e: String, i: String)] = [
    ("के", "की"), ("ते", "ती"), ("मे", "मी"), ("से", "सी"),
    ("ले", "ली"), ("वे", "वी"), ("रे", "री"), ("पे", "पी"),
  ]
  for pair in pairs {
    let e = analyze(pair.e)
    let i = analyze(pair.i)
    #expect(e.canonical != i.canonical, "\(pair.e)/\(pair.i) canonical collapsed")
    #expect(e.kokoroPhonemes != i.kokoroPhonemes, "\(pair.e)/\(pair.i) IPA collapsed")

    let eTokens = SanskritTokenAudit.audit(text: pair.e)
    let iTokens = SanskritTokenAudit.audit(text: pair.i)
    #expect(eTokens.tokenIDs != iTokens.tokenIDs, "\(pair.e)/\(pair.i) tokens collapsed")
    #expect(eTokens.decoded != iTokens.decoded, "\(pair.e)/\(pair.i) decoded collapsed")
    #expect(eTokens.roundTrips && iTokens.roundTrips)

    // The specific direction of the old bug: an ए word must never come back
    // carrying ई's vowel.
    #expect(e.kokoroPhonemes.contains("eː"))
    #expect(!e.kokoroPhonemes.contains("iː"))
  }
}

/// The four words that were reported as sounding wrong, against the ई-form
/// they were heard as. These are whole-word pairs, not syllables.
@Test func theReportedWordsStayDistinctFromTheirLongIForms() {
  let cases: [(word: String, wrong: String, expected: String)] = [
    ("क्षेत्रे", "क्षेत्री", "kʂeːtɾeː"),
    ("कुरुक्षेत्रे", "कुरुक्षेत्री", "kuɾukʂeːtɾeː"),
    ("समवेता", "समवीता", "samaʋeːtaː"),
    ("फलेषु", "फलीषु", "pʰaleːʂu"),
    ("अधिकारस्ते", "अधिकारस्ती", "adʰikaːɾasteː"),
  ]
  for item in cases {
    #expect(phonemes(item.word) == item.expected, "\(item.word) gave \(phonemes(item.word))")
    #expect(phonemes(item.word) != phonemes(item.wrong),
            "\(item.word) collapsed onto \(item.wrong)")
    #expect(SanskritTokenAudit.audit(text: item.word).tokenIDs
            != SanskritTokenAudit.audit(text: item.wrong).tokenIDs)
    #expect(decoded(item.word) != decoded(item.wrong))
  }
}

/// क्षेत्रे ends on ए and nothing else — the single assertion the original
/// report turned on.
@Test func kshetreEndsOnTheEVowel() {
  let result = analyze("क्षेत्रे")
  #expect(result.canonical == "kzetre")
  #expect(result.kokoroPhonemes == "kʂeːtɾeː")
  #expect(result.kokoroPhonemes.hasSuffix("eː"))
  #expect(decoded("क्षेत्रे").suffix(2) == ["e", "ː"])
}

// MARK: - Visarga

/// Canonical visarga is its own segment and is never `ह`, `ह्` or `हा`.
@Test func visargaIsNeverHaAtTheCanonicalLayer() {
  #expect(analyze("कः").canonical == "kaH")
  #expect(analyze("कह").canonical == "kaha")
  #expect(analyze("कह्").canonical == "kah")
  #expect(analyze("कहा").canonical == "kahA")
  #expect(Set(["कः", "कह", "कह्", "कहा"].map { analyze($0).canonical }).count == 4)
}

/// The v2 fix: no inherent vowel is ever attached to a visarga.
@Test func visargaNeverReceivesAnInherentVowel() {
  let words = ["अः", "कः", "रामः", "नमः", "योगः", "अर्जुनः",
               "युयुत्सवः", "पाण्डवाः", "मामकाः", "पुनः"]
  for word in words {
    let produced = phonemes(word)
    #expect(produced.hasSuffix("h"), "\(word) does not end on the visarga: \(produced)")
    #expect(!produced.hasSuffix("ha"), "\(word) grew an echo syllable: \(produced)")
    // Not dropped, and not doubled.
    #expect(produced.filter { $0 == "h" }.count
            == analyze(word).canonical.filter { $0 == "H" || $0 == "h" }.count,
            "\(word) duplicated or lost its h: \(produced)")
  }
  // Word-internal too.
  #expect(phonemes("दुःख") == "duhkʰa")
  #expect(phonemes("अन्तःकरण") == "antahkaɾaɳa")
}

/// A visarga never claims to be faithful.
@Test func visargaAlwaysReportsItsApproximation() {
  for word in ["अः", "कः", "रामः", "नमः", "योगः", "अर्जुनः", "युयुत्सवः",
               "पाण्डवाः", "मामकाः", "दुःख", "अन्तःकरण", "पुनः"] {
    #expect(analyze(word).warnings.contains {
      $0.text.hasPrefix("KOKORO_APPROXIMATED_VISARGA")
    }, "\(word) claimed a faithful visarga")
  }
}

/// A word boundary after a visarga survives.
@Test func aWordBoundaryAfterVisargaSurvives() {
  #expect(phonemes("रामः करोति") == "ɾaːmah kaɾoːti")
  #expect(phonemes("मामकाः पाण्डवाश्चैव") == "maːmakaːh paːɳɖaʋaːʃcaɪʋa")
  #expect(phonemes("मामकाः पाण्डवाश्चैव").filter { $0 == " " }.count == 1)
}

// MARK: - Long vowels before visarga

/// Every long vowel keeps its length mark when a visarga follows. The
/// acoustic model shortens the vowel it is given — measured, and reported —
/// but that must never be true of the symbols we send.
@Test func longVowelsSurviveBeforeVisarga() {
  let cases: [(String, String, String)] = [
    ("काः", "kAH", "kaːh"),
    ("रामाः", "rAmAH", "ɾaːmaːh"),
    ("पाण्डवाः", "pARqavAH", "paːɳɖaʋaːh"),
    ("मामकाः", "mAmakAH", "maːmakaːh"),
    ("धीः", "DIH", "dʰiːh"),
    ("भूः", "BUH", "bʰuːh"),
    ("हरेः", "hareH", "haɾeːh"),
    ("गुरोः", "guroH", "ɡuɾoːh"),
  ]
  for (word, canonical, ipa) in cases {
    let result = analyze(word)
    #expect(result.canonical == canonical, "\(word) gave \(result.canonical)")
    #expect(result.kokoroPhonemes == ipa, "\(word) gave \(result.kokoroPhonemes)")
    // The length mark is present, and it is before the h rather than after.
    #expect(result.kokoroPhonemes.contains("ː"), "\(word) lost its length mark")
    let scalars = Array(result.kokoroPhonemes.unicodeScalars)
    #expect(scalars.dropLast().last == "ː", "\(word) has ː in the wrong place")
    #expect(SanskritTokenAudit.audit(text: word).roundTrips)
  }
}

/// The short/long contrast survives the visarga: कः is not काः.
@Test func visargaDoesNotCollapseVowelLength() {
  for (short, long) in [("कः", "काः"), ("रामः", "रामाः"), ("गुरुः", "गुरोः")] {
    #expect(phonemes(short) != phonemes(long))
    #expect(SanskritTokenAudit.audit(text: short).tokenIDs
            != SanskritTokenAudit.audit(text: long).tokenIDs)
  }
}

// MARK: - Avagraha

/// Avagraha is silent, is not a word break, and survives as structure.
@Test func avagrahaStaysASilentBoundary() {
  let cases: [(String, String)] = [
    ("सोऽहम्", "soːham"),
    ("कोऽपि", "koːpi"),
    ("सङ्गोऽस्तु", "saŋɡoːstu"),
    ("सङ्गोऽस्त्वकर्मणि", "saŋɡoːstʋakaɾmaɳi"),
    ("तेऽपि", "teːpi"),
  ]
  for (word, expected) in cases {
    #expect(phonemes(word) == expected, "\(word) gave \(phonemes(word))")
    // Not spoken as a consonant, and not a word break.
    #expect(!phonemes(word).contains(" "), "\(word) gained a word break")
    #expect(analyze(word).canonical.contains("'"), "\(word) lost the avagraha")
    // Retained as a boundary, so source alignment survives for highlighting.
    #expect(analyze(word).units.contains(.boundary(.elision)))
  }
  #expect(SanskritBoundary.elision.isPause == false)
  #expect(SanskritProsodyConfiguration.default.pause(for: .elision) == 0)
}

// MARK: - Daṇḍa prosody

@Test func dandaAndDoubleDandaRemainDistinctAndOrdered() {
  #expect(phonemes("कर्म । योग") == "kaɾma, joːɡa")
  #expect(phonemes("कर्म ॥ योग") == "kaɾma. joːɡa")
  #expect(Set(["कर्म योग", "कर्म । योग", "कर्म ॥ योग"].map(phonemes)).count == 3)

  let configuration = SanskritProsodyConfiguration.default
  #expect(configuration.pause(for: .verse) > configuration.pause(for: .pada))
  #expect(configuration.pause(for: .pada) > configuration.pause(for: .word))

  // The configured pause has to beat the gap the model already produces on
  // its own (~350 ms measured), or configuring one makes the verse less
  // separated than leaving it alone.
  #expect(configuration.padaPause > 0.35)
  #expect(configuration.versePause > configuration.padaPause)
}

@Test func realShlokaLinesSegmentIntoPadas() {
  let cases: [(String, Int, SanskritBoundary)] = [
    ("अर्जुन उवाच ।", 1, .pada),
    ("धर्मक्षेत्रे कुरुक्षेत्रे ।", 1, .pada),
    ("सञ्जय उवाच ॥", 1, .verse),
    ("योगः कर्मसु कौशलम् ॥", 1, .verse),
  ]
  for (line, count, boundary) in cases {
    let segments = SanskritProsody.segments(for: line)
    #expect(segments.count == count, "\(line) gave \(segments.count) segments")
    #expect(segments.last?.boundary == boundary, "\(line) ended on the wrong boundary")
  }
  // A two-pāda śloka splits in two, with the stronger pause last.
  let shloka = "धर्मक्षेत्रे कुरुक्षेत्रे ।\nमामकाः सञ्जय ॥"
  let segments = SanskritProsody.segments(for: shloka)
  #expect(segments.count == 2)
  #expect(segments[1].pauseAfter > segments[0].pauseAfter)
}

// MARK: - Clusters still under review

/// The clusters the third pass singled out. None may gain a vowel, drop a
/// consonant, or lose aspiration.
@Test func theRemainingWeakClustersParseCleanly() {
  let cases: [(String, String, String)] = [
    ("र्मक्ष", "rmakza", "ɾmakʂa"),
    ("श्चै", "ScE", "ʃcaɪ"),
    ("ण्ये", "Rye", "ɳjeː"),
    ("र्भू", "rBU", "ɾbʰuː"),
    ("ङ्गो", "Ngo", "ŋɡoː"),
    ("स्त्व", "stva", "stʋa"),
    ("निर्भ", "nirBa", "niɾbʰa"),
    ("भ्युत्थ", "ByutTa", "bʰjuttʰa"),
    ("त्थ", "tTa", "ttʰa"),
    ("त्म", "tma", "tma"),
    ("ञ्ज", "Yja", "ɲɟa"),
    ("सृ", "sf", "sɾɪ"),
  ]
  for (cluster, canonical, ipa) in cases {
    let result = analyze(cluster)
    #expect(result.canonical == canonical, "\(cluster) gave \(result.canonical)")
    #expect(result.kokoroPhonemes == ipa, "\(cluster) gave \(result.kokoroPhonemes)")
    #expect(SanskritTokenAudit.audit(text: cluster).roundTrips)
  }
}

/// The specific wrong expansions the brief names, asserted as impossible.
@Test func clustersNeverExpandIntoSeparateSyllables() {
  #expect(phonemes("क्ष") == "kʂa")
  #expect(phonemes("क्ष") != phonemes("कष"))       // not कष
  #expect(phonemes("स्त्व") == "stʋa")
  #expect(phonemes("स्त्व") != phonemes("सतव"))    // not सतव
  #expect(phonemes("त्थ") == "ttʰa")
  #expect(phonemes("त्थ") != phonemes("ततह"))      // not ततह
  #expect(phonemes("र्भू") == "ɾbʰuː")
  #expect(phonemes("र्भू") != phonemes("रभू"))     // no extra inherent vowel
  #expect(phonemes("भ्य") == "bʰja")
  #expect(phonemes("भ्य") != phonemes("भिया"))     // not भिया
  #expect(phonemes("ञ्ज") == "ɲɟa")
  #expect(phonemes("ञ्ज") != phonemes("नज"))       // not नज

  // Aspiration survives inside every cluster.
  for (aspirated, plain) in [("त्थ", "त्त"), ("र्भ", "र्ब"), ("द्ध", "द्द"), ("भ्य", "ब्य")] {
    #expect(phonemes(aspirated) != phonemes(plain), "\(aspirated) lost its aspiration")
    #expect(phonemes(aspirated).contains("ʰ"))
  }
}

@Test func verseWordsWithHardClustersKeepTheirShape() {
  let cases: [(String, String)] = [
    ("धर्मक्षेत्रे", "dʰaɾmakʂeːtɾeː"),
    ("पाण्डवाश्चैव", "paːɳɖaʋaːʃcaɪʋa"),
    ("कर्मण्येव", "kaɾmaɳjeːʋa"),
    ("हेतुर्भूर्मा", "heːtuɾbʰuːɾmaː"),
    ("सङ्गोऽस्त्वकर्मणि", "saŋɡoːstʋakaɾmaɳi"),
    ("ग्लानिर्भवति", "ɡlaːniɾbʰaʋati"),
    ("अभ्युत्थानम्", "abʰjuttʰaːnam"),
    ("तदात्मानम्", "tadaːtmaːnam"),
    ("सञ्जय", "saɲɟaja"),
    ("सृजाम्यहम्", "sɾɪɟaːmjaham"),
  ]
  for (word, expected) in cases {
    #expect(phonemes(word) == expected, "\(word) gave \(phonemes(word))")
  }
}

// MARK: - Nasals and sibilants

/// सञ्जय's ञ must stay palatal. Collapsing it to dental n is the failure the
/// brief names.
@Test func thePalatalNasalStaysPalatal() {
  #expect(phonemes("सञ्जय") == "saɲɟaja")
  #expect(phonemes("सञ्जय").contains("ɲ"))
  #expect(!phonemes("सञ्जय").contains("n"))
  #expect(phonemes("सञ्जय") != phonemes("सनजय"))
  #expect(phonemes("सञ्जय") != phonemes("सन्जय"))

  // All five nasals stay five.
  let nasals = ["सङ्ग", "सञ्जय", "पाण्डव", "सन्त", "सम्पद्"].map(phonemes)
  #expect(Set(nasals).count == 5)
  #expect(Set(["ŋ", "ɲ", "ɳ", "n", "m"].map { nasal in
    nasals.first { $0.contains(nasal) } != nil
  }) == [true])
}

@Test func theThreeSibilantsStayThree() {
  #expect(phonemes("शक्ति") == "ʃakti")
  #expect(phonemes("षट्") == "ʂaʈ")
  #expect(phonemes("सत्") == "sat")
  #expect(Set(["शक्ति", "षट्", "सत्"].map(phonemes)).count == 3)

  for word in ["कृष्ण", "क्षेत्र", "श्रद्धा", "शास्त्र", "संशय"] {
    #expect(SanskritTokenAudit.audit(text: word).roundTrips)
  }
  // ष in कृष्ण and क्षेत्र is retroflex, not the palatal of श्रद्धा.
  #expect(phonemes("कृष्ण").contains("ʂ"))
  #expect(phonemes("श्रद्धा").contains("ʃ"))
  #expect(!phonemes("श्रद्धा").contains("ʂ"))
}

@Test func anusvaraAndChandrabinduStayApartFromPlainNasals() {
  #expect(phonemes("संयुक्त") == "sãjukta")
  #expect(phonemes("संशय") == "sãʃaja")
  #expect(phonemes("सम्पद्") == "sampad")
  #expect(phonemes("संयुक्त") != phonemes("सम्युक्त"))
  #expect(phonemes("हुँ") == "hũ")
  #expect(phonemes("हुँ") != phonemes("हु"))
  #expect(phonemes("हुँ") != phonemes("हुम्"))
}

// MARK: - Vocalic ṛ

/// Canonical stays `f`. Only the Kokoro layer approximates, and it says so.
@Test func vocalicRStaysCanonicalAndReportsItsApproximation() {
  let cases: [(String, String, String)] = [
    ("कृष्ण", "kfzRa", "kɾɪʂɳa"),
    ("सृजाम्यहम्", "sfjAmyaham", "sɾɪɟaːmjaham"),
    ("हृषीकेश", "hfzIkeSa", "hɾɪʂiːkeːʃa"),
    ("कृत", "kfta", "kɾɪta"),
    ("प्रकृति", "prakfti", "pɾakɾɪti"),
    ("वृत्ति", "vftti", "ʋɾɪtti"),
    ("पृथ्वी", "pfTvI", "pɾɪtʰʋiː"),
    ("मृत्यु", "mftyu", "mɾɪtju"),
  ]
  for (word, canonical, ipa) in cases {
    let result = analyze(word)
    #expect(result.canonical == canonical, "\(word) gave \(result.canonical)")
    #expect(result.kokoroPhonemes == ipa, "\(word) gave \(result.kokoroPhonemes)")
    #expect(result.warnings.contains { $0.text.contains("vocalic ṛ") },
            "\(word) approximated ṛ silently")
  }
  // The alternative realisation is available and genuinely different.
  var south = SanskritOptions.default
  south.vocalicLiquid = .ru
  #expect(analyze("कृष्ण", south).kokoroPhonemes == "kɾuʂɳa")
  // But the canonical form is identical either way — the choice is acoustic.
  #expect(analyze("कृष्ण", south).canonical == analyze("कृष्ण").canonical)
}

// MARK: - Speed

/// Speed is an acoustic control and must never reach the phonemes. Nothing in
/// the Sanskrit path takes a speed argument, which is the structural
/// guarantee; this pins it.
@Test func speedNeverChangesThePhonemeOrTokenSequence() {
  for verse in ["धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।",
                "मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥"] {
    let reference = analyze(verse)
    let tokens = SanskritTokenAudit.audit(phonemes: reference.kokoroPhonemes).tokenIDs
    let segments = SanskritProsody.segments(for: verse).map(\.phonemes)
    for _ in 0 ..< 4 {
      let again = analyze(verse)
      #expect(again.kokoroPhonemes == reference.kokoroPhonemes)
      #expect(SanskritTokenAudit.audit(phonemes: again.kokoroPhonemes).tokenIDs == tokens)
      #expect(SanskritProsody.segments(for: verse).map(\.phonemes) == segments)
    }
  }
}

// MARK: - Token round trip

/// Every sound Sanskrit needs, including the ones only Sanskrit uses.
@Test func tokenRoundTripHoldsForSanskritSpecificPhonemes() {
  var probes = ["रामः", "दुःख", "हुँ", "संस्कृत", "अङ्ग", "क्षेत्रज्ञ", "ॐ", "सोऽहम्",
                "कृष्ण", "ॠकार", "ऌकार", "ॡकार", "सञ्जय", "पाण्डवाश्चैव",
                "अभ्युत्थानम्", "सङ्गोऽस्त्वकर्मणि", "हृषीकेश"]
  for sign in ["", "ा", "ि", "ी", "ु", "ू", "ृ", "ॄ", "ॢ", "ॣ", "े", "ै", "ो", "ौ"] {
    probes.append("क" + sign)
  }
  for consonant in "कखगघङचछजझञटठडढणतथदधनपफबभमयरलवशषसह" {
    probes.append(String(consonant) + "ा")
  }
  for probe in probes {
    let audit = SanskritTokenAudit.audit(text: probe)
    #expect(audit.roundTrips, "\(probe) did not round trip:\n\(audit.summary)")
  }
}
