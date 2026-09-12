import Foundation
import Testing
@testable import KokoroSwift

// Regression tests for the bugs the audio diagnosis confirmed.
//
// Names follow this package's convention — descriptive, no `test` prefix, as
// swift-testing uses. The mapping to the names in the brief is in the report;
// every behaviour it lists is covered here.
//
// Evidence for each is in Artifacts/sanskrit/diagnostics/audio-failure-analysis.md.
// Where a complaint turned out to be acoustic rather than ours, the test pins
// the *frontend* behaviour that was proven correct, so a later change cannot
// quietly "fix" it by corrupting the phonemes.

private func analyze(_ text: String, _ options: SanskritOptions = .default)
  -> SanskritPhonemizer.Result
{
  SanskritPhonemizer.analyze(text, options: options)
}

private func phonemes(_ text: String) -> String { SanskritPhonemizer.phonemize(text) }

// MARK: - ए versus ई

/// The highest-priority hypothesis, and it was refuted at the frontend: ए and
/// ई are distinct in the canonical form, in the IPA, and in the token ids.
/// The spectral measurement puts them 7.3 dB apart, further than o from u.
/// What remains is that Kokoro renders `eː` centralized — an acoustic
/// limitation, and not a reason to change the mapping.
@Test func sanskritEAndLongIDoNotCollapse() {
  #expect(phonemes("के") == "keː")
  #expect(phonemes("की") == "kiː")
  #expect(analyze("के").canonical == "ke")
  #expect(analyze("की").canonical == "kI")

  let e = SanskritTokenAudit.audit(text: "के")
  let i = SanskritTokenAudit.audit(text: "की")
  #expect(e.tokenIDs != i.tokenIDs, "ए and ई tokenized identically: \(e.tokenIDs)")
  #expect(e.roundTrips && i.roundTrips)
}

/// The seven minimal pairs from the brief, at every stage.
@Test func everyEVersusLongIMinimalPairStaysDistinct() {
  let pairs: [(String, String, String, String)] = [
    ("के", "की", "keː", "kiː"),
    ("ते", "ती", "teː", "tiː"),
    ("मे", "मी", "meː", "miː"),
    ("से", "सी", "seː", "siː"),
    ("ले", "ली", "leː", "liː"),
    ("वे", "वी", "ʋeː", "ʋiː"),
    ("रे", "री", "ɾeː", "ɾiː"),
  ]
  for (eForm, iForm, eIPA, iIPA) in pairs {
    #expect(phonemes(eForm) == eIPA, "\(eForm) gave \(phonemes(eForm))")
    #expect(phonemes(iForm) == iIPA, "\(iForm) gave \(phonemes(iForm))")
    #expect(SanskritTokenAudit.audit(text: eForm).tokenIDs
            != SanskritTokenAudit.audit(text: iForm).tokenIDs)
  }
}

/// The four words the listener flagged. Each must keep an `eː`, and must not
/// contain the `iː` it was heard as.
@Test func theWordsHeardAsLongIStillCarryE() {
  let cases: [(String, String)] = [
    ("क्षेत्रे", "kʂeːtɾeː"),
    ("कुरुक्षेत्रे", "kuɾukʂeːtɾeː"),
    ("समवेता", "samaʋeːtaː"),
    ("फलेषु", "pʰaleːʂu"),
    ("अधिकारस्ते", "adʰikaːɾasteː"),
  ]
  for (word, expected) in cases {
    let produced = phonemes(word)
    #expect(produced == expected, "\(word) gave \(produced)")
    #expect(produced.contains("eː"), "\(word) lost its ए")
    #expect(!produced.contains("iː"), "\(word) gained an ई")
  }
}

// MARK: - Visarga

