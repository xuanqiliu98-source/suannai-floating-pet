#!/usr/bin/env python3
"""Neutralize chroma spill only on the faint outer alpha fringe."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageFilter


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--alpha-max", type=int, default=96)
    parser.add_argument("--edge-depth", type=int, default=2)
    parser.add_argument("--edge-contract", type=int, default=0)
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGBA")
    pixels = image.load()
    alpha_channel = image.getchannel("A")
    outside = alpha_channel.point(lambda alpha: 255 if alpha <= 8 else 0)
    filter_size = args.edge_depth * 2 + 1
    near_outside = outside.filter(ImageFilter.MaxFilter(filter_size)).load()

    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue
            excess = max(0, min(red - green, blue - green))
            is_outer_edge = near_outside[x, y] > 0

            if is_outer_edge and alpha <= 8:
                pixels[x, y] = (0, 0, 0, 0)
            # Strong key-colored pixels can become fully opaque during sprite
            # extraction. Remove them only when they touch the external matte;
            # enclosed pink details such as the nose and paw pads are untouched.
            elif is_outer_edge and excess > 58 and red > 155 and blue > 125:
                pixels[x, y] = (0, 0, 0, 0)
            elif (alpha <= args.alpha_max or is_outer_edge) and excess > 8:
                # Subtract the same chroma-key component from red and blue.
                # Unequal subtraction turns a purple fringe into a red fringe.
                red = max(0, red - excess)
                blue = max(0, blue - excess)
                pixels[x, y] = (red, green, blue, alpha)

    if args.edge_contract > 0:
        contracted_alpha = image.getchannel("A")
        for _ in range(args.edge_contract):
            contracted_alpha = contracted_alpha.filter(ImageFilter.MinFilter(3))
        image.putalpha(contracted_alpha)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
