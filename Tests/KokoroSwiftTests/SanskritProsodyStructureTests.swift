import Foundation
import Testing
@testable import KokoroSwift

// Phonetic features, syllabification, weight, mātrās and conjunct holding.
//
// Names follow this package's convention — descriptive, no `test` prefix.
// Linguistic rules from sanskritguide.com, quoted where they are applied.

private func syllables(_ text: String) -> [SanskritSyllable] {
  let units = SanskritAksharaParser.parse(SanskritNormalizer.normalize(text).text).units
  return SanskritSyllabifier.syllabify(units).syllables
}

private func pattern(_ text: String) -> String {
  syllables(text).map { $0.weight == .guru ? "G" : "L" }.joined()
}

private func division(_ text: String) -> String {
  syllables(text).map(\.slp1).joined(separator: "-")
}

// MARK: - Consonant features

@Test func velarConsonantFeatures() {
  #expect(SanskritConsonant.ka.place == .velar)
  #expect(SanskritConsonant.ka.voicing == .voiceless)
  #expect(SanskritConsonant.ka.aspiration == .unaspirated)
  #expect(SanskritConsonant.ka.manner == .stop)
  #expect(SanskritConsonant.kha.aspiration == .aspirated)
  #expect(SanskritConsonant.ga.voicing == .voiced)
  #expect(SanskritConsonant.gha.voicing == .voiced)
  #expect(SanskritConsonant.gha.aspiration == .aspirated)
  #expect(SanskritConsonant.nga.manner == .nasal)
  #expect(SanskritConsonant.nga.place == .velar)
}

/// The whole varga system: columns 1 and 2 voiceless, 3 and 4 voiced, 5 nasal;
/// columns 2 and 4 aspirated; every member of a varga shares its place.
@Test func everyVargaFollowsTheSameFeaturePattern() {
  let vargas: [(place: SanskritPlace, members: [SanskritConsonant])] = [
    (.velar, [.ka, .kha, .ga, .gha, .nga]),
    (.palatal, [.ca, .cha, .ja, .jha, .nya]),
    (.retroflex, [.tta, .ttha, .dda, .ddha, .nna]),
    (.dental, [.ta, .tha, .da, .dha, .na]),
    (.labial, [.pa, .pha, .ba, .bha, .ma]),
  ]
  for (place, members) in vargas {
    for consonant in members {
      #expect(consonant.place == place, "\(consonant.rawValue) is not \(place)")
    }
    #expect(members[0].voicing == .voiceless && members[1].voicing == .voiceless)
    #expect(members[2].voicing == .voiced && members[3].voicing == .voiced)
    #expect(members[4].voicing == .voiced)
    #expect(members[0].aspiration == .unaspirated && members[2].aspiration == .unaspirated)
    #expect(members[1].aspiration == .aspirated && members[3].aspiration == .aspirated)
    let allStops = members[0 ..< 4].allSatisfy { $0.manner == .stop }
    #expect(allStops)
    #expect(members[4].manner == .nasal)
    // Every stop and nasal is sparśa — the class the syllabifier tests.
    let allSparsha = members.allSatisfy { $0.isSparsha }
    #expect(allSparsha)
  }
}

