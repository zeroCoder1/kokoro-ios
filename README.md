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
    sentencePause: 0.35,     // seconds of silence between sentences
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
