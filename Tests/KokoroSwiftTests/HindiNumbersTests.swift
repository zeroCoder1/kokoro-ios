import Testing
@testable import KokoroSwift

/// Every case from the Hindi number-expansion spec.
@Test(arguments: [
  ("0", "शून्य"),
  ("7", "सात"),
  ("19", "उन्नीस"),
  ("99", "निन्यानवे"),
  ("100", "एक सौ"),
  ("101", "एक सौ एक"),
  ("999", "नौ सौ निन्यानवे"),
  ("1000", "एक हज़ार"),
  ("1500", "पंद्रह सौ"),
  ("1947", "उन्नीस सौ सैंतालीस"),
  ("2000", "दो हज़ार"),
  ("2024", "दो हज़ार चौबीस"),
  ("100000", "एक लाख"),
  ("150000", "एक लाख पचास हज़ार"),
  ("10000000", "एक करोड़"),
  ("12345678", "एक करोड़ तेईस लाख पैंतालीस हज़ार छह सौ अठहत्तर"),
  ("987654321", "अट्ठानवे करोड़ छिहत्तर लाख चौवन हज़ार तीन सौ इक्कीस"),
  ("15%", "पंद्रह प्रतिशत"),
  ("₹500", "पाँच सौ रुपये"),
  ("3.5", "तीन दशमलव पाँच"),
  ("१५ अगस्त", "पंद्रह अगस्त"),
])
func hindiNumbersMatchTheSpecification(input: String, expected: String) {
  #expect(HindiNumbers.expand(input) == expected, "\(input)")
}

/// Indian grouping: `1,50,000` and `1,500,000` are the same number, and the
/// commas are not sentence punctuation.
@Test func hindiNumbersStripGroupingCommas() {
  #expect(HindiNumbers.expand("1,50,000") == "एक लाख पचास हज़ार")
  #expect(HindiNumbers.expand("1,500,000") == "पंद्रह लाख")
  #expect(HindiNumbers.expand("2,024") == "दो हज़ार चौबीस")
}

@Test func hindiNumbersKeepNonGroupingCommasAsPunctuation() {
  #expect(HindiNumbers.expand("पहला, दूसरा") == "पहला, दूसरा")
  #expect(HindiNumbers.expand("2, 3") == "दो, तीन")
}

@Test func hindiNumbersReadFractionsDigitByDigit() {
  #expect(HindiNumbers.expand("3.14") == "तीन दशमलव एक चार")
  #expect(HindiNumbers.expand("0.75") == "शून्य दशमलव सात पाँच")
}

/// A `.` is only a decimal point with digits on both sides; otherwise it stays
/// the sentence-break token the model was trained on.
@Test func hindiNumbersLeaveSentenceFinalPeriodsAlone() {
  #expect(HindiNumbers.expand("यह 5 है.") == "यह पाँच है.")
  #expect(HindiNumbers.expand("कुल 100.") == "कुल एक सौ.")
}

/// Long runs and hyphenated groups are identifiers, not quantities.
@Test func hindiNumbersReadIdentifiersDigitByDigit() {
  #expect(HindiNumbers.expand("98765-43210")
    == "नौ आठ सात छह पाँच चार तीन दो एक शून्य")
  #expect(HindiNumbers.expand("1234567890")
    == "एक दो तीन चार पाँच छह सात आठ नौ शून्य")
  #expect(HindiNumbers.expand("007") == "शून्य शून्य सात")
}

@Test func hindiNumbersAttachCurrencyAndPercentSymbols() {
  #expect(HindiNumbers.expand("$20") == "बीस डॉलर")
  #expect(HindiNumbers.expand("₹1,50,000") == "एक लाख पचास हज़ार रुपये")
  #expect(HindiNumbers.expand("100%") == "एक सौ प्रतिशत")
}

/// A currency mark not attached to digits has no number to ride on. It is left
/// for `HindiG2PProcessor` to drop, and must not swallow the text after it.
@Test func hindiNumbersIgnoreDetachedCurrencyMarks() {
  #expect(HindiNumbers.expand("₹ है") == "₹ है")
  #expect(HindiNumbers.expand("कीमत %") == "कीमत %")
}

@Test func hindiNumbersNormalizeDevanagariDigits() {
  #expect(HindiNumbers.expand("२०२४") == "दो हज़ार चौबीस")
  #expect(HindiNumbers.expand("१,५०,०००") == "एक लाख पचास हज़ार")
}

@Test func hindiNumbersReadTheHundredsBandAsCenturies() {
  #expect(HindiNumbers.expand("1100") == "ग्यारह सौ")
  #expect(HindiNumbers.expand("1999") == "उन्नीस सौ निन्यानवे")
  // Just outside the band on either side, the scale words take over again.
  #expect(HindiNumbers.expand("1099") == "एक हज़ार निन्यानवे")
  #expect(HindiNumbers.expand("2001") == "दो हज़ार एक")
}

/// The century reading applies to a number as a whole, never to a remainder
/// sitting inside a larger one.
@Test func hindiNumbersDoNotApplyCenturiesToRemainders() {
  #expect(HindiNumbers.expand("11500") == "ग्यारह हज़ार पाँच सौ")
  #expect(HindiNumbers.expand("1947000") == "उन्नीस लाख सैंतालीस हज़ार")
}