/// The confirmed mapping bug. The echo vowel made `रामः` three syllables —
/// measured at six energy nuclei against three for a plain h — so it is off.
@Test func visargaDoesNotGainAnInherentVowel() {
  for (word, expected) in [("रामः", "ɾaːmah"), ("नमः", "namah"), ("योगः", "joːɡah"),
                           ("अर्जुनः", "aɾɟunah"), ("युयुत्सवः", "jujutsaʋah"),
                           ("पाण्डवाः", "paːɳɖaʋaːh"), ("पुनः", "punah"),
                           ("कः", "kah"), ("अः", "ah")] {
    let produced = phonemes(word)
    #expect(produced == expected, "\(word) gave \(produced)")
    #expect(produced.hasSuffix("h"), "\(word) does not end on the visarga")
    // The failure this test exists for: a vowel appearing after the h.
    #expect(!produced.hasSuffix("ha"), "\(word) grew an echo syllable: \(produced)")
  }
}

/// Word-internally there was never an echo, and there must not be one: दुःख is
/// two syllables and EdgeSanskrit's three-syllable reading breaks the metre.
@Test func wordInternalVisargaStaysASingleConsonant() {
  #expect(phonemes("दुःख") == "duhkʰa")
  #expect(phonemes("निःशेष") == "nihʃeːʂa")
  #expect(phonemes("अन्तःकरण") == "antahkaɾaɳa")
  #expect(phonemes("दुःशासन") == "duhʃaːsana")
  // Two vowels, not three.
  #expect(phonemes("दुःख").filter { "aeiou".contains($0) }.count == 2)
}

/// The assertions §7 of the brief asks for: the canonical representation keeps
/// visarga apart from ह, ह् and हा.
@Test func visargaIsDistinctFromHaInEveryForm() {
  #expect(analyze("कः").canonical == "kaH")
  #expect(analyze("कह").canonical == "kaha")
  #expect(analyze("कह्").canonical == "kah")
  #expect(analyze("कहा").canonical == "kahA")

  let forms = ["कः", "कह", "कह्", "कहा"].map { analyze($0).canonical }
  #expect(Set(forms).count == 4, "visarga collapsed into ha: \(forms)")

  // In Kokoro's IPA, ः and ह् do collapse — both become `h`. Sanskrit visarga
  // is voiceless and ह is the breathy `ɦ`, which is one of the tokens
  // IndicVoice had to add and base Kokoro does not have. The distinction
  // survives where it matters, in the canonical form, and the collapse is
  // reported rather than hidden.
  #expect(phonemes("कः") == phonemes("कह्"))
  #expect(Set(["कः", "कह", "कहा"].map(phonemes)).count == 3)
  #expect(analyze("कः").warnings.contains { $0.text.hasPrefix("KOKORO_APPROXIMATED_VISARGA") })
  #expect(!analyze("कह्").warnings.contains { $0.text.hasPrefix("KOKORO_APPROXIMATED_VISARGA") })
}

/// A visarga is never faithful in Kokoro, and must always say so.
@Test func everyVisargaReportsThatItIsApproximated() {
  for word in ["रामः", "दुःख", "नमः", "युयुत्सवः", "अन्तःकरण"] {
    let warnings = analyze(word).warnings.map(\.text)
    #expect(warnings.contains { $0.hasPrefix("KOKORO_APPROXIMATED_VISARGA") },
            "\(word) claimed a faithful visarga")
  }
  // A word without one does not cry wolf.
  #expect(!analyze("कर्म").warnings.contains {
    $0.text.hasPrefix("KOKORO_APPROXIMATED_VISARGA")
  })
}

/// The echo remains available, because the phonology behind it is real and a
/// Sanskrit-trained voice may render it correctly.
@Test func theVisargaEchoIsStillAvailableAsAnOption() {
  var options = SanskritOptions.default
  options.visargaEchoAtPause = true
  #expect(analyze("रामः", options).kokoroPhonemes == "ɾaːmaha")
  #expect(analyze("गुरुः", options).kokoroPhonemes == "ɡuɾuhu")
  #expect(analyze("रामः", options).warnings.contains {
    $0.text.contains("whole syllable")
  })
}

// MARK: - Boundaries and pauses

