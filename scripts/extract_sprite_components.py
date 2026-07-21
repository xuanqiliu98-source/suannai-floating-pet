#!/usr/bin/env python3
"""Extract complete sprite subjects by connected component instead of hard cells."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


def components(mask: Image.Image) -> list[list[int]]:
    width, height = mask.size
    values = mask.tobytes()
    visited = bytearray(width * height)
    found: list[list[int]] = []

    for start, value in enumerate(values):
        if visited[start] or value == 0:
            continue
        visited[start] = 1
        queue: deque[int] = deque([start])
        component: list[int] = []
        while queue:
            index = queue.popleft()
            component.append(index)
            x = index % width
            y = index // width
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if not (0 <= nx < width and 0 <= ny < height):
                    continue
                neighbor = ny * width + nx
                if visited[neighbor] or values[neighbor] == 0:
                    continue
                visited[neighbor] = 1
                queue.append(neighbor)
        found.append(component)
    return found


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--rows", type=int, default=1)
    parser.add_argument("--per-row", type=int, required=True)
    parser.add_argument("--width", type=int, default=192)
    parser.add_argument("--height", type=int, default=208)
    parser.add_argument("--alpha-threshold", type=int, default=32)
    parser.add_argument("--padding", type=int, default=8)
    args = parser.parse_args()

    strip = Image.open(args.input).convert("RGBA")
    extracted: list[tuple[Image.Image, tuple[int, int, int, int]]] = []

    # Generated contact sheets rarely place the visual gap at the exact
    # mathematical row boundary. Find the quietest scanline near each expected
    # split so ears or tails crossing the midpoint are not clipped.
    strip_alpha = strip.getchannel("A")
    strip_binary = strip_alpha.point(
        lambda value: 255 if value > args.alpha_threshold else 0
    )
    row_boundaries = [0]
    for boundary_index in range(1, args.rows):
        expected = round(boundary_index * strip.height / args.rows)
        radius = max(8, round(strip.height / args.rows / 4))
        search_top = max(row_boundaries[-1] + 1, expected - radius)
        search_bottom = min(strip.height - 1, expected + radius)
        candidates: list[tuple[int, int, int]] = []
        for y in range(search_top, search_bottom + 1):
            occupied = sum(
                1 for value in strip_binary.crop((0, y, strip.width, y + 1)).getdata()
                if value
            )
            candidates.append((occupied, abs(y - expected), y))
        row_boundaries.append(min(candidates)[2])
    row_boundaries.append(strip.height)

    for row_index in range(args.rows):
        row_top = row_boundaries[row_index]
        row_bottom = row_boundaries[row_index + 1]
        row = strip.crop((0, row_top, strip.width, row_bottom))
        alpha = row.getchannel("A")
        binary = alpha.point(lambda value: 255 if value > args.alpha_threshold else 0)
        row_components = components(binary)
        substantial = [component for component in row_components if len(component) > 400]
        selected = sorted(substantial, key=len, reverse=True)[: args.per_row]
        if len(selected) != args.per_row:
            raise ValueError(
                f"row {row_index}: expected {args.per_row} sprites, found {len(selected)}"
            )
        selected.sort(key=lambda component: min(index % row.width for index in component))

        for component in selected:
            mask = Image.new("L", row.size, 0)
            mask_pixels = mask.load()
            xs: list[int] = []
            ys: list[int] = []
            for index in component:
                x = index % row.width
                y = index // row.width
                mask_pixels[x, y] = 255
                xs.append(x)
                ys.append(y)

            # Re-include the soft matte surrounding this component while
            # excluding nearby sprites that happen to cross an equal cell edge.
            soft_mask = mask.filter(ImageFilter.MaxFilter(7))
            subject = Image.new("RGBA", row.size, (0, 0, 0, 0))
            subject.paste(row, (0, 0), soft_mask)
            bbox = (
                max(0, min(xs) - args.padding),
                max(0, min(ys) - args.padding),
                min(row.width, max(xs) + args.padding + 1),
                min(row.height, max(ys) + args.padding + 1),
            )
            extracted.append((subject, bbox))

    content_width = max(bbox[2] - bbox[0] for _, bbox in extracted)
    content_height = max(bbox[3] - bbox[1] for _, bbox in extracted)
    crop_height = max(content_height, round(content_width * args.height / args.width))
    crop_width = round(crop_height * args.width / args.height)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for index, (subject, bbox) in enumerate(extracted):
        center_x = round((bbox[0] + bbox[2]) / 2)
        bottom = min(subject.height, bbox[3])
        left = center_x - crop_width // 2
        top = bottom - crop_height

        canvas = Image.new("RGBA", (crop_width, crop_height), (0, 0, 0, 0))
        source_left = max(0, left)
        source_top = max(0, top)
        source_right = min(subject.width, left + crop_width)
        source_bottom = min(subject.height, top + crop_height)
        piece = subject.crop((source_left, source_top, source_right, source_bottom))
        canvas.alpha_composite(piece, (source_left - left, source_top - top))
        frame = canvas.resize((args.width, args.height), Image.Resampling.LANCZOS)

        pixels = frame.load()
        for y in range(frame.height):
            for x in range(frame.width):
                red, green, blue, alpha_value = pixels[x, y]
                if 0 < alpha_value < 250:
                    excess = max(0, min(red - green, blue - green))
                    if excess > 6:
                        red = max(0, red - excess)
                        blue = max(0, blue - excess)
                        pixels[x, y] = (red, green, blue, alpha_value)
        frame.save(args.output_dir / f"{index:02d}.png", optimize=True)


if __name__ == "__main__":
    main()