/// Aspirated stops are single phonemes, not stop + ह.
@Test func aspiratedStopIsSingleCanonicalPhonemeNotStopPlusHa() {
  for aspirated in [SanskritConsonant.kha, .gha, .cha, .jha, .ttha,
                    .ddha, .tha, .dha, .pha, .bha] {
    #expect(aspirated.isSingleAspiratedPhoneme, "\(aspirated.rawValue) is not one phoneme")
    #expect(aspirated.manner == .stop)
    #expect(aspirated.aspiration == .aspirated)
    // One canonical symbol, not two.
    #expect(aspirated.rawValue.count == 1)
    #expect(aspirated.unaspiratedCounterpart != nil)
    #expect(aspirated.unaspiratedCounterpart?.place == aspirated.place)
  }
  // ख is not क + ह at the canonical layer, and the two are different words.
  // A bare consonant carries its inherent vowel, so ख is `Ka` — one consonant
  // symbol, not two.
  #expect(SanskritPhonemizer.analyze("ख").canonical == "Ka")
  #expect(SanskritPhonemizer.analyze("ख्").canonical == "K")
  #expect(SanskritPhonemizer.analyze("कह").canonical == "kaha")
  #expect(SanskritPhonemizer.analyze("ख").canonical != SanskritPhonemizer.analyze("क्ह").canonical)
  #expect(SanskritPhonemizer.analyze("थ").canonical != SanskritPhonemizer.analyze("त्ह").canonical)
  #expect(SanskritPhonemizer.analyze("ध").canonical != SanskritPhonemizer.analyze("द्ह").canonical)
  #expect(SanskritPhonemizer.analyze("भ").canonical != SanskritPhonemizer.analyze("ब्ह").canonical)
}

@Test func shaSsaSaHaveDifferentArticulation() {
  #expect(SanskritConsonant.sha.place == .palatal)
  #expect(SanskritConsonant.ssa.place == .retroflex)
  #expect(SanskritConsonant.sa.place == .dental)
  for sibilant in [SanskritConsonant.sha, .ssa, .sa] {
    #expect(sibilant.manner == .sibilant)
    #expect(sibilant.voicing == .voiceless)
    #expect(!sibilant.isSparsha, "a sibilant must not close a syllable as sparśa")
  }
  #expect(Set([SanskritConsonant.sha, .ssa, .sa].map(\.place)).count == 3)
}

@Test func fiveNasalsHaveDifferentPlacesOfArticulation() {
  let nasals: [SanskritConsonant] = [.nga, .nya, .nna, .na, .ma]
  #expect(Set(nasals.map(\.place)).count == 5)
  for nasal in nasals {
    #expect(nasal.manner == .nasal)
    #expect(nasal.voicing == .voiced)
    #expect(nasal.isSparsha)
  }
  // The homorganic rule derives from the place, not a table.
  #expect(SanskritPlace.velar.nasal == .nga)
  #expect(SanskritPlace.palatal.nasal == .nya)
  #expect(SanskritPlace.retroflex.nasal == .nna)
  #expect(SanskritPlace.dental.nasal == .na)
  #expect(SanskritPlace.labial.nasal == .ma)
}

/// Retroflex and dental must not merge at any stage.
@Test func retroflexAndDentalSeriesStayApart() {
  for (retroflex, dental) in [("ट", "त"), ("ठ", "थ"), ("ड", "द"), ("ढ", "ध"), ("ण", "न")] {
    let r = SanskritPhonemizer.analyze(retroflex + "ा")
    let d = SanskritPhonemizer.analyze(dental + "ा")
    #expect(r.canonical != d.canonical, "\(retroflex)/\(dental) canonical collapsed")
    #expect(r.kokoroPhonemes != d.kokoroPhonemes, "\(retroflex)/\(dental) IPA collapsed")
    #expect(SanskritTokenAudit.audit(text: retroflex + "ा").tokenIDs
            != SanskritTokenAudit.audit(text: dental + "ा").tokenIDs)
  }
}

// MARK: - Syllabification

/// The reference's own worked examples.
@Test func syllabificationMatchesTheReferenceExamples() {
  // "the n terminates the first syllable" — man-tra, not mant-ra
  #expect(division("मन्त्र") == "man-tra")
  // kṛt-snam: the closing consonant contributes to weight
  #expect(division("कृत्स्नम्") == "kft-snam")
  // saṁ-trā-ṇa: an anusvāra closes the syllable
  #expect(division("संत्राण") == "san-trA-Ra")
  // dhar-ma: a non-sparśa cluster leaves only its last consonant as onset
  #expect(division("धर्म") == "Dar-ma")
  // "every syllable must begin with a consonant if possible"
  #expect(division("मत") == "ma-ta")
  #expect(division("मय") == "ma-ya")
  // the holding example: not सिध, and not सिदध either
  #expect(division("सिद्ध") == "sid-Da")
}

