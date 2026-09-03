import Foundation

// The prosodic intent layer.
//
// Sanskrit recitation is timed, not stressed. English prosody makes one
// syllable prominent and reduces its neighbours; Sanskrit gives a guru
// syllable two mātrās and a laghu one, and holds the closing consonant of a
// conjunct. Those are duration facts, and this layer records them as intent —
// separately from whether Kokoro can act on them.
//
//     Sanskrit phonology  →  syllables + weight  →  prosodic intent
//                                                        ↓
//                                            Kokoro realization (optional)
//
// The goal is **not** "make Sanskrit slower". A global slowdown lengthens guru
// and laghu alike and preserves nothing. The goal is to keep the contrasts:
// long vowels long, closed syllables heavy, conjunct codas held, light
// syllables comparatively light, and the phrase still continuous.

/// One syllable's prosodic intent.
struct SanskritProsodicUnit: Equatable {
  var syllable: SanskritSyllable
  var matras: Int
  var weight: SanskritSyllableWeight
  /// Whether the closing consonant of a conjunct should be given time.
  var holdCoda: Bool
  /// What follows this syllable.
  var boundaryAfter: SanskritBoundary?
  /// How much longer or shorter than the model's own prediction this syllable
  /// wants to be. `nil` means "no opinion" — the model's prediction stands.
  var preferredDurationScale: Float?
}

/// How strongly the linguistic intent should be pushed onto the model.
///
/// The values are deliberately gentle. Kokoro's own duration predictor is not
/// ignorant of length — it produced 1.40× for भू against भु unprompted — so
/// this corrects a tendency rather than dictating a timing grid. Pushed hard
/// it would sound metronomic, which is the failure mode the brief names.
struct SanskritProsodyIntent: Equatable {
  /// Multiplier for the vowel of a guru syllable.
  var guruVowelScale: Float
  /// Multiplier for the vowel of a laghu syllable.
  var laghuVowelScale: Float
  /// Multiplier for a consonant closing a conjunct — the "holding" the
  /// reference describes. Duration and clear articulation, never an inserted
  /// vowel.
  var heldCodaScale: Float
  /// Multiplier for the aspiration mark, so an aspirated stop keeps its
  /// release.
  var aspirationScale: Float
  /// Multiplier for a syllable closed by a visarga.
  ///
  /// This one is not a preference, it is a repair. A visarga-final syllable is
  /// guru — a long vowel *and* a closing visarga — yet the model gives it
  /// barely more time than a light one. Measured on मामकाः at 0.80:
  ///
  ///     maːmaka   (short a)            330 ms
  ///     maːmakaː  (long ā)             390 ms
  ///     maːmakaːh (ours)               360 ms   ← 9% over the *short* form
  ///     maːmakaːh + 1.25×              450 ms
  ///
  /// So काः was arriving barely longer than क, which is why it is heard as
  /// मामक. Scaling restores the duration the phonology already specifies; it
  /// adds no phoneme and changes no token. It does **not** make the visarga
  /// audible — that is a separate, unfixable limitation — so the result is a
  /// correctly long final syllable rather than a correctly pronounced one.
  var visargaSyllableScale: Float

  /// No opinion at all: every scale is 1.0, so the model's own prediction
  /// stands untouched. This is what production uses until listening says
  /// otherwise.
  static let neutral = SanskritProsodyIntent(
    guruVowelScale: 1.0, laghuVowelScale: 1.0, heldCodaScale: 1.0,
    aspirationScale: 1.0, visargaSyllableScale: 1.0
  )

  /// The experimental setting. Guru vowels get a little more time, laghu
  /// vowels a little less, held codas and aspiration a little more. The
  /// contrast between guru and laghu widens by about 25% without either
  /// leaving the range the model already produces.
  static let recitation = SanskritProsodyIntent(
    guruVowelScale: 1.15, laghuVowelScale: 0.92, heldCodaScale: 1.20,
    aspirationScale: 1.15, visargaSyllableScale: 1.30
  )

