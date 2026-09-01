import Testing
@testable import KokoroSwift

// Hindi G2P regression corpus.
//
// Table driven and organised by what each group is testing, so a change that
// moves one class of word shows up as that class rather than as a scatter of
// unrelated failures.
//
// Expected values are this package's own output, checked against
// `espeak-ng -v hi -q --ipa` — the distribution Kokoro's Hindi voices were
// trained on. Where the two deliberately differ the case is marked
// MODEL_COMPATIBILITY or LINGUISTIC_G2P_RULE and says why, so a future model
// trained on labels from this phonemizer can revisit it rather than inherit
// the reasoning by accident.
//
// Re-measure divergence with Tools/espeak-diff.py.

typealias HindiWordCase = (word: String, phonemes: String)

private func check(_ cases: [HindiWordCase], _ file: StaticString = #filePath, _ line: UInt = #line) {
  for testCase in cases {
    #expect(
      HindiPhonemizer.phonemize(testCase.word) == testCase.phonemes,
      "\(testCase.word): got \(HindiPhonemizer.phonemize(testCase.word)), want \(testCase.phonemes)"
    )
  }
}


/// Category 1. Each vowel standing alone.
private let independentVowels: [HindiWordCase] = [
    ("अ", "ˈʌ"),
    ("आ", "ˈaː"),
    ("इ", "ˈɪ"),
    ("ई", "ˈi"),
    ("उ", "ˈʊ"),
    ("ऊ", "ˈu"),
    ("ए", "ˈeː"),
    ("ऐ", "ˈɛː"),
    ("ओ", "ˈoː"),
    ("औ", "ˈɔː"),
]

/// Category 2. The same vowels as matras on क.
private let vowelSigns: [HindiWordCase] = [
    ("का", "kaː"),
    ("कि", "kɪ"),
    ("की", "ki"),
    ("कु", "kˈʊ"),
    ("कू", "kˈu"),
    ("के", "keː"),
    ("कै", "kˈɛː"),
    ("को", "koː"),
    ("कौ", "kˈɔː"),
]

/// Category 3. Every stop against its aspirated partner.
private let aspiration: [HindiWordCase] = [
    ("कल", "kˈʌl"),
    ("खल", "kʰˈʌl"),
    ("गल", "ɡˈʌl"),
    ("घल", "ɡʰˈʌl"),
    ("चल", "cˈʌl"),
    ("छल", "cʰˈʌl"),
    ("जल", "ɟˈʌl"),
    ("झल", "ɟʰˈʌl"),
    ("टल", "ʈˈʌl"),
    ("ठल", "ʈʰˈʌl"),
    ("डल", "ɖˈʌl"),
    ("ढल", "ɖʰˈʌl"),
    ("तल", "tˈʌl"),
    ("थल", "tʰˈʌl"),
    ("दल", "dˈʌl"),
    ("धल", "dʰˈʌl"),
    ("पल", "pˈʌl"),
    ("फल", "pʰˈʌl"),
    ("बल", "bˈʌl"),
    ("भल", "bʰˈʌl"),
]

/// Category 4. त/ट and द/ड must not collapse.
private let dentalVsRetroflex: [HindiWordCase] = [
    ("तार", "tˈaːɾ"),
    ("टार", "ʈˈaːɾ"),
    ("दान", "dˈaːn"),
    ("डान", "ɖˈaːn"),
    ("थाल", "tʰˈaːl"),
    ("ठाल", "ʈʰˈaːl"),
    ("धार", "dʰˈaːɾ"),
    ("ढाल", "ɖʰˈaːl"),
]

/// Category 5. The dotted Perso-Arabic series.
private let nuktaConsonants: [HindiWordCase] = [
    ("क़ानून", "qaːnˈuːn"),
    ("ख़बर", "xˈʌbəɾ"),
    ("ग़रीब", "ɣəɾˈiːb"),
    ("ज़मीन", "zəmˈiːn"),
    ("ज़िला", "zˈɪlaː"),
    ("फ़ोन", "fˈoːn"),
]

/// Category 6. LINGUISTIC_G2P_RULE. espeak reads every plain फ as pʰ, including
/// in loanwords. Native फल, फूल, फिर and सफल keep pʰ; loanwords written
/// without the nukta still take f, which is a deliberate divergence.
private let phVersusF: [HindiWordCase] = [
    ("फल", "pʰˈʌl"),
    ("फूल", "pʰˈuːl"),
    ("फिर", "pʰˈɪɾ"),
    ("सफल", "sˈʌpʰəl"),
    ("फिल्म", "fˈɪlm"),
    ("फोन", "fˈoːn"),
    ("फोटो", "fˈoːʈoː"),
    ("फीफा", "fˈiːfaː"),
    ("फाइनल", "fˈaːɪnəl"),
    ("फैसला", "fˈɛːslaː"),
    ("फ़िल्म", "fˈɪlm"),
    ("फ़ोन", "fˈoːn"),
]