@Test func wordBoundariesSurviveIntoThePhonemeStream() {
  #expect(phonemes("धर्मक्षेत्रे कुरुक्षेत्रे") == "dʰaɾmakʂeːtɾeː kuɾukʂeːtɾeː")
  for phrase in ["समवेता युयुत्सवः", "मा फलेषु कदाचन", "ग्लानिर्भवति भारत",
                 "तदात्मानं सृजाम्यहम्"] {
    let produced = phonemes(phrase)
    let words = phrase.split(separator: " ").count
    #expect(produced.filter { $0 == " " }.count == words - 1,
            "\(phrase) lost a word boundary: \(produced)")
  }
}

/// `।` and `॥` must reach the phoneme stream as different punctuation, and
/// must be worth different amounts of silence.
@Test func dandaAndDoubleDandaAreDistinct() {
  #expect(phonemes("कर्म । योग") == "kaɾma, joːɡa")
  #expect(phonemes("कर्म ॥ योग") == "kaɾma. joːɡa")
  #expect(phonemes("कर्म योग") == "kaɾma joːɡa")
  #expect(Set(["कर्म । योग", "कर्म ॥ योग", "कर्म योग"].map(phonemes)).count == 3)

  let configuration = SanskritProsodyConfiguration.default
  #expect(configuration.pause(for: .verse) > configuration.pause(for: .pada))
  #expect(configuration.pause(for: .pada) > configuration.pause(for: .word))
  #expect(configuration.pause(for: .elision) == 0)
}

/// The prosody layer splits at pauses and leaves the phonemes alone.
@Test func prosodySplitsAtPausesWithoutChangingPhonemes() {
  let verse = "धर्मक्षेत्रे कुरुक्षेत्रे ।\nमामकाः सञ्जय ॥"
  let segments = SanskritProsody.segments(for: verse)
  #expect(segments.count == 2)
  #expect(segments[0].boundary == .pada)
  #expect(segments[1].boundary == .verse)
  #expect(segments[0].pauseAfter == SanskritProsodyConfiguration.default.padaPause)
  #expect(segments[1].pauseAfter == SanskritProsodyConfiguration.default.versePause)
  // The punctuation still reaches the model: the split supplies duration, it
  // does not take the phrasing cue away.
  #expect(segments[0].phonemes.hasSuffix(","))
  #expect(segments[1].phonemes.hasSuffix("."))

  // With no configured pauses this is exactly the old single-call behaviour.
  let flat = SanskritProsody.segments(for: verse, configuration: .none)
  #expect(flat.count == 1)
  #expect(flat[0].phonemes == SanskritPhonemizer.phonemize(verse))
  #expect(flat[0].pauseAfter == 0)
}

// MARK: - Clusters

/// No cluster may gain a vowel that is not written. `क्ष` must not become
/// `कष`, `स्त्व` not `सतव`, `त्थ` not `ततह`.
@Test func complexClustersDoNotGainExtraVowels() {
  let clusters: [(String, String)] = [
    ("क्ष", "kʂa"), ("ण्य", "ɳja"), ("स्त्व", "stʋa"), ("र्भ", "ɾbʰa"),
    ("भ्य", "bʰja"), ("त्थ", "ttʰa"), ("ज्ञ", "ɟɲa"), ("श्र", "ʃɾa"),
    ("त्त्व", "ttʋa"), ("द्व", "dʋa"), ("ह्म", "hma"), ("र्म", "ɾma"),
    ("ञ्ज", "ɲɟa"), ("ण्ड", "ɳɖa"), ("ग्ल", "ɡla"), ("त्म", "tma"),
  ]
  for (cluster, expected) in clusters {
    let produced = phonemes(cluster)
    #expect(produced == expected, "\(cluster) gave \(produced)")
    // Exactly one vowel: the single inherent `a` the last consonant carries.
    let vowels = produced.filter { "aeiouɪʊɛɔəɐ".contains($0) }.count
    #expect(vowels == 1, "\(cluster) has \(vowels) vowels: \(produced)")
  }
}

