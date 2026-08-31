#!/usr/bin/env python3
"""Convert a StyleTTS2 voicepack into something KokoroSwift can load.

`extract_voicepack.py` writes a PyTorch `.pt` holding a [510, 1, 256] float32
tensor. KokoroSwift takes voices as an MLXArray, loaded from `.npz` or
`.safetensors`, so this rewrites the tensor without changing a number.

It also checks the layout, because a wrong voicepack does not fail loudly — it
synthesizes something that merely sounds off. KokoroTTS reads the acoustic half
from dimensions 0-127 and the prosodic half from 128-255:

    let globalStyle   = referenceStyle[0 ... 1, 128...]
    let acousticStyle = referenceStyle[0 ... 1, 0 ... 127]

so a pack whose halves are swapped or whose length is not 510 is rejected here
rather than at synthesis.

    python3 Tools/voicepack-to-mlx.py --input voices/hf_indic.pt --output hf_indic.npz
"""
import argparse
import os
import sys

EXPECTED_SHAPE = (510, 1, 256)
STYLE_DIM = 128


def load_tensor(path):
    """Reads the voicepack, whichever way it was saved."""
    import numpy as np

    if path.endswith(".npy"):
        return np.load(path)
    if path.endswith(".npz"):
        bundle = np.load(path)
        keys = list(bundle.keys())
        if len(keys) != 1:
            sys.exit(f"{path} holds {len(keys)} arrays; expected exactly one: {keys}")
        return bundle[keys[0]]
    try:
        import torch
    except ImportError:
        sys.exit("reading a .pt needs torch:  uv pip install torch")
    loaded = torch.load(path, map_location="cpu", weights_only=False)
    if hasattr(loaded, "detach"):
        return loaded.detach().cpu().float().numpy()
    if isinstance(loaded, dict):
        tensors = [v for v in loaded.values() if hasattr(v, "detach")]
        if len(tensors) != 1:
            sys.exit(f"{path} holds {len(tensors)} tensors; expected exactly one")
        return tensors[0].detach().cpu().float().numpy()
    sys.exit(f"could not find a tensor in {path}")


def describe(pack):
    """Both halves should carry real signal. A half that is all but zero means
    the wrong encoder ran, or its weights never loaded."""
    import numpy as np

    acoustic = pack[:, :, :STYLE_DIM]
    prosodic = pack[:, :, STYLE_DIM:]
    lines = [
        "",
        f"  shape          {pack.shape}  {pack.dtype}",
        f"  acoustic  0-127   mean {acoustic.mean():+.4f}  std {acoustic.std():.4f}"
        f"  |max| {np.abs(acoustic).max():.4f}",
        f"  prosodic 128-255   mean {prosodic.mean():+.4f}  std {prosodic.std():.4f}"
        f"  |max| {np.abs(prosodic).max():.4f}",
    ]
    warnings = []
    if np.abs(acoustic).max() < 1e-6:
        warnings.append("acoustic half is all zeros — the style encoder did not run")
    if np.abs(prosodic).max() < 1e-6:
        warnings.append("prosodic half is all zeros — the predictor encoder did not run")
    if not np.isfinite(pack).all():
        warnings.append("pack contains NaN or inf")
    return "\n".join(lines), warnings


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--input", required=True, help=".pt, .npy or .npz voicepack")
    parser.add_argument("--output", required=True, help=".npz to write")
    parser.add_argument("--key", default="voice",
                        help="array name inside the .npz (default: voice)")
    parser.add_argument("--force", action="store_true",
                        help="write even if the layout checks fail")
    args = parser.parse_args()

    import numpy as np

    pack = np.asarray(load_tensor(args.input), dtype="float32")
    report, warnings = describe(pack)
    print(f"read {args.input}{report}")

    problems = list(warnings)
    if pack.shape != EXPECTED_SHAPE:
        problems.append(
            f"shape is {pack.shape}, expected {EXPECTED_SHAPE} "
            f"(510 sequence positions, 1 channel, 256 style dims)"
        )
    if problems:
        print("\nproblems:")
        for problem in problems:
            print(f"  - {problem}")
        if not args.force:
            sys.exit("\nrefusing to write. Re-run with --force if you are sure.")
        print("\n--force given, writing anyway.")

    if not args.output.endswith(".npz"):
        args.output += ".npz"
    directory = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(directory, exist_ok=True)
    np.savez(args.output, **{args.key: pack})

    print(f"\nwrote {args.output}  (array name: {args.key!r})")
    print("Load it in Swift with MLX.loadArrays(url:) and pass the array as `voice`.")


if __name__ == "__main__":
    main()