@Test func hindiNumbersAlwaysSayEkBeforeAScaleWord() {
  #expect(HindiNumbers.expand("1000").hasPrefix("एक "))
  #expect(HindiNumbers.expand("100000").hasPrefix("एक "))
  #expect(HindiNumbers.expand("10000000").hasPrefix("एक "))
  #expect(HindiNumbers.expand("100").hasPrefix("एक "))
}

@Test func hindiNumbersLeaveTextWithoutDigitsUntouched() {
  let sentence = "यह एक साधारण वाक्य है, जिसमें कोई अंक नहीं है."
  #expect(HindiNumbers.expand(sentence) == sentence)
}

@Test func hindiNumbersExpandEveryValueBelowOneThousand() {
  // Nothing in 0...999 may fall through the tables and vanish.
  for value in 0...999 {
    #expect(!HindiNumbers.expand(String(value)).isEmpty, "\(value)")
  }
}

// MARK: - Phase 8 regression corpus

/// The full required ladder, so a change to the scale logic shows up here
/// rather than in a sentence test.
@Test(arguments: [
  ("0", "शून्य"), ("1", "एक"), ("10", "दस"), ("11", "ग्यारह"),
  ("19", "उन्नीस"), ("20", "बीस"), ("21", "इक्कीस"), ("50", "पचास"),
  ("99", "निन्यानवे"), ("100", "एक सौ"), ("101", "एक सौ एक"),
  ("110", "एक सौ दस"), ("125", "एक सौ पच्चीस"), ("1000", "एक हज़ार"),
  ("1947", "उन्नीस सौ सैंतालीस"), ("1999", "उन्नीस सौ निन्यानवे"),
  ("2000", "दो हज़ार"), ("2001", "दो हज़ार एक"),
  ("2024", "दो हज़ार चौबीस"), ("2026", "दो हज़ार छब्बीस"),
  ("10000", "दस हज़ार"), ("100000", "एक लाख"),
  ("150000", "एक लाख पचास हज़ार"), ("1,50,000", "एक लाख पचास हज़ार"),
  ("10,00,000", "दस लाख"), ("1,00,00,000", "एक करोड़"),
])
func hindiNumberLadder(input: String, expected: String) {
  #expect(HindiNumbers.expand(input) == expected, "\(input)")
}

@Test(arguments: [
  ("3.5", "तीन दशमलव पाँच"),
  ("7.25", "सात दशमलव दो पाँच"),
  ("50%", "पचास प्रतिशत"),
  ("7%", "सात प्रतिशत"),
  ("₹100", "एक सौ रुपये"),
  ("₹1,500", "पंद्रह सौ रुपये"),
  ("$100", "एक सौ डॉलर"),
])
func hindiNumberDecimalsAndSymbols(input: String, expected: String) {
  #expect(HindiNumbers.expand(input) == expected, "\(input)")
}

/// Devanagari digits are the same numbers.
@Test(arguments: [("२०२६", "दो हज़ार छब्बीस"), ("१००", "एक सौ"), ("५०", "पचास")])
func hindiNumberDevanagariDigits(input: String, expected: String) {
  #expect(HindiNumbers.expand(input) == expected, "\(input)")
}

/// A scale word written after the digits goes between the amount and the
/// currency, which is the order Hindi uses.
@Test func hindiNumberCurrencyFollowsTheScaleWord() {
  #expect(HindiNumbers.expand("₹1,500 करोड़") == "पंद्रह सौ करोड़ रुपये")
  #expect(HindiNumbers.expand("₹1.5 लाख") == "एक दशमलव पाँच लाख रुपये")
  #expect(HindiNumbers.expand("₹2 हज़ार") == "दो हज़ार रुपये")
  // Without a currency the scale word is just the next word.
  #expect(HindiNumbers.expand("1,500 करोड़") == "पंद्रह सौ करोड़")
}

/// `:` is a Kokoro token, so leaving it inside a time puts a pause in the
/// middle of it.
@Test func hindiNumberClockTimes() {
  #expect(HindiNumbers.expand("7:30") == "सात तीस")
  #expect(HindiNumbers.expand("10:45") == "दस पैंतालीस")
  #expect(HindiNumbers.expand("मैच शाम 7:30 बजे शुरू होगा।")
    == "मैच शाम सात तीस बजे शुरू होगा।")
  // A colon that is ordinary punctuation is left alone.
  #expect(HindiNumbers.expand("समय: 5 बजे") == "समय: पाँच बजे")
}

/// Digits welded to Latin letters are part of a term, not a quantity, and are
/// read by HindiG2PProcessor with English number names instead.
@Test(arguments: ["G20", "5G", "4G", "U19", "COVID-19", "H1N1", "B2B", "Web3"])
func hindiNumberLeavesAlphanumericTermsAlone(term: String) {
  #expect(HindiNumbers.expand(term) == term)
}

/// News lines end to end.
@Test func hindiNumberNewsSentences() {
  #expect(HindiNumbers.expand("साल 2026 में") == "साल दो हज़ार छब्बीस में")
  #expect(HindiNumbers.expand("भारत की GDP 7.2% बढ़ी।")
    == "भारत की GDP सात दशमलव दो प्रतिशत बढ़ी।")
}