/// An akṣara is orthographic; a syllable is phonological.
///
/// Both hold exactly one vowel, so their *counts* agree. What differs is where
/// the consonants go: मन्त्र is written म + न्त्र and spoken man-tra, so the
/// n moves from the second unit to the first.
@Test func aksharasAndSyllablesDivideTheWordDifferently() {
  let result = SanskritPhonemizer.analyze("मन्त्र")
  var aksharas: [String] = []
  for unit in result.units {
    if case let .akshara(akshara) = unit {
      aksharas.append(akshara.onset.map(\.rawValue).joined() + (akshara.vowel?.rawValue ?? ""))
    }
  }
  #expect(aksharas == ["ma", "ntra"])              // orthographic
  #expect(division("मन्त्र") == "man-tra")         // phonological
  #expect(aksharas.count == syllables("मन्त्र").count)
  #expect(aksharas.joined(separator: "-") != division("मन्त्र"))

  // धर्म divides differently too: written ध + र्म, spoken dhar-ma.
  #expect(division("धर्म") == "Dar-ma")
}

// MARK: - Weight and mātrās

@Test func shortOpenSyllableIsLaghu() {
  #expect(pattern("क") == "L")
  #expect(pattern("मत") == "LL")
  #expect(pattern("मय") == "LL")
  #expect(syllables("क")[0].weight.matras == 1)
  #expect(syllables("क")[0].weightReason == .shortOpenSyllable)
}

@Test func longVowelSyllableIsGuru() {
  for word in ["का", "की", "कू", "कॄ"] {
    #expect(pattern(word) == "G", "\(word) is not guru")
    #expect(syllables(word)[0].weightReason == .longVowel)
    #expect(syllables(word)[0].matras == 2)
  }
}

@Test func closedSyllableIsGuru() {
  #expect(syllables("मन्त्र")[0].weight == .guru)
  #expect(syllables("मन्त्र")[0].weightReason == .closedByConsonant)
  #expect(syllables("धर्म")[0].weight == .guru)
  // ...and the open second syllable stays light.
  #expect(syllables("धर्म")[1].weight == .laghu)
}

@Test func anusvaraAndVisargaCloseTheSyllable() {
  // Before a continuant the anusvāra stays a nasalised vowel, and *that* is
  // what closes the syllable as an anusvāra.
  let nasalised = syllables("संस्कृत")
  #expect(nasalised.first?.endsWithAnusvara == true)
  #expect(nasalised.first?.weight == .guru)
  #expect(nasalised.first?.weightReason == .anusvara)

  // Word-finally it resolves to a real म, so the syllable is closed by a
  // consonant instead. Either way it is guru, which is what metre needs.
  let final = syllables("अहं")
  #expect(final.last?.weight == .guru)
  #expect(final.last?.weightReason == .closedByConsonant)

  let visarga = syllables("रामः")
  #expect(visarga.last?.endsWithVisarga == true)
  #expect(visarga.last?.weight == .guru)
  #expect(visarga.last?.weightReason == .visarga)
  // मामकाः: the final syllable is heavy from the visarga *and* the long ā.
  #expect(pattern("मामकाः") == "GLG")
}

/// e, ai, o and au are long for prosody, whatever a macron-less transcription
/// might suggest. This is separate from phoneme identity.
@Test func eAiOAuAreAllLongForProsody() {
  for word in ["के", "कै", "को", "कौ"] {
    #expect(pattern(word) == "G", "\(word) was treated as light")
    #expect(syllables(word)[0].weightReason == .longVowel)
    #expect(syllables(word)[0].matras == 2)
  }
  for vowel in [SanskritVowel.e, .ai, .o, .au] {
    #expect(vowel.isProsodicallyLong)
    #expect(vowel.nucleusMatras == 2)
  }
  // ...while their phoneme identities stay distinct from each other.
  #expect(Set(["के", "कै", "को", "कौ"].map { SanskritPhonemizer.phonemize($0) }).count == 4)
}

