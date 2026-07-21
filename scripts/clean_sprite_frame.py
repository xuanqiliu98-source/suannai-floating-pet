#!/usr/bin/env python3
"""Remove neighboring sprite fragments and neutralize magenta edge spill."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--alpha-threshold", type=int, default=8)
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGBA")
    width, height = image.size
    pixels = image.load()
    visited = bytearray(width * height)
    components: list[list[int]] = []

    for y in range(height):
        for x in range(width):
            start = y * width + x
            if visited[start] or pixels[x, y][3] <= args.alpha_threshold:
                continue

            visited[start] = 1
            queue: deque[int] = deque([start])
            component: list[int] = []
            while queue:
                index = queue.popleft()
                component.append(index)
                cx = index % width
                cy = index // width
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if not (0 <= nx < width and 0 <= ny < height):
                        continue
                    neighbor = ny * width + nx
                    if visited[neighbor] or pixels[nx, ny][3] <= args.alpha_threshold:
                        continue
                    visited[neighbor] = 1
                    queue.append(neighbor)
            components.append(component)

    if not components:
        raise ValueError("frame has no visible component")
    largest_size = max(len(component) for component in components)
    discard: set[int] = set()
    for component in components:
        xs = [index % width for index in component]
        component_width = max(xs) - min(xs) + 1
        # Chroma-keyed sprite sheets can leave a few isolated pixels from a
        # neighboring cell. Real fur wisps remain connected through their soft
        # alpha fringe, so these very small islands are safe to remove.
        if len(component) < 64:
            discard.update(component)
            continue
        # Generated strips occasionally let the previous cell intrude a thin
        # fragment at x=0. Keep all real subject components (including detached
        # wispy fur), and remove only a narrow, much smaller left-edge fragment.
        if (
            min(xs) <= 1
            and component_width < width * 0.22
            and len(component) < largest_size * 0.35
        ):
            discard.update(component)

    # A clipped tail from the previous sprite can directly touch the current
    # laptop at the hard cell boundary and therefore appear in the same alpha
    # component. Flood only warm neutral fur pixels connected to the left edge;
    # the silver laptop and its dark trim do not satisfy this color predicate.
    def is_fur_pixel(x: int, y: int) -> bool:
        red, green, blue, alpha = pixels[x, y]
        average = (red + green + blue) / 3
        return (
            alpha > args.alpha_threshold
            and 60 < average < 190
            and red >= green - 5
            and green >= blue - 5
            and red - blue < 65
        )

    fur_fragment: set[int] = set()
    queue = deque()
    for y in range(height):
        if is_fur_pixel(0, y):
            index = y * width
            fur_fragment.add(index)
            queue.append(index)

    while queue:
        index = queue.popleft()
        x = index % width
        y = index // width
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if not (0 <= nx < width and 0 <= ny < height):
                continue
            neighbor = ny * width + nx
            if neighbor in fur_fragment or not is_fur_pixel(nx, ny):
                continue
            fur_fragment.add(neighbor)
            queue.append(neighbor)

    if fur_fragment:
        expanded = set(fur_fragment)
        for index in fur_fragment:
            x = index % width
            y = index // width
            for ny in range(max(0, y - 2), min(height, y + 3)):
                for nx in range(max(0, x - 2), min(width, x + 3)):
                    expanded.add(ny * width + nx)
        discard.update(expanded)

    def is_left_non_laptop(x: int, y: int) -> bool:
        red, green, blue, alpha = pixels[x, y]
        average = (red + green + blue) / 3
        is_bright_silver = (
            average > 145
            and abs(red - green) < 28
            and abs(green - blue) < 28
        )
        return alpha > args.alpha_threshold and not is_bright_silver

    edge_fragment: set[int] = set()
    queue.clear()
    for y in range(height):
        if is_left_non_laptop(0, y):
            index = y * width
            edge_fragment.add(index)
            queue.append(index)

    maximum_edge_x = min(28, width - 1)
    while queue:
        index = queue.popleft()
        x = index % width
        y = index // width
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if not (0 <= nx <= maximum_edge_x and 0 <= ny < height):
                continue
            neighbor = ny * width + nx
            if neighbor in edge_fragment or not is_left_non_laptop(nx, ny):
                continue
            edge_fragment.add(neighbor)
            queue.append(neighbor)

    if edge_fragment:
        expanded = set(edge_fragment)
        for index in edge_fragment:
            x = index % width
            y = index // width
            for ny in range(max(0, y - 1), min(height, y + 2)):
                for nx in range(max(0, x - 1), min(width, x + 2)):
                    expanded.add(ny * width + nx)
        discard.update(expanded)

    for y in range(height):
        for x in range(width):
            index = y * width + x
            red, green, blue, alpha = pixels[x, y]
            if index in discard:
                pixels[x, y] = (0, 0, 0, 0)
                continue

            # Only touch translucent matte pixels. Fully opaque pink noses and
            # orange phones remain byte-for-byte unchanged.
            if 0 < alpha < 250:
                magenta_excess = max(0, min(red - green, blue - green))
                if magenta_excess > 6:
                    red = max(0, red - round(magenta_excess * 0.72))
                    blue = max(0, blue - round(magenta_excess * 0.88))
                    pixels[x, y] = (red, green, blue, alpha)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