  /// The visarga repair on its own, with every other scale neutral. Isolates
  /// the one change with a measured before-and-after.
  static let visargaLengthOnly = SanskritProsodyIntent(
    guruVowelScale: 1.0, laghuVowelScale: 1.0, heldCodaScale: 1.0,
    aspirationScale: 1.0, visargaSyllableScale: 1.30
  )
}

enum SanskritProsodyPlanner {
  struct Plan {
    var units: [SanskritProsodicUnit] = []
    var warnings: [String] = []

    var totalMatras: Int { units.reduce(0) { $0 + $1.matras } }
    /// `G`/`L` per syllable, for diagnostics.
    var weightPattern: String {
      units.map { $0.weight == .guru ? "G" : "L" }.joined()
    }
  }

  static func plan(
    for text: String,
    options: SanskritOptions = .default,
    intent: SanskritProsodyIntent = .neutral
  ) -> Plan {
    let normalized = SanskritNormalizer.normalize(text)
    let units = SanskritAksharaParser.parse(normalized.text).units
    let syllabified = SanskritSyllabifier.syllabify(units, options: options)

    var plan = Plan(warnings: syllabified.warnings)
    for syllable in syllabified.syllables {
      plan.units.append(SanskritProsodicUnit(
        syllable: syllable,
        matras: syllable.matras,
        weight: syllable.weight,
        holdCoda: syllable.holdClosingConsonant,
        boundaryAfter: nil,
        preferredDurationScale: syllable.weight == .guru
          ? intent.guruVowelScale : intent.laghuVowelScale
      ))
    }
    return plan
  }

  /// A per-token duration multiplier for phonemes already produced.
  ///
  /// **This changes no phoneme.** It is a parallel array of multipliers, one
  /// per Kokoro token, applied to the model's own predicted durations. The
  /// token sequence, its order and its identity are untouched — which is the
  /// whole reason for doing timing this way rather than by repeating tokens.
  /// Repetition would turn a long vowel into two vowels and a held consonant
  /// into a geminate, both of which are different phonemes.
  ///
  /// `SanskritProsody` splits a verse into pādas and synthesizes each one
  /// separately, so a scale computed over the whole verse would not line up
  /// with any single call's tokens. This derives one for exactly the phonemes
  /// being sent. Returns `nil` for the neutral intent, so the default path is
  /// byte identical to having no prosody layer at all.
  static func durationScaleForPhonemes(
    _ phonemes: String,
    intent: SanskritProsodyIntent = .neutral
  ) -> [Float]? {
    guard intent != .neutral else { return nil }
    let tokens = Tokenizer.tokenize(phonemizedText: phonemes)
    guard !tokens.isEmpty else { return nil }
    let vocab = (try? KokoroConfig.loadConfig().vocab) ?? [:]
    var scale: [Float] = []
    var previousWasVowel = false
    // Positions of every `h` that closes a word — a visarga, since Sanskrit ह
    // never ends a word. Its syllable is the vowel run just before it.
    let kept = phonemes.unicodeScalars.filter { vocab[String($0)] != nil }
    var visargaPositions: Set<Int> = []
    for (index, scalar) in kept.enumerated() where scalar == "h" {
      let next = index + 1 < kept.count ? kept[kept.index(kept.startIndex, offsetBy: index + 1)] : " "
      guard next == " " || ",.;:!?".unicodeScalars.contains(next) || index == kept.count - 1
      else { continue }
      visargaPositions.insert(index)
      // ...and the vowel (plus its length mark) immediately before it.
      var back = index - 1
      while back >= 0 {
        let previous = kept[kept.index(kept.startIndex, offsetBy: back)]
        let isVowelish = "aeiouɑɐɒæɔəɛɜɨɪɯøœʊʌɤː".unicodeScalars.contains(previous)
        if !isVowelish { break }
        visargaPositions.insert(back)
        back -= 1
      }
    }

    var position = -1
    for scalar in phonemes.unicodeScalars where vocab[String(scalar)] != nil {
      position += 1
      let isVowel = "aeiouɑɐɒæɔəɛɜɨɪɯøœʊʌɤ".unicodeScalars.contains(scalar)
      if isVowel {
        // Weight is not known from the phoneme string alone, so the vowel's
        // own length stands in for it: a long vowel is always guru, and a
        // short one is guru only when a coda closes it — which the held-coda
        // rule below already lengthens.
        scale.append(intent.laghuVowelScale)
      } else if scalar == "ː" {
        // Promote the vowel this lengthens, and itself, to the guru scale.
        // Multiplied rather than assigned: assigning would clobber a visarga
        // multiplier already applied to that same vowel.
        let promotion = intent.laghuVowelScale == 0
          ? 1 : intent.guruVowelScale / intent.laghuVowelScale
        if let last = scale.indices.last { scale[last] *= promotion }
        scale.append(intent.guruVowelScale)
      } else if scalar == "ʰ" {
        scale.append(intent.aspirationScale)
      } else if !previousWasVowel, !scale.isEmpty {
        // A consonant directly after another consonant is a cluster member —
        // the closing half-letter the reference says to hold.
        scale.append(intent.heldCodaScale)
      } else {
        scale.append(1.0)
      }
      previousWasVowel = isVowel
      if visargaPositions.contains(position), let last = scale.indices.last {
        scale[last] *= intent.visargaSyllableScale
      }
    }
    return scale.count == tokens.count ? scale : nil
  }

