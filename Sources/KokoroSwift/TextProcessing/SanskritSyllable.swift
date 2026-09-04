import Foundation

// Sanskrit syllable structure, weight and conjunct holding.
//
// This layer sits between the phonology and anything Kokoro-specific. It knows
// nothing about tokens or duration in seconds: it produces *linguistic* timing
// metadata — guru/laghu and mātrās — which a later layer may or may not be able
// to act on.
//
// Reference: sanskritguide.com/chapter-4-syllables, used as a linguistic
// description. The rules implemented here are its rules, quoted in place.
//
// An **akṣara** is an orthographic unit: one consonant cluster plus its vowel,
// which is what `SanskritAksharaParser` produces. A **syllable** is a
// phonological unit, and the two differ whenever a consonant closes the
// previous syllable — मन्त्र is three akṣaras (म, न्त्र... ) but two syllables
// (man-tra). Both are printed by the diagnostics, deliberately.

/// गुरु / लघु.
enum SanskritSyllableWeight: Equatable, Sendable {
  /// Light: ends in a short vowel, nothing after it. One mātrā.
  case laghu
  /// Heavy: a long vowel, or closed by a consonant, anusvāra or visarga.
  /// Two mātrās.
  case guru

  var matras: Int { self == .guru ? 2 : 1 }
}

/// Why a syllable is heavy. Recorded so a diagnostic can explain the weight
/// rather than just assert it.
enum SanskritWeightReason: Equatable, Sendable {
  case shortOpenSyllable
  case longVowel
  case closedByConsonant
  case anusvara
  case visarga
  case lineFinal
}

/// One phonological syllable.
struct SanskritSyllable: Equatable, Sendable {
  /// Consonants before the nucleus.
  var onset: [SanskritConsonant] = []
  /// The vowel. Every syllable has exactly one — "a syllable must have one,
  /// and only one, vowel".
  var nucleus: SanskritVowel
  /// Consonants after the nucleus, within this syllable.
  var coda: [SanskritConsonant] = []

  var endsWithAnusvara = false
  var endsWithVisarga = false

  /// Scalar offsets into the normalized source that produced this syllable.
  var sourceOffsets: Range<Int> = 0 ..< 0
  /// Indices of the akṣaras this syllable draws on. A syllable may span two,
  /// because a coda comes from the akṣara that follows its nucleus.
  var aksharaIndices: [Int] = []

  var weight: SanskritSyllableWeight = .laghu
  var weightReason: SanskritWeightReason = .shortOpenSyllable

  var endsWithConsonant: Bool { !coda.isEmpty }
  var matras: Int { weight.matras }

  /// True when this syllable is closed by a consonant that opens a written
  /// conjunct — the "half letter" the guide describes.
  var containsConjunct: Bool { coda.count >= 1 && onsetOfNextIsCluster }
  /// Set by the syllabifier: the following syllable begins with a cluster.
  var onsetOfNextIsCluster = false

  /// Whether the closing consonant should be *held*.
  ///
  /// "Giving ample time to the first half of a conjunct and clearly
  /// enunciating its closing half letter is called holding."
  ///
  /// Holding means duration and clear articulation. It never means inserting a
  /// vowel: सिद्ध must not become सिध, but it must not become सिदध either.
  var holdClosingConsonant: Bool { !coda.isEmpty }

  /// SLP1 for the syllable, for diagnostics.
  var slp1: String {
    var out = onset.map(\.rawValue).joined() + nucleus.rawValue
    if endsWithAnusvara { out += "M" }
    out += coda.map(\.rawValue).joined()
    if endsWithVisarga { out += "H" }
    return out
  }
}

/// Divides a canonical phoneme stream into Sanskrit syllables.
enum SanskritSyllabifier {
  /// The stream the syllabifier works over: phonology segments plus, for each,
  /// the akṣara it came from.
  struct Result {
    var syllables: [SanskritSyllable] = []
    var warnings: [String] = []
  }

