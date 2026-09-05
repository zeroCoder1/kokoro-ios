import Foundation

/// How long a pause each Sanskrit boundary is worth.
///
/// **These are seconds of real silence, and they are not part of G2P.** They
/// exist because Kokoro's punctuation does not deliver a *differentiated*
/// pause. Measured on this model at verse length, with the same phonemes and
/// only the separator changed:
///
///     separator between the two pādas   longest internal silence
///     none (plain space)                   350 ms
///     `,`  (daṇḍa)                         385 ms
///     `.`  (double daṇḍa)                  355 ms
///
/// The model does insert a substantial gap on its own — about 350 ms — but it
/// inserts roughly the same one whether the punctuation is there or not, and
/// `।` and `॥` come out identical. So the phoneme stream still carries `,`
/// and `.`, because the model uses them for intonation and final lengthening,
/// and this layer supplies the *differentiated duration* the model will not.
/// That is the same mechanism `generateContinuousAudio` uses between
/// sentences.
///
/// The defaults are **totals, not additions**: each stretch is trimmed of the
/// decoder's own edge silence first, so the configured value is the whole gap.
/// They are set above the model's natural 350 ms, or configuring a pause would
/// make the verse *less* separated than leaving it alone.
///
/// `wordBoundary` defaults to zero: the space token measurably does its job,
/// and pausing between every word would sound like dictation rather than
/// recitation.
public struct SanskritProsodyConfiguration: Equatable, Sendable {
  /// Extra silence at an ordinary word boundary. Zero by default — the space
  /// token already separates words.
  public var wordBoundary: TimeInterval
  /// `।` — a pāda or half-verse break.
  public var padaPause: TimeInterval
  /// `॥` — the end of a verse.
  public var versePause: TimeInterval
  /// Sentence punctuation carried over from the source.
  public var sentencePause: TimeInterval

  public init(
    wordBoundary: TimeInterval = 0.0,
    padaPause: TimeInterval = 0.50,
    versePause: TimeInterval = 1.00,
    sentencePause: TimeInterval = 0.50
  ) {
    self.wordBoundary = wordBoundary
    self.padaPause = padaPause
    self.versePause = versePause
    self.sentencePause = sentencePause
  }

  /// Recitation pacing: a clear half-verse break and a longer verse break.
  public static let `default` = SanskritProsodyConfiguration()

  /// No added silence at all — one call, exactly the previous behaviour.
  /// Use this to hear what the model does on its own.
  public static let none = SanskritProsodyConfiguration(
    wordBoundary: 0, padaPause: 0, versePause: 0, sentencePause: 0
  )

  func pause(for boundary: SanskritBoundary) -> TimeInterval {
    switch boundary {
    case .word: return wordBoundary
    case .pada: return padaPause
    case .verse: return versePause
    case .sentence: return sentencePause
    // Neither of these is a pause: an avagraha is an elision inside continuous
    // speech, and a source newline is typography.
    case .elision, .displayLineBreak: return 0
    }
  }
}

/// A speaking rate paired with the pauses that suit it.
///
/// Sanskrit is not English at 1.0. Measured over three pādas — identical
/// phonemes and token ids at every rate, only `speed` changed — by counting
/// separately articulated energy nuclei against the syllables each pāda
/// actually has. The figure is how many syllables went missing:
///
///     speed   BG 1.1 (16)   BG 2.47 (18)   BG 4.7 (18)
///     0.72         ok            -3            ok
///     0.76         ok            -3            ok
///     0.80         ok            -1            ok      ← best across all three
///     0.84         ok            -4            ok
///     0.88         -1            -6            -2
///     0.92         ok            -6            -5
///     1.00         ok            -8            -2
///
/// BG 2.47's first pāda is the discriminating one: it contains
/// कर्मण्येवाधिकारस्ते, twenty-four phonemes in a single orthographic word, and
/// it never reaches its full syllable count. 0.80 is where it comes closest and
/// where the other two are clean, so that is the recitation default — it
/// replaces 0.84, which loses four syllables there.
///
/// This measures articulation, not beauty. Treat the values as a starting
/// point for listening rather than a settled answer.
public struct SanskritDelivery: Equatable, Sendable {
  public var speed: Float
  public var prosody: SanskritProsodyConfiguration
  /// Per-token duration intent applied on top of the model's own prediction.
  ///
  /// Defaults to `.visargaLengthOnly` rather than the fuller `.recitation`,
  /// because those are two different levels of evidence. The visarga repair is
  /// measured against references — काः was arriving at the duration of a short
  /// क, and 1.3× restores it — while the broader guru/laghu scaling has not
  /// shown a consistent whole-verse effect and stays out until listening says
  /// otherwise.
  var intent: SanskritProsodyIntent = .closureRepairs

