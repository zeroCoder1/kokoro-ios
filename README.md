# Kokoro TTS for Swift

✨ *New in 1.0.8:* Added timestamps for each token. Please check [Kokoro Test App](https://github.com/mlalma/KokoroTestApp) how to use them.

✨ *New in 1.0.5:* Voice styles are moved out of the library to the integrating application. Please check [Kokoro Test App](https://github.com/mlalma/KokoroTestApp) how to use them.

Kokoro is a high-quality TTS (text-to-speech) model, providing faster than real-time English and Hindi audio generation.

*NOTE:* This is a SPM package of the TTS engine. For an application integrating Kokoro and showing how the neural speech synthesis works, please see [KokoroTestApp](https://github.com/mlalma/KokoroTestApp) project.

Kokoro TTS port is based on the great work done in [MLX-Audio project](https://github.com/Blaizzy/mlx-audio), where the model was ported from PyTorch to MLX Python. This project ports the MLX Python code to MLX Swift.

Currently the library generates audio ~3.3 times faster than real-time on the release build on iPhone 13 Pro after warm up / first run.

## Requirements

- iOS 18.0+
- macOS 15.0+
- (Other Apple platforms may work as well)

## Installation

Add KokoroSwift to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/mlalma/kokoro-ios.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "KokoroSwift", package: "kokoro-ios")
    ]
)
```

## Usage

```swift
import KokoroSwift

// Initialize the TTS engine
let modelPath = URL(fileURLWithPath: "path/to/your/model")
let tts = KokoroTTS(modelPath: modelPath, g2p: .misaki)

// Generate speech
let voiceEmbedding = ... // See KokoroTestApp on how to get a voice style as an `MLXArray`
let text = "Hello, this is a test of Kokoro TTS."
let audioBuffer = try tts.generateAudio(voice: voiceEmbedding, language: .enUS, text: text)

// audioBuffer now contains the synthesized speech
```

For native Hindi, select the Hindi G2P front end and pass `.hi` when generating audio:

```swift
let tts = KokoroTTS(modelPath: modelPath, g2p: .hindi)
let hindiAudio = try tts.generateAudio(
    voice: voiceEmbedding,
    language: .hi,
    text: "यह दुनिया की आज की खबर है।"
)

// The same KokoroTTS instance can switch back to English.
let englishAudio = try tts.generateAudio(
    voice: voiceEmbedding,
    language: .enGB,
    text: "Here is today's news."
)
```

The Hindi processor is entirely local and deterministic. On top of Devanagari
it also handles the things that show up in real Hindi text:

- **Numbers** are read in Hindi with Indian grouping — `2024` becomes
  `दो हज़ार चौबीस`, `1,50,000` becomes `एक लाख पचास हज़ार`, and `1947` becomes
  `उन्नीस सौ सैंतालीस`. Devanagari digits `०-९`, decimals and attached `%`, `₹`
  and `$` are covered too. Phone numbers and long identifiers are read digit by
  digit.
- **Latin acronyms** are read as a Hindi speaker says them, so `BJP` becomes
  `बीजेपी` and `IPL` becomes `आईपीएल`.
- **Common English terms** — WhatsApp, Google, ATM, online and about thirty
  more — are spoken in Devanagari rather than with an American accent
  mid-sentence.

Any other Latin text embedded in Hindi still routes through the local Misaki
English processor.

## Delivery Styles

Kokoro predicts a pitch curve and an energy curve from the text and the voice,
then hands both to the decoder. Those curves are where delivery lives, and
`SpeechStyle` reshapes them on the way through:

```swift
let audio = try tts.generateAudio(
    voice: voiceEmbedding,
    language: .enUS,
    text: "And then, all at once, the lights went out.",
    style: .storyteller
)
```

Presets: `.neutral`, `.newsreader`, `.storyteller`, `.excited`, `.calm`. Each is
an ordinary value you can start from and adjust:

```swift
var style = SpeechStyle.newsreader
style.pitchRange = 1.15      // a little more movement than a straight bulletin
style.sentencePause = 0.6    // and longer beats between items
```

| knob | effect |
|---|---|
| `speed` | speaking rate |
| `pitchShiftSemitones` | shifts the whole contour; F0 is in Hz, so this is a true transposition |
| `pitchRange` | scales pitch travel around its own mean — above 1 more sung, below 1 flatter |
| `energy` | scales the energy contour, heard as emphasis |
| `sentencePause` | silence between sentences in `generateContinuousAudio` |

Values are clamped to ranges where the decoder stays believable, and unvoiced
frames are left alone so silences do not ring. The clamping applies to this API
only — `generateAudio(voice:language:text:speed:)` passes its `speed` through
untouched, so existing callers are unaffected.

This is prosody shaping, not learned emotion. It rescales the delivery a voice
already has; it cannot give it a register it never had, and pushed hard it
sounds artificial rather than expressive. Voices graded A and B respond
noticeably better than Grade C ones, so it does more for English than for Hindi.

## Long Text, Pauses and Loudness

`generateAudio` takes at most 510 tokens and throws above that, and it leaves
phrasing entirely to the model. For anything longer than a couple of sentences,
use `generateContinuousAudio`, which splits at sentence boundaries (including
the Devanagari danda `।`), synthesizes each group, and joins them with a pause
you control:

```swift
let audio = try tts.generateContinuousAudio(
    voice: voiceEmbedding,
    language: .hi,
    text: bulletin,          // any length
    style: .newsreader,      // sets pace, pitch movement and the pause
    targetLUFS: -16          // or nil to leave the level alone
)
```

Each segment is trimmed of the decoder's own edge silence before joining, so
the gap is the one you asked for rather than that plus whatever the model added.

Loudness is available on its own if you are assembling audio yourself. The
voice packs render quietly — the Hindi ones sit near -29 LUFS, against roughly
-16 for spoken content — so normalisation is usually worth applying:

```swift
let level = AudioLoudness.integratedLoudness(samples: audio, sampleRate: 24000)
let ready = AudioLoudness.normalized(samples: audio, sampleRate: 24000)
```

Measurement follows ITU-R BS.1770-4, and normalisation is followed by a
look-ahead limiter, so raising a quiet take by 13 dB does not clip it.

## Comparing Hindi Phonemes Against espeak-ng

Kokoro's Hindi voices were trained on espeak-ng's output, which makes espeak the
target distribution regardless of what is more phonetically accurate. `Tools/`
measures where this package's phonemizer diverges from it:

```bash
brew install espeak-ng
KOKORO_PHONEME_DUMP=/tmp/ours.tsv swift test --filter dumpHindiPhonemesForEspeakDiff
python3 Tools/espeak-diff.py /tmp/ours.tsv
```

The report groups differences into stress-only, vowel-length-only, segmental,
and espeak's own retroflex-flap artifact. espeak is **not** a runtime
dependency — it is used offline, to check work.

## Improving the Hindi Voices

The bundled Hindi voices are Grade C, trained on 10–100 minutes each. That is a
training limit, not something the phonemizer can fix. `docs/TRAINING.md` walks
through fine-tuning Kokoro on a larger Hindi corpus to produce better male and
female voices, including the two tools in this repo that prepare the data:

```bash
Tools/prepare-audio.sh <source-wav-dir> <output-dir>   # 24 kHz mono 16-bit
swift run kokoro-labels --transcripts ... --speaker hi_female --output female.txt
```

`kokoro-labels` writes the phoneme column with this package's phonemizer rather
than espeak, so a fine-tuned model learns the phonemes inference actually sends
it — which removes the espeak divergence rather than working around it.

## Running the Tests

Most of the suite is plain Swift and runs with `swift test`. The tests that
touch MLX need a Metal device, and SwiftPM cannot compile Metal shaders, so
`swift build` never produces mlx-swift's `default.metallib`. Install it once:

```bash
Tools/install-metallib.sh
```

It builds via `xcodebuild` (which can compile the shaders) and drops the
result both beside the test binary and in the working directory, since the
first copy is wiped whenever the test bundle is relinked.

Two things the suite deliberately does not do:

- **It never invokes Misaki.** MLX is linked into both the test binary and
  `libMisakiSwift`, and calling into Misaki crashes the test process at
  teardown — one such test is enough to turn a green run into exit 1. Tests
  covering mixed Hindi/English text check that each token is *routed* to the
  right processor rather than running the English one. Misaki works normally at
  runtime; this is a test-linkage problem, not a functional one.
- **It does not chase espeak agreement.** `Tools/espeak-diff.py` reports how far
  the Hindi phonemizer sits from espeak, which is what the current voices were
  trained on, so it is useful evidence. It is not the target: a change that
  lowers agreement and sounds better through the current voice is still the
  right change. Decide by listening — `Tools/hindi-listening-corpus.txt` exists
  for exactly that, and `Tools/hindi-inspect.sh` shows what the phonemes did.

## G2P (Grapheme-to-Phoneme) Options

- `.misaki` - MisakiSwift, the default English G2P processor
- `.hindi` - Native Hindi G2P with number expansion, acronym and Latin handling, and English switching
- `.eSpeakNG` - eSpeak NG, an optional processor whose dependency is commented out by default

## Model Files

You'll need to provide your own Kokoro TTS model file due to its large size as well as voice style. Please see example project [Kokoro Test App](https://github.com/mlalma/KokoroTestApp) how they can be included as a part of the application package.

## Dependencies

This package depends on:
- [MLX Swift](https://github.com/ml-explore/mlx-swift) - Apple's MLX framework for Swift
- [MisakiSwift](https://github.com/mlalma/MisakiSwift) - G2P processor
- [MLXUtilsLibrary](https://github.com/mlalma/MLXUtilsLibrary) - Utility library

## License

This project is licensed under MIT License - see the [LICENSE](LICENSE) file for details.