  /// Whether the final syllable of the input counts as heavy by position.
  ///
  /// "A syllable is long if it is the last syllable of a line" is a *metrical*
  /// convention, and a line is not a display line. It is off by default so a
  /// UI wrap can never change phonology, and the meter analysis turns it on
  /// per pāda where it belongs.
  static func syllabify(
    _ units: [SanskritUnit],
    options: SanskritOptions = .default,
    lineFinalIsHeavy: Bool = false
  ) -> Result {
    var result = Result()
    let phonology = SanskritPhonology.apply(to: units, options: options)

    // Flatten to (consonant | vowel | boundary) with the akṣara each came from.
    enum Item { case consonant(SanskritConsonant); case vowel(SanskritVowel, Bool); case boundary(SanskritBoundary) }
    var items: [(item: Item, origin: Int?)] = []
    for (index, segment) in phonology.segments.enumerated() {
      let origin = index < phonology.origins.count ? phonology.origins[index] : nil
      switch segment {
      case let .consonant(consonant): items.append((.consonant(consonant), origin))
      case let .vowel(vowel, nasalized): items.append((.vowel(vowel, nasalized), origin))
      case let .boundary(boundary): items.append((.boundary(boundary), origin))
      }
    }

    // Split into stretches that a boundary never crosses: a syllable cannot
    // span a word break or a daṇḍa.
    var stretch: [(item: Item, origin: Int?)] = []
    var stretches: [[(item: Item, origin: Int?)]] = []
    for entry in items {
      if case let .boundary(boundary) = entry.item {
        // Avagraha marks an elision inside continuous speech, so it does not
        // break a syllable; every other boundary does.
        if boundary == .elision { continue }
        if !stretch.isEmpty { stretches.append(stretch); stretch = [] }
        continue
      }
      stretch.append(entry)
    }
    if !stretch.isEmpty { stretches.append(stretch) }

    for stretch in stretches {
      result.syllables += syllabifyStretch(stretch.map { ($0.item, $0.origin) },
                                           warnings: &result.warnings)
    }

    if lineFinalIsHeavy, var last = result.syllables.last, last.weight == .laghu {
      last.weight = .guru
      last.weightReason = .lineFinal
      result.syllables[result.syllables.count - 1] = last
    }
    return result

    // MARK: the division rule

    /// Divides one boundary-free stretch.
    ///
    /// Every syllable has exactly one vowel, so the vowels fix the count. What
    /// the rules decide is where each intervocalic consonant cluster splits:
    ///
    ///   * a single consonant always opens the next syllable — "every syllable
    ///     must begin with a consonant if possible" (मत → ma-ta);
    ///   * otherwise, if the cluster's first consonant is sparśa it closes the
    ///     current syllable and the rest open the next — "when a sparśa
    ///     consonant appears after a vowel, the syllable ends with that
    ///     consonant" (मन्त्र → man-tra, कृत्स्नम् → kṛt-snam);
    ///   * otherwise only the last consonant opens the next syllable, and the
    ///     rest close the current one (धर्म → dhar-ma).
    func syllabifyStretch(
      _ items: [(Item, Int?)],
      warnings: inout [String]
    ) -> [SanskritSyllable] {
      // Positions of the vowels.
      var vowelPositions: [Int] = []
      for (index, entry) in items.enumerated() {
        if case .vowel = entry.0 { vowelPositions.append(index) }
      }
      guard !vowelPositions.isEmpty else {
        if !items.isEmpty { warnings.append("stretch with no vowel: skipped") }
        return []
      }

      var syllables: [SanskritSyllable] = []
      for (order, position) in vowelPositions.enumerated() {
        guard case let .vowel(vowel, nasalized) = items[position].0 else { continue }
        var syllable = SanskritSyllable(nucleus: vowel)
        syllable.endsWithAnusvara = nasalized

        // Onset: whatever the previous split assigned, filled in below.
        // Coda: the consonants between this vowel and the next, minus the
        // next syllable's onset.
        let clusterStart = position + 1
        let clusterEnd = order + 1 < vowelPositions.count
          ? vowelPositions[order + 1] : items.count
        var cluster: [SanskritConsonant] = []
        for index in clusterStart ..< clusterEnd {
          if case let .consonant(consonant) = items[index].0 { cluster.append(consonant) }
        }

        let isLast = order + 1 >= vowelPositions.count
        let split: Int      // how many of the cluster stay in this coda
        if isLast {
          split = cluster.count           // nothing follows; all of it is coda
        } else if cluster.count <= 1 {
          split = 0                       // the next syllable takes it
        } else if cluster[0].isSparsha {
          split = 1
        } else {
          split = cluster.count - 1
        }
        syllable.coda = Array(cluster.prefix(split))
        syllable.onsetOfNextIsCluster = cluster.count - split > 1

        // A visarga is written as `ha` in the canonical consonant stream; the
        // parser already recorded it, so detect it from the akṣara instead of
        // guessing from the phoneme.
        if let origin = items[position].1,
           case let .akshara(akshara) = units[origin], akshara.visarga,
           split == cluster.count, cluster.last == .visarga {
          syllable.coda.removeLast()
          syllable.endsWithVisarga = true
        }

        var offsets: Set<Int> = []
        for index in position ..< min(clusterStart + split, items.count) {
          if let origin = items[index].1 { offsets.insert(origin) }
        }
        syllable.aksharaIndices = offsets.sorted()
        if let first = syllable.aksharaIndices.first,
           let last = syllable.aksharaIndices.last,
           case let .akshara(from) = units[first],
           case let .akshara(to) = units[last] {
          syllable.sourceOffsets = from.sourceOffsets.lowerBound ..< to.sourceOffsets.upperBound
        }

        (syllable.weight, syllable.weightReason) = weigh(syllable)
        syllables.append(syllable)
      }

      // Fill in each onset from the previous syllable's leftover.
      for index in syllables.indices.dropFirst() {
        let previous = syllables[index - 1]
        let start = vowelPositions[index - 1] + 1 + previous.coda.count
          + (previous.endsWithVisarga ? 1 : 0)
        var onset: [SanskritConsonant] = []
        for position in start ..< vowelPositions[index] {
          if case let .consonant(consonant) = items[position].0 { onset.append(consonant) }
        }
        syllables[index].onset = onset
      }
      // And the first syllable's onset is everything before its vowel.
      var firstOnset: [SanskritConsonant] = []
      for position in 0 ..< vowelPositions[0] {
        if case let .consonant(consonant) = items[position].0 { firstOnset.append(consonant) }
      }
      syllables[0].onset = firstOnset
      return syllables
    }
  }

  /// "A syllable is short if and only if it ends in a short vowel."
  private static func weigh(
    _ syllable: SanskritSyllable
  ) -> (SanskritSyllableWeight, SanskritWeightReason) {
    if syllable.nucleus.isProsodicallyLong { return (.guru, .longVowel) }
    if syllable.endsWithVisarga { return (.guru, .visarga) }
    if syllable.endsWithAnusvara { return (.guru, .anusvara) }
    if !syllable.coda.isEmpty { return (.guru, .closedByConsonant) }
    return (.laghu, .shortOpenSyllable)
  }
}
