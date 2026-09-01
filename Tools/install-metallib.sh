#!/usr/bin/env bash
# Makes MLX usable from `swift test`.
#
# SwiftPM cannot compile Metal shaders, so `swift build` never produces
# mlx-swift's default.metallib and every MLX call from a test fails with
# "Failed to load the default metallib". Xcode's build system can compile
# them, so this builds once with xcodebuild and drops the result where MLX
# looks for it: a colocated mlx.metallib beside the test binary.
#
# Run once after a clean checkout, and again after `swift package clean`.
#
#   Tools/install-metallib.sh

set -euo pipefail
cd "$(dirname "$0")/.."

derived=$(mktemp -d)
trap 'rm -rf "$derived"' EXIT

echo "building for macOS to compile the Metal shaders..."
xcodebuild -scheme KokoroSwift -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived" build >/dev/null

metallib=$(find "$derived" -name default.metallib -path '*Cmlx*' | head -1)
[[ -n "$metallib" ]] || { echo "no default.metallib was produced" >&2; exit 1; }

swift build --build-tests >/dev/null
xctest=$(find .build -maxdepth 3 -name '*.xctest' | head -1)
[[ -n "$xctest" ]] || { echo "no test bundle; run 'swift build --build-tests'" >&2; exit 1; }

# MLX tries a colocated mlx.metallib before anything else.
install -m 644 "$metallib" "$xctest/Contents/MacOS/mlx.metallib"
echo "installed -> $xctest/Contents/MacOS/mlx.metallib"
echo "MLX-backed tests will now run. Verify with:"
echo "  swift test --filter unvoicedFramesAreNeverLiftedOffZero"