/// Category 7. ज़ is z, ज is ɟ.
private let zVersusJ: [HindiWordCase] = [
    ("ज़िला", "zˈɪlaː"),
    ("जिला", "ɟˈɪlaː"),
    ("ज़मीन", "zəmˈiːn"),
    ("जमीन", "ɟəmˈiːn"),
    ("जल", "ɟˈʌl"),
    ("ज़रूरी", "zəɾˈuːɾi"),
]

/// Category 8. ख़ is x, ख is kʰ.
private let xVersusKh: [HindiWordCase] = [
    ("ख़बर", "xˈʌbəɾ"),
    ("खबर", "kʰˈʌbəɾ"),
    ("ख़ास", "xˈaːs"),
    ("खास", "kʰˈaːs"),
]

/// Category 9. Final and medial inherent schwa.
private let schwaDeletion: [HindiWordCase] = [
    ("कमल", "kˈʌməl"),
    ("नगर", "nˈʌɡəɾ"),
    ("समझ", "sˈʌməɟʰ"),
    ("समझना", "səmˈʌɟʰnaː"),
    ("भारत", "bʰˈaːɾət"),
    ("अदालत", "ʌdˈaːlət"),
    ("अस्पताल", "ʌspətˈaːl"),
    ("महत्व", "mˈʌhətʋ"),
]

/// Category 10-12. A written conjunct keeps the vowel before it, and a final
/// य completing one keeps its schwa.
private let schwaPreservation: [HindiWordCase] = [
    ("मुख्य", "mˈʊkʰjə"),
    ("योग्य", "jˈoːɡjə"),
    ("वाक्य", "ʋˈaːkjə"),
    ("विश्व", "ʋˈɪʃʋ"),
    ("स्वतंत्र", "sʋətˈʌntɾə"),
    ("स्वतंत्रता", "sʋətˈʌntɾətˌaː"),
    ("राष्ट्रीय", "ɾaːʂʈɾˈiːj"),
]

/// Category 13-15. On the short central vowel the anusvara is its own
/// consonant, assimilated to what follows. This is the सं- news vocabulary.
private let anusvaraOnSchwa: [HindiWordCase] = [
    ("अंक", "ˈʌŋk"),
    ("अंग", "ˈʌŋɡ"),
    ("अंतर", "ˈʌntəɾ"),
    ("अंत", "ˈʌnt"),
    ("अंदर", "ˈʌndəɾ"),
    ("संसद", "sˈʌnsəd"),
    ("संविधान", "sənʋɪdʰˈaːn"),
    ("संयुक्त", "sˈʌɲjʊkt"),
    ("संस्कृति", "sˈʌnskɾɪtɪ"),
    ("संस्था", "sˈʌnstʰaː"),
    ("संसाधन", "sənsˈaːdʰən"),
    ("संरक्षण", "sˈʌnɾkʃəɳ"),
    ("संशोधन", "sənʃˈoːdʰən"),
    ("संघ", "sˈʌŋɡʰ"),
    ("संगठन", "sˈʌŋɡʈʰən"),
    ("संचार", "səɲcˈaːɾ"),
    ("संबंध", "səmbˈʌndʰ"),
    ("संकट", "sˈʌŋkəʈ"),
    ("संकेत", "səŋkˈeːt"),
    ("संख्या", "sˈʌŋkʰjaː"),
    ("संभावना", "səmbʰˈaːʋnaː"),
    ("संपर्क", "sˈʌmpərk"),
]

/// Category 13-15. On any other vowel it nasalizes that vowel and adds no
/// consonant, before stops included.
private let anusvaraOnWrittenVowel: [HindiWordCase] = [
    ("दांत", "dˈa\u{0303}t"),
    ("सांप", "sˈa\u{0303}p"),
    ("हिंसा", "hˈi\u{0303}saː"),
    ("सिंह", "sˈi\u{0303}h"),
    ("बिंदु", "bˈi\u{0303}dʊ"),
    ("केंद्र", "kˈe\u{0303}ːdɾə"),
    ("चांद", "cˈa\u{0303}d"),
    ("नींद", "nˈi\u{0303}d"),
    ("बैंक", "bˈɛ\u{0303}k"),
    ("मुंबई", "mˈu\u{0303}bi"),
]

/// Category 14. Same rule as the anusvara.
private let chandrabindu: [HindiWordCase] = [
    ("हाँ", "hˈa\u{0303}"),
    ("माँ", "mˈa\u{0303}"),
    ("यहाँ", "jəhˈa\u{0303}"),
    ("अँधेरा", "ʌndʰˈeːɾaː"),
    ("मैं", "mˈɛ\u{0303}"),
    ("में", "mˈe\u{0303}ː"),
]

/// Category 16. Trill after a written virama, flap otherwise.
private let rhotic: [HindiWordCase] = [
    ("सरकार", "səɾkˈaːɾ"),
    ("कुर्सी", "kˈʊrsi"),
    ("निर्माण", "nɪrmˈaːɳ"),
]

