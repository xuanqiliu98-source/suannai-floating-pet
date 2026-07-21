#!/usr/bin/env python3
"""Slice a transparent horizontal sprite strip into aligned app frames."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--frames", type=int, default=6, help="legacy column count for one-row strips")
    parser.add_argument("--rows", type=int, default=1)
    parser.add_argument("--columns", type=int)
    parser.add_argument("--width", type=int, default=192)
    parser.add_argument("--height", type=int, default=208)
    parser.add_argument("--padding", type=int, default=10)
    parser.add_argument("--bbox-alpha-threshold", type=int, default=32)
    args = parser.parse_args()

    strip = Image.open(args.input).convert("RGBA")
    columns = args.columns or args.frames
    frame_count = args.rows * columns
    cells: list[Image.Image] = []
    alpha_boxes: list[tuple[int, int, int, int]] = []

    for row in range(args.rows):
        top = round(row * strip.height / args.rows)
        bottom = round((row + 1) * strip.height / args.rows)
        for column in range(columns):
            left = round(column * strip.width / columns)
            right = round((column + 1) * strip.width / columns)
            cell = strip.crop((left, top, right, bottom))
            visible_mask = cell.getchannel("A").point(
                lambda alpha: 255 if alpha > args.bbox_alpha_threshold else 0
            )
            bbox = visible_mask.getbbox()
            if bbox is None:
                raise ValueError(f"frame {len(cells)} has no visible pixels")
            cells.append(cell)
            alpha_boxes.append(bbox)

    # Use one crop size and one scale for every frame so the character does not
    # pulse or jump. Each cell is centered horizontally and bottom-aligned to
    # its own visible content, which also supports multi-row sprite sheets.
    content_width = max(box[2] - box[0] for box in alpha_boxes) + args.padding * 2
    content_height = max(box[3] - box[1] for box in alpha_boxes) + args.padding * 2
    crop_height = max(content_height, round(content_width * args.height / args.width))
    crop_width = round(crop_height * args.width / args.height)

    maximum_width = min(cell.width for cell in cells)
    maximum_height = min(cell.height for cell in cells)
    if crop_width > maximum_width:
        crop_width = maximum_width
        crop_height = round(crop_width * args.height / args.width)
    if crop_height > maximum_height:
        crop_height = maximum_height
        crop_width = round(crop_height * args.width / args.height)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for index, cell in enumerate(cells):
        bbox = alpha_boxes[index]
        center_x = round((bbox[0] + bbox[2]) / 2)
        bottom = min(cell.height, bbox[3] + args.padding)
        top = max(0, bottom - crop_height)
        bottom = top + crop_height
        if bottom > cell.height:
            bottom = cell.height
            top = bottom - crop_height

        left = max(0, center_x - crop_width // 2)
        right = min(cell.width, left + crop_width)
        left = right - crop_width
        cropped = cell.crop((left, top, right, bottom))
        cropped = cropped.resize((args.width, args.height), Image.Resampling.LANCZOS)

        cropped.save(args.output_dir / f"{index:02d}.png", optimize=True)


if __name__ == "__main__":
    main()