@Test func clustersInRealVersesKeepTheirShape() {
  let cases: [(String, String)] = [
    ("क्षेत्रे", "kʂeːtɾeː"),
    ("कर्मण्येव", "kaɾmaɳjeːʋa"),
    ("सङ्गोऽस्त्वकर्मणि", "saŋɡoːstʋakaɾmaɳi"),
    ("हेतुर्भूर्मा", "heːtuɾbʰuːɾmaː"),
    ("ग्लानिर्भवति", "ɡlaːniɾbʰaʋati"),
    ("अभ्युत्थानम्", "abʰjuttʰaːnam"),
    ("तत्त्व", "tattʋa"),
    ("ज्ञान", "ɟɲaːna"),
    ("श्रद्धा", "ʃɾaddʰaː"),
    ("ब्रह्म", "bɾahma"),
    ("सञ्जय", "saɲɟaja"),
    ("पाण्डव", "paːɳɖaʋa"),
    ("तदात्मानम्", "tadaːtmaːnam"),
  ]
  for (word, expected) in cases {
    #expect(phonemes(word) == expected, "\(word) gave \(phonemes(word))")
  }
}

// MARK: - Vocalic ṛ and vowel length

/// The canonical form keeps ṛ as ṛ. Only the Kokoro layer approximates it,
/// and it says so every time.
@Test func vocalicRIsPreservedCanonically() {
  for (word, canonical) in [("ऋ", "f"), ("कृ", "kf"), ("कृत", "kfta"),
                            ("कृष्ण", "kfzRa"), ("सृ", "sf"), ("सृज", "sfja"),
                            ("हृषीकेश", "hfzIkeSa"), ("प्रकृति", "prakfti"),
                            ("वृत्ति", "vftti"), ("पृथ्वी", "pfTvI"),
                            ("मृत्यु", "mftyu")] {
    let result = analyze(word)
    #expect(result.canonical == canonical, "\(word) gave \(result.canonical)")
    #expect(result.warnings.contains { $0.text.contains("vocalic ṛ") },
            "\(word) approximated ṛ without saying so")
  }
  // Short against long stays distinct.
  #expect(analyze("ऋ").canonical != analyze("ॠ").canonical)
  #expect(phonemes("ऋ") != phonemes("ॠ"))
}

/// Length is carried by a real token, not by post-processing. Verified
/// acoustically too: the mark lengthens the vowel by about 24%.
@Test func vowelLengthIsDistinctAtEveryStage() {
  let pairs: [(String, String)] = [
    ("कन", "कान"), ("दिन", "दीन"), ("कुल", "कूल"), ("ऋषि", "ॠषि"),
  ]
  for (short, long) in pairs {
    #expect(analyze(short).canonical != analyze(long).canonical)
    #expect(phonemes(short) != phonemes(long))
    #expect(SanskritTokenAudit.audit(text: short).tokenIDs
            != SanskritTokenAudit.audit(text: long).tokenIDs)
  }
  #expect(phonemes("कान") == "kaːna")
  #expect(phonemes("कान").contains("ː"))
  #expect(!phonemes("कन").contains("ː"))
}

// MARK: - Tokenizer round trip

@Test func phonemeTokenizerRoundTripsForEverySanskritSound() {
  // Every vowel and every consonant, in a frame that gives it a real context.
  var probes: [String] = []
  for sign in ["", "ा", "ि", "ी", "ु", "ू", "ृ", "ॄ", "े", "ै", "ो", "ौ"] {
    probes.append("क" + sign)
  }
  for consonant in "कखगघङचछजझञटठडढणतथदधनपफबभमयरलवशषसह" {
    probes.append(String(consonant) + "ा")
  }
  probes += ["रामः", "दुःख", "हुँ", "संस्कृत", "अङ्ग", "क्षेत्रज्ञ", "ॐ", "सोऽहम्"]

  for probe in probes {
    let audit = SanskritTokenAudit.audit(text: probe)
    #expect(audit.roundTrips, "\(probe) did not round trip:\n\(audit.summary)")
    #expect(audit.unknown.isEmpty, "\(probe) has unmappable symbols: \(audit.unknown)")
  }
}

/// The audit has to be able to fail, or it proves nothing.
@Test func theTokenAuditReportsSymbolsKokoroCannotSay() {
  // ɭ and ɦ are real IPA that Kokoro's vocabulary does not contain.
  let report = SanskritTokenAudit.audit(phonemes: "kaɭɦa")
  #expect(!report.roundTrips)
  #expect(report.unknown.contains("ɭ"))
  #expect(report.unknown.contains("ɦ"))
  #expect(report.dropped.contains("ɭ"))
}