@Test func matrasFollowWeight() {
  for syllable in syllables("धर्मक्षेत्रे") {
    #expect(syllable.matras == (syllable.weight == .guru ? 2 : 1))
  }
  #expect(syllables("अभ्युत्थानम्").reduce(0) { $0 + $1.matras } == 8)
  #expect(syllables("मत").reduce(0) { $0 + $1.matras } == 2)
}

// MARK: - Holding

@Test func conjunctCodaCreatesHoldingMetadata() {
  for word in ["मन्त्र", "सिद्ध", "तत्त्व", "अभ्युत्थानम्", "धर्मक्षेत्रे"] {
    let held = syllables(word).filter(\.holdClosingConsonant)
    #expect(!held.isEmpty, "\(word) has no held syllable")
    for syllable in held { #expect(!syllable.coda.isEmpty) }
  }
  // An open light syllable is never held.
  let noneHeld = syllables("मत").allSatisfy { !$0.holdClosingConsonant }
  #expect(noneHeld)
}

/// Holding is duration, never an inserted vowel. सिद्ध must not become
/// सिध (a lost consonant) and must not become सिदध (a gained vowel).
@Test func holdingDoesNotInsertVowel() {
  let siddha = SanskritPhonemizer.phonemize("सिद्ध")
  #expect(siddha == "siddʰa")
  #expect(siddha.filter { "aeiouɪʊ".contains($0) }.count == 2)
  #expect(siddha != SanskritPhonemizer.phonemize("सिध"))
  #expect(siddha != SanskritPhonemizer.phonemize("सिदध"))

  // The prosody plan expresses holding as a scale, never as extra phonemes.
  var intent = SanskritProsodyIntent.recitation
  intent.heldCodaScale = 2.0
  let plain = SanskritPhonemizer.phonemize("सिद्ध")
  let planned = SanskritProsodyPlanner.durationScale(for: "सिद्ध", intent: intent)
  #expect(SanskritPhonemizer.phonemize("सिद्ध") == plain, "planning changed the phonemes")
  #expect(planned?.count == SanskritPhonemizer.analyze("सिद्ध").tokens.count)
}

// MARK: - Prosody plan

@Test func theProsodyPlanCarriesLinguisticIntentNotPhonemes() {
  let plan = SanskritProsodyPlanner.plan(for: "धर्मक्षेत्रे", intent: .recitation)
  #expect(plan.units.count == syllables("धर्मक्षेत्रे").count)
  #expect(plan.weightPattern == pattern("धर्मक्षेत्रे"))
  #expect(plan.totalMatras == syllables("धर्मक्षेत्रे").reduce(0) { $0 + $1.matras })
  for unit in plan.units {
    #expect(unit.matras == unit.weight.matras)
    #expect(unit.preferredDurationScale != nil)
  }
  // A guru syllable asks for more time than a laghu one.
  let guru = plan.units.first { $0.weight == .guru }?.preferredDurationScale ?? 0
  let laghu = plan.units.first { $0.weight == .laghu }?.preferredDurationScale ?? 0
  if laghu > 0 { #expect(guru > laghu) }
}

/// The neutral intent must be a true no-op, so the default path is unchanged.
@Test func neutralProsodyIntentChangesNothing() {
  #expect(SanskritProsodyPlanner.durationScale(for: "धर्मक्षेत्रे", intent: .neutral) == nil)
  for verse in ["धर्मक्षेत्रे कुरुक्षेत्रे", "मामकाः पाण्डवाश्चैव"] {
    let before = SanskritPhonemizer.phonemize(verse)
    _ = SanskritProsodyPlanner.durationScale(for: verse, intent: .recitation)
    #expect(SanskritPhonemizer.phonemize(verse) == before, "planning mutated the phonemes")
  }
}

/// The scale has one entry per token and never reorders or replaces one.
@Test func durationScaleIsParallelToTokensAndChangesNoPhoneme() {
  for text in ["धर्मक्षेत्रे", "अभ्युत्थानम्", "मामकाः",
               "धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।"] {
    let result = SanskritPhonemizer.analyze(text)
    let scale = SanskritProsodyPlanner.durationScale(for: text, intent: .recitation)
    #expect(scale?.count == result.tokens.count, "\(text): scale is not parallel to tokens")
    let allPositive = scale?.allSatisfy { $0 > 0 } ?? false
    #expect(allPositive, "\(text): non-positive scale")
    // Applying a plan cannot change what is said.
    #expect(SanskritPhonemizer.analyze(text).kokoroPhonemes == result.kokoroPhonemes)
    #expect(SanskritPhonemizer.analyze(text).tokens == result.tokens)
  }
}

// MARK: - Boundaries

/// A source newline is typography. It must not become a pause, and must not
/// change a single phoneme.
@Test func displayLineBreakDoesNotChangeCanonicalPhonology() {
  let oneLine = "धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।"
  let wrapped = "धर्मक्षेत्रे कुरुक्षेत्रे\nसमवेता युयुत्सवः ।"
  #expect(SanskritPhonemizer.phonemize(oneLine) == SanskritPhonemizer.phonemize(wrapped))
  #expect(SanskritPhonemizer.analyze(oneLine).canonical
          == SanskritPhonemizer.analyze(wrapped).canonical)
  #expect(pattern(oneLine) == pattern(wrapped))

  #expect(SanskritBoundary.displayLineBreak.isPause == false)
  #expect(SanskritProsodyConfiguration.default.pause(for: .displayLineBreak) == 0)
  // It is its own kind, distinct from every other boundary.
  for other in [SanskritBoundary.word, .pada, .verse, .elision] {
    #expect(SanskritBoundary.displayLineBreak != other)
  }
}

/// A daṇḍa is a recitation pause. It must not silently rewrite the phonology
/// of the syllable in front of it.
@Test func dandaDoesNotChangeThePrecedingSyllablePhonology() {
  let bare = SanskritPhonemizer.analyze("युयुत्सवः")
  let withDanda = SanskritPhonemizer.analyze("युयुत्सवः ।")
  #expect(withDanda.canonical.hasPrefix(bare.canonical))
  #expect(withDanda.kokoroPhonemes.hasPrefix(bare.kokoroPhonemes))
  // Line-final heaviness is a metrical convention and is opt-in, so plain
  // syllabification does not apply it.
  let units = SanskritAksharaParser.parse(SanskritNormalizer.normalize("मत").text).units
  #expect(SanskritSyllabifier.syllabify(units).syllables.last?.weight == .laghu)
  #expect(SanskritSyllabifier.syllabify(units, lineFinalIsHeavy: true)
    .syllables.last?.weight == .guru)
}

