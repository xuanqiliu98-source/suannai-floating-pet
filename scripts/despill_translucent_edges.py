#!/usr/bin/env python3
"""Neutralize chroma spill only on the faint outer alpha fringe."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--alpha-max", type=int, default=96)
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if not 0 < alpha <= args.alpha_max:
                continue
            excess = max(0, min(red - green, blue - green))
            if excess > 10:
                red = max(0, red - round(excess * 0.78))
                blue = max(0, blue - round(excess * 0.92))
                pixels[x, y] = (red, green, blue, alpha)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