  /// The same scale for a whole text, derived from its syllable weights rather
  /// than from vowel length alone. More accurate than
  /// `durationScaleForPhonemes`, and usable when the text is synthesized in
  /// one call.
  static func durationScale(
    for text: String,
    options: SanskritOptions = .default,
    intent: SanskritProsodyIntent = .neutral
  ) -> [Float]? {
    guard intent != .neutral else { return nil }
    let result = SanskritPhonemizer.analyze(text, options: options)
    let syllabified = SanskritSyllabifier.syllabify(result.units, options: options)
    let tokenCount = result.tokens.count
    guard tokenCount > 0 else { return nil }

    var scale = [Float](repeating: 1.0, count: tokenCount)

    // Map each syllable onto the token range of the akṣaras it draws on, using
    // the alignment the phonemizer already computes. Then, inside that range,
    // scale the vowel tokens by weight and the length and aspiration marks
    // with them.
    var tokensForAkshara: [Int: Range<Int>] = [:]
    for (index, entry) in result.alignment.enumerated() {
      tokensForAkshara[index] = entry.tokenIndices
    }
    let phonemeScalars = Array(result.kokoroPhonemes.unicodeScalars)
    // Token index -> scalar index. Nothing is dropped for Sanskrit, but derive
    // it rather than assume.
    let vocab = (try? KokoroConfig.loadConfig().vocab) ?? [:]
    var scalarForToken: [Int] = []
    for (offset, scalar) in phonemeScalars.enumerated()
    where vocab[String(scalar)] != nil {
      scalarForToken.append(offset)
    }

    func isVowelScalar(_ scalar: Unicode.Scalar) -> Bool {
      "aeiouɑɐɒæɔəɛɜɨɪɯøœʊʌɤ".unicodeScalars.contains(scalar)
    }

    for syllable in syllabified.syllables {
      let vowelFactor = syllable.weight == .guru
        ? intent.guruVowelScale : intent.laghuVowelScale
      for aksharaIndex in syllable.aksharaIndices {
        guard let range = tokensForAkshara[aksharaIndex] else { continue }
        for token in range where token < tokenCount {
          guard token < scalarForToken.count else { continue }
          let scalar = phonemeScalars[scalarForToken[token]]
          if isVowelScalar(scalar) {
            scale[token] *= vowelFactor
          } else if scalar == "ː" {
            // The length mark rides with its vowel.
            scale[token] *= vowelFactor
          } else if scalar == "ʰ" {
            scale[token] *= intent.aspirationScale
          } else if syllable.holdClosingConsonant,
                    !syllable.coda.isEmpty,
                    token == range.upperBound - 1 {
            // The closing half-letter of a conjunct: held, not vowel-broken.
            scale[token] *= intent.heldCodaScale
          }
        }
      }
    }
    return scale
  }
}