// MARK: - Metre

/// Twelve pādas across three verses, every one matching the anuṣṭubh pathyā
/// cadence — L G G at 5-7 in an odd pāda, L G L in an even one. Nothing in the
/// implementation knows the pattern, so this is independent evidence that the
/// syllabifier, vowel lengths and phonology are jointly right.
@Test func gitaVersesScanAsAnushtubh() {
  let verses = [
    "धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।\nमामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥",
    "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।\nमा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥",
    "यदा यदा हि धर्मस्य ग्लानिर्भवति भारत ।\nअभ्युत्थानमधर्मस्य तदात्मानं सृजाम्यहम् ॥",
  ]
  for verse in verses {
    let analysis = SanskritMeter.analyze(verse)
    #expect(analysis.warnings.isEmpty, "\(verse): \(analysis.warnings)")
    #expect(analysis.padaSyllableCounts == [16, 16], "\(analysis.padaSyllableCounts)")

    for half in analysis.padas {
      let weights = half.weights
      #expect(weights.count == 16)
      // Two anuṣṭubh pādas per printed half.
      for (offset, isEven) in [(0, false), (8, true)] {
        #expect(weights[offset + 4] == .laghu, "syllable 5 must be laghu")
        #expect(weights[offset + 5] == .guru, "syllable 6 must be guru")
        #expect(weights[offset + 6] == (isEven ? .laghu : .guru),
                "syllable 7 cadence wrong")
      }
    }
  }
}