/// Category 17. MODEL_COMPATIBILITY. ड़ and ढ़ are retroflex flaps ɽ/ɽʰ in
/// careful IPA, but espeak emits ɽ for no language Kokoro supports, so that
/// embedding is untrained. ɖ/ɖʰ is what the current voices render, and what
/// speakers hear: बड़ा is \"bada\" against बरा \"bara\". Revisit only with a
/// model trained on labels from this phonemizer.
private let dottedRetroflex: [HindiWordCase] = [
    ("करोड़", "kəɾˈoːɖ"),
    ("बड़ा", "bˈʌɖaː"),
    ("बरा", "bˈʌɾaː"),
    ("पढ़ना", "pˈʌɖʰnaː"),
    ("सड़क", "sˈʌɖək"),
    ("लड़का", "lˈʌɖkaː"),
    ("लड़की", "lˈʌɖki"),
    ("बढ़ना", "bˈʌɖʰnaː"),
    ("पहाड़", "pəhˈaːɖ"),
]

/// Category 30. Compounds split at morpheme boundaries.
private let newsCompounds: [HindiWordCase] = [
    ("प्रधानमंत्री", "pɾədʰˈaːn mˈʌntɾi"),
    ("मुख्यमंत्री", "mˈʊkʰjə mˈʌntɾi"),
    ("राष्ट्रपति", "ɾˈaːʂʈɾə pˈʌtɪ"),
    ("लोकसभा", "lˈoːk sˈʌbʰaː"),
    ("राज्यसभा", "ɾˈaːɟjə sˈʌbʰaː"),
]

/// Category 28.
private let indianProperNouns: [HindiWordCase] = [
    ("दिल्ली", "dˈɪlːi"),
    ("बेंगलुरु", "bˈe\u{0303}ːɡlʊɾʊ"),
    ("वाराणसी", "ʋaːɾˈaːɳəsi"),
    ("कोलकाता", "kˈoːlkaːtˌaː"),
    ("चेन्नई", "cˈeːnːi"),
    ("मुम्बई", "mˈʊmbəˌi"),
]

/// Category 33. Postpositions and pronouns, which must stay unstressed so they
/// do not become prominent in a sentence.
private let functionWords: [HindiWordCase] = [
    ("दुनिया", "dˈʊnɪjˌaː"),
    ("यह", "jˈʌh"),
    ("हम", "həm"),
    ("आप", "aːp"),
    ("और", "ɔːɾ"),
    ("का", "kaː"),
    ("की", "ki"),
    ("के", "keː"),
    ("को", "koː"),
    ("से", "seː"),
    ("ने", "neː"),
    ("है", "hɛː"),
    ("हैं", "hɛ\u{0303}"),
]

/// MODEL_COMPATIBILITY. espeak never ends a Hindi word on a long high vowel,
/// so the voices never heard one there. Isolate for a future model.
private let finalHighVowels: [HindiWordCase] = [
    ("पानी", "pˈaːni"),
    ("कहानी", "kəhˈaːni"),
    ("आदमी", "ˈaːdmi"),
    ("भेजी", "bʰˈeːɟi"),
    ("लड़की", "lˈʌɖki"),
]

/// MODEL_COMPATIBILITY. espeak opens a word written with अ on ʌ rather than ə.
private let wordInitialA: [HindiWordCase] = [
    ("अचानक", "ʌcˈaːnək"),
    ("अदालत", "ʌdˈaːlət"),
    ("अस्पताल", "ʌspətˈaːl"),
    ("अधिकारी", "ʌdʰɪkˈaːɾi"),
    ("अमेरिका", "ʌmˈeːɾɪkˌaː"),
    ("अलग", "ˈʌləɡ"),
]

// MARK: - Tests

@Test func hindiIndependentVowels() { check(independentVowels) }
@Test func hindiVowelSigns() { check(vowelSigns) }
@Test func hindiAspiration() { check(aspiration) }
@Test func hindiDentalVsRetroflex() { check(dentalVsRetroflex) }
@Test func hindiNuktaConsonants() { check(nuktaConsonants) }
@Test func hindiPhVersusF() { check(phVersusF) }
@Test func hindiZVersusJ() { check(zVersusJ) }
@Test func hindiXVersusKh() { check(xVersusKh) }
@Test func hindiSchwaDeletion() { check(schwaDeletion) }
@Test func hindiSchwaPreservation() { check(schwaPreservation) }
@Test func hindiAnusvaraOnSchwa() { check(anusvaraOnSchwa) }
@Test func hindiAnusvaraOnWrittenVowel() { check(anusvaraOnWrittenVowel) }
@Test func hindiChandrabindu() { check(chandrabindu) }
@Test func hindiRhotic() { check(rhotic) }
@Test func hindiDottedRetroflex() { check(dottedRetroflex) }
@Test func hindiNewsCompounds() { check(newsCompounds) }
@Test func hindiIndianProperNouns() { check(indianProperNouns) }
@Test func hindiFunctionWords() { check(functionWords) }
@Test func hindiFinalHighVowels() { check(finalHighVowels) }
@Test func hindiWordInitialA() { check(wordInitialA) }