  /// A delivery with the standard Sanskrit duration intent.
  public init(speed: Float, prosody: SanskritProsodyConfiguration) {
    self.speed = speed
    self.prosody = prosody
    self.intent = .closureRepairs
  }

  init(speed: Float, prosody: SanskritProsodyConfiguration, intent: SanskritProsodyIntent) {
    self.speed = speed
    self.prosody = prosody
    self.intent = intent
  }

  /// Deliberate pace for following along word by word, with long pauses.
  public static let learning = SanskritDelivery(
    speed: 0.76,
    prosody: SanskritProsodyConfiguration(padaPause: 0.70, versePause: 1.30),
    intent: .closureRepairs
  )

  /// The default for recitation. The slowest rate at which every syllable
  /// still resolves separately, without sounding laboured.
  public static let recitation = SanskritDelivery(
    speed: 0.80,
    prosody: SanskritProsodyConfiguration(padaPause: 0.50, versePause: 1.00),
    intent: .closureRepairs
  )

  /// The pace of a human reciter, calibrated against a recorded Gītā pāṭha.
  ///
  /// `recitation`'s 0.80 was chosen as the slowest rate at which Kokoro stopped
  /// *merging* syllables. That is a constraint of the model, and it turns out
  /// to be nowhere near how the Gītā is actually chanted. Measured over 585
  /// anuṣṭubh verses of a single reciter — the Gītā Supersite recordings, one
  /// voice throughout at a median F0 of 182.8 Hz, sd 5.9 Hz, which is chant on
  /// a fixed reciting tone rather than read prose:
  ///
  ///     voiced time per syllable, reciter      477 ms  (sd 33, IQR 456–497)
  ///     voiced time per syllable, ours @0.80   195 ms
  ///
  /// **2.4× slower**, not the 1.7× a measurement including pauses suggests.
  /// Sweeping the rate against that target, voiced time per syllable:
  ///
  ///     speed   0.80  0.65  0.55  0.50  0.46  0.42  0.36  0.30  0.25
  ///     ms/syl   195   238   281   305   322   350   403   475   564
  ///
  /// 0.30 lands on 475 against the reciter's 477 — 473, 474 and 478 across the
  /// three validation verses.
  ///
  /// **Slowing this far costs nothing measurable.** F0 stability, which is what
  /// a stretched acoustic model loses first, is unchanged: median frame-to-frame
  /// pitch jump 0.47 semitones at 0.30 against 0.67 at 0.80, with the reciter at
  /// 0.33–0.39. If anything the slow render is steadier. It also removes the one
  /// defect the syllable-nucleus count can legitimately detect — at 0.80 BG 4.7
  /// loses three syllables to merging and BG 2.47 one, and from 0.50 down
  /// nothing merges.
  ///
  /// The nucleus count *over*-counts at this pace, and that is not evidence of
  /// damage: the reciter over-counts more (+7 to +15 against +28 to +32 here,
  /// on a metric that rewards fast smooth delivery and penalises held chant).
  /// It cannot separate a held syllable from a warble, so it is not what chose
  /// this value; the pace target and the F0 check are.
  ///
  /// The pause is far shorter than `recitation`'s, and the reason inverts the
  /// usual one. Kokoro's *own* gap at the daṇḍa grows as it slows — 390–460 ms
  /// at 0.80, but 550–1150 ms at 0.30 — so at this pace the model over-pauses,
  /// and the split path is what reins it in rather than what supplies the gap.
  /// The reciter's half-verse break measures 410 ms (median over the 292 verses
  /// that take one), and `padaPause` is divided by speed at render time, so
  /// 0.12 ÷ 0.30 ≈ 400 ms.
  ///
  /// `versePause` is **not** calibrated: the reference recordings are trimmed
  /// at the end — median 50 ms of trailing silence — so they say nothing about
  /// how long a reciter rests between verses. It is set to twice the half-verse
  /// break and no more is claimed for it.
  ///
  /// **What this does not reach.** Matching the reciter's syllable *duration*
  /// does not make the verse the reciter's *length*. Kokoro puts silence
  /// between things that the reciter does not: measured at a 2% energy gate,
  /// internal silence is 21% of the span at 0.80 and 29% at 0.30, where the
  /// reciter's recordings are continuous — 0.0% at that gate, 3.3% at 6%.
  /// So BG 2.47 comes out around 27 s here against the reciter's 15.7 s for
  /// the same voiced time. That silence sits *inside* one `generateAudio`
  /// call; no pause setting reaches it.
  ///
  /// The two targets therefore conflict, and this delivery picks the first:
  /// per-syllable duration matches the reciter, total verse length does not.
  /// A rate near 0.46 inverts that — the verse runs about the reciter's
  /// length, with each syllable a third short.
  ///
  /// The 0.30 figure also depends on where the energy gate is put, because
  /// only our side has internal silence to gate out. Across gates of 2/6/10%
  /// the reciter measures 488/471/414 ms and 0.30 measures 542/474/434, so
  /// the honest reading is 0.30–0.33 rather than a single exact value.
  ///
  /// This is a pace, not a pronunciation. The visarga, vocalic ṛ and final
  /// nasal gaps are exactly as they were; see
  /// `docs/SANSKRIT_FINE_TUNING_REQUIREMENTS.md`.
  public static let traditional = SanskritDelivery(
    speed: 0.30,
    prosody: SanskritProsodyConfiguration(padaPause: 0.12, versePause: 0.24),
    intent: .closureRepairs
  )