// MARK: - Visarga length repair

/// A visarga-final syllable is guru, but *why* it is guru decides what may be
/// lengthened. In मामकाः the ā is genuinely long and the model under-realises
/// it, so restoring its duration is a repair. In युयुत्सवः the a is genuinely
/// short, and lengthening it turns वः into वाः — a different vowel, and the
/// error reported as "युयुत्सवाह". The visarga's own duration is scaled in
/// both cases; the vowel's only when it is already long.
@Test func visargaLengtheningNeverLengthensAShortVowel() {
  // Long vowel before the visarga: the vowel is repaired.
  for word in ["मामकाः", "पाण्डवाः", "भूः", "धीः", "हरेः", "गुरोः"] {
    let phonemes = SanskritPhonemizer.phonemize(word)
    guard let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
      phonemes, intent: .closureRepairs
    ) else { Issue.record("\(word): no scale"); continue }
    #expect(scale[scale.count - 1] > 1.0, "\(word): the visarga was not lengthened")
    #expect(scale[scale.count - 2] > 1.0, "\(word): its long vowel was not repaired")
  }

  // Short vowel before the visarga: only the visarga is scaled.
  for word in ["युयुत्सवः", "रामः", "योगः", "अर्जुनः", "नमः", "पुनः", "कः"] {
    let phonemes = SanskritPhonemizer.phonemize(word)
    guard let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
      phonemes, intent: .closureRepairs
    ) else { Issue.record("\(word): no scale"); continue }
    #expect(scale[scale.count - 1] > 1.0, "\(word): the visarga was not lengthened")
    #expect(scale[scale.count - 2] == 1.0,
            "\(word): a SHORT vowel was lengthened — वः would become वाः")
  }

  // And no repair touches a phoneme.
  for word in ["मामकाः", "युयुत्सवः"] {
    let before = SanskritPhonemizer.phonemize(word)
    _ = SanskritProsodyPlanner.durationScaleForPhonemes(before, intent: .closureRepairs)
    #expect(SanskritPhonemizer.phonemize(word) == before)
  }
  // A word with no visarga gets no visarga repair.
  let none = SanskritProsodyPlanner.durationScaleForPhonemes(
    SanskritPhonemizer.phonemize("कर्म"), intent: .visargaLengthOnly
  )
  #expect(none?.allSatisfy { $0 == 1.0 } == true)
}

/// `prepareInputTensors` wraps the token sequence in a padding token at each
/// end, so the duration tensor is two longer than the phoneme count. A scale
/// built per phoneme must still line up.
///
/// This is a regression test: the first version of the duration control was
/// silently ignored for every input, because the caller supplied one entry per
/// phoneme and the check demanded one per padded token.
@Test func durationScaleIsSizedForPhonemesNotPaddedTokens() {
  for word in ["मामकाः", "धर्मक्षेत्रे", "अभ्युत्थानम्"] {
    let phonemes = SanskritPhonemizer.phonemize(word)
    let scale = SanskritProsodyPlanner.durationScaleForPhonemes(
      phonemes, intent: .recitation
    )
    let tokens = Tokenizer.tokenize(phonemizedText: phonemes)
    #expect(scale?.count == tokens.count,
            "\(word): scale is \(scale?.count ?? -1) for \(tokens.count) phoneme tokens")
    // The model pads to tokens.count + 2; the mismatch must not be the
    // caller's to reconcile.
    #expect(scale?.count != tokens.count + 2)
  }
}
