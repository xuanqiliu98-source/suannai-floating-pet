#!/usr/bin/env python3
"""Restore chroma-like details enclosed by an opaque foreground subject."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="original chroma-key image")
    parser.add_argument("keyed", type=Path, help="background-removed RGBA image")
    parser.add_argument("output", type=Path)
    parser.add_argument("--alpha-threshold", type=int, default=245)
    args = parser.parse_args()

    source = Image.open(args.source).convert("RGBA")
    keyed = Image.open(args.keyed).convert("RGBA")
    if source.size != keyed.size:
        raise ValueError("source and keyed image sizes differ")

    width, height = keyed.size
    alpha = keyed.getchannel("A").tobytes()
    visited = bytearray(width * height)
    queue: deque[int] = deque()

    def enqueue(index: int) -> None:
        if not visited[index] and alpha[index] < args.alpha_threshold:
            visited[index] = 1
            queue.append(index)

    for x in range(width):
        enqueue(x)
        enqueue((height - 1) * width + x)
    for y in range(height):
        enqueue(y * width)
        enqueue(y * width + width - 1)

    while queue:
        index = queue.popleft()
        x = index % width
        if x > 0:
            enqueue(index - 1)
        if x + 1 < width:
            enqueue(index + 1)
        if index >= width:
            enqueue(index - width)
        if index + width < width * height:
            enqueue(index + width)

    source_pixels = source.load()
    keyed_pixels = keyed.load()
    restored = 0
    for y in range(height):
        row = y * width
        for x in range(width):
            index = row + x
            if not visited[index] and alpha[index] < args.alpha_threshold:
                red, green, blue, _ = source_pixels[x, y]
                keyed_pixels[x, y] = (red, green, blue, 255)
                restored += 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    keyed.save(args.output, optimize=True)
    print(f"Restored {restored} enclosed foreground pixels")


if __name__ == "__main__":
    main()