  /// The voice's own pace. Measurably degraded — BG 2.47's first pāda loses
  /// eight of its eighteen syllables here. Kept for review and for callers who
  /// ask for it; not recommended for recitation.
  public static let fast = SanskritDelivery(
    speed: 1.0,
    prosody: SanskritProsodyConfiguration(padaPause: 0.40, versePause: 0.80),
    intent: .closureRepairs
  )

  /// Exactly the model's own timing, for A/B against any of the above.
  public static let unshaped = SanskritDelivery(
    speed: 0.80,
    prosody: SanskritProsodyConfiguration(padaPause: 0.50, versePause: 1.00),
    intent: .neutral
  )
}

/// Splits a Sanskrit text into stretches that are synthesized separately and
/// rejoined with real silence.
///
/// Strictly a **prosody** layer sitting after G2P, not part of it. The
/// phonemes for a given stretch are exactly what `SanskritPhonemizer` produces
/// for it; nothing here changes a phoneme. Splitting is safe because the
/// phonological rules never look across a pause anyway — the anusvāra and
/// visarga lookaheads both stop at one.
enum SanskritProsody {
  struct Segment: Equatable {
    /// What to synthesize.
    let phonemes: String
    /// Silence to append after it, in seconds.
    let pauseAfter: TimeInterval
    /// The boundary that ended this stretch, for diagnostics.
    let boundary: SanskritBoundary?
  }

  /// Splits at every boundary the configuration gives a non-zero pause to.
  /// With `.none` this returns a single segment and the result is identical
  /// to one `generateAudio` call.
  static func segments(
    for text: String,
    options: SanskritOptions = .default,
    configuration: SanskritProsodyConfiguration = .default
  ) -> [Segment] {
    let normalized = SanskritNormalizer.normalize(text)
    let parsed = SanskritAksharaParser.parse(normalized.text)

    var segments: [Segment] = []
    var pending: [SanskritUnit] = []

    func flush(endedBy boundary: SanskritBoundary?) {
      guard !pending.isEmpty else { return }
      let phonology = SanskritPhonology.apply(to: pending, options: options)
      let mapped = SanskritKokoroMapper.map(phonology.segments, options: options)
      pending.removeAll(keepingCapacity: true)
      guard !mapped.phonemes.isEmpty else { return }
      segments.append(Segment(
        phonemes: mapped.phonemes,
        pauseAfter: boundary.map(configuration.pause(for:)) ?? 0,
        boundary: boundary
      ))
    }

    for unit in parsed.units {
      // A boundary the configuration pauses at ends the stretch, and stays in
      // it: the punctuation token still reaches the model, so intonation and
      // final lengthening are the model's own rather than an abrupt cut.
      if case let .boundary(boundary) = unit, configuration.pause(for: boundary) > 0 {
        pending.append(unit)
        flush(endedBy: boundary)
        continue
      }
      pending.append(unit)
    }
    flush(endedBy: nil)
    return segments
  }
}