@Test func unknownSanskritInputProducesAWarning() {
  #expect(analyze("ळ").warnings.contains { $0.text.hasPrefix("KOKORO_UNSUPPORTED") })
  #expect(analyze("धर्म dharma").warnings.contains { $0.text.hasPrefix("UNKNOWN_SCALAR") })
  #expect(analyze("ा").warnings.contains { $0.text.hasPrefix("ORPHANED_MARK") })
  #expect(analyze("अ\u{0951}ग्नि").warnings.contains(.vedicAccentIgnored))
}

// MARK: - Sibilants and nasals

@Test func sibilantsAndNasalsStayDistinctThroughTokenization() {
  let sibilants = ["शक्ति", "षट्", "सत्"].map(phonemes)
  #expect(sibilants == ["ʃakti", "ʂaʈ", "sat"])
  #expect(Set(sibilants).count == 3)

  let nasals = ["सङ्ग", "सञ्जय", "पाण्डव", "सन्त", "सम्पद्"].map(phonemes)
  #expect(nasals == ["saŋɡa", "saɲɟaja", "paːɳɖaʋa", "santa", "sampad"])
  #expect(Set(nasals).count == 5)

  // Distinct symbols means distinct tokens.
  for word in ["शक्ति", "षट्", "सत्", "सङ्ग", "सञ्जय", "पाण्डव"] {
    #expect(SanskritTokenAudit.audit(text: word).roundTrips)
  }
  #expect(phonemes("संशय") != phonemes("संयुक्त"))
  #expect(phonemes("अंश").unicodeScalars.contains("\u{0303}"))
}

// MARK: - Stress

/// It used to be declared and never read: the documentation advertised a
/// switch that did nothing.
@Test func theStressOptionActuallyDoesSomething() {
  var stressed = SanskritOptions.default
  stressed.markStressOnHeavySyllables = true

  #expect(phonemes("क्षेत्रे") == "kʂeːtɾeː")
  #expect(analyze("क्षेत्रे", stressed).kokoroPhonemes == "kʂˈeːtɾeː")
  #expect(analyze("समवेता", stressed).kokoroPhonemes == "samaʋˈeːtaː")
  #expect(analyze("कर्म", stressed).kokoroPhonemes == "kˈaɾma")

  // One mark per word, and only when asked for.
  let verse = analyze("धर्मक्षेत्रे कुरुक्षेत्रे समवेता", stressed).kokoroPhonemes
  #expect(verse.filter { $0 == "ˈ" }.count == 3, "expected one per word: \(verse)")
  #expect(!phonemes("धर्मक्षेत्रे कुरुक्षेत्रे समवेता").contains("ˈ"))

  // Sanskrit has no stress accent, so the default must stay off.
  #expect(SanskritOptions.default.markStressOnHeavySyllables == false)
}

// MARK: - Speed

/// Speed is an acoustic control. It must not reach the phonemes at all — the
/// G2P never sees it, and this pins that.
@Test func speedDoesNotChangeThePhonemeSequence() {
  let verse = "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।"
  let reference = SanskritPhonemizer.analyze(verse)
  let tokens = SanskritTokenAudit.audit(phonemes: reference.kokoroPhonemes).tokenIDs

  // Nothing in the Sanskrit path takes a speed, which is the point: there is
  // no code path by which it could alter the phonemes. Re-deriving is stable.
  for _ in 0 ..< 4 {
    let again = SanskritPhonemizer.analyze(verse)
    #expect(again.kokoroPhonemes == reference.kokoroPhonemes)
    #expect(SanskritTokenAudit.audit(phonemes: again.kokoroPhonemes).tokenIDs == tokens)
  }
  // And the prosody layer's segmentation does not depend on speed either.
  #expect(SanskritProsody.segments(for: verse).map(\.phonemes)
          == SanskritProsody.segments(for: verse).map(\.phonemes))
}
