#!/usr/bin/env python3
"""Remove only border-connected magenta while keeping the subject fully opaque."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--edge-blur", type=float, default=0.55)
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGB")
    width, height = source.size
    source_pixels = source.load()
    background = bytearray(width * height)
    queue: deque[int] = deque()

    def looks_like_magenta(x: int, y: int) -> bool:
        red, green, blue = source_pixels[x, y]
        return (
            red > 160
            and blue > 125
            and green < 105
            and red - green > 80
            and blue - green > 75
        )

    def enqueue(x: int, y: int) -> None:
        index = y * width + x
        if not background[index] and looks_like_magenta(x, y):
            background[index] = 1
            queue.append(index)

    for x in range(width):
        enqueue(x, 0)
        enqueue(x, height - 1)
    for y in range(height):
        enqueue(0, y)
        enqueue(width - 1, y)

    while queue:
        index = queue.popleft()
        x = index % width
        y = index // width
        if x > 0:
            enqueue(x - 1, y)
        if x + 1 < width:
            enqueue(x + 1, y)
        if y > 0:
            enqueue(x, y - 1)
        if y + 1 < height:
            enqueue(x, y + 1)

    alpha = Image.new("L", source.size, 255)
    alpha_pixels = alpha.load()
    for y in range(height):
        row = y * width
        for x in range(width):
            if background[row + x]:
                alpha_pixels[x, y] = 0

    if args.edge_blur > 0:
        alpha = alpha.filter(ImageFilter.GaussianBlur(args.edge_blur))

    output = source.convert("RGBA")
    output.putalpha(alpha)
    output_pixels = output.load()
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha_value = output_pixels[x, y]
            if alpha_value == 0:
                output_pixels[x, y] = (0, 0, 0, 0)
            elif alpha_value < 250:
                # Neutralize only residual key-color contamination at the
                # outer antialiased edge. Opaque fur, eyes, nose and devices
                # retain the exact RGB values from the generated source.
                excess = max(0, min(red - green, blue - green))
                if excess > 8:
                    red = max(0, red - excess)
                    blue = max(0, blue - excess)
                    output_pixels[x, y] = (red, green, blue, alpha_value)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output, optimize=True)
    opaque = sum(1 for value in alpha.getdata() if value == 255)
    partial = sum(1 for value in alpha.getdata() if 0 < value < 255)
    print(f"Opaque pixels: {opaque}; edge pixels: {partial}")


if __name__ == "__main__":
    main()
