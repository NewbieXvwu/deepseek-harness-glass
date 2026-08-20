#!/usr/bin/env python3
"""Measure dark foreground bounds in a known sidebar footer crop.

This review-only deterministic helper never modifies screenshots or production
assets. The 5..160 x 790..825 crop excludes window-edge antialiasing and the
central composer while isolating the light-mode Settings icon and label.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def foreground_bounds(path: Path) -> tuple[int, int, int, int]:
    image = Image.open(path).convert("RGB")
    points: list[tuple[int, int]] = []
    for y in range(790, min(825, image.height)):
        for x in range(5, min(160, image.width)):
            red, green, blue = image.getpixel((x, y))
            # Light-mode shell foreground is near neutral #1f; retain glyph and
            # text antialiasing while rejecting neutral sidebar/background fills.
            if max(red, green, blue) < 125 and max(red, green, blue) - min(red, green, blue) < 35:
                points.append((x, y))
    if not points:
        raise RuntimeError(f"no footer foreground found in {path}")
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return min(xs), min(ys), max(xs), max(ys)


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} OFFICIAL_PNG NATIVE_PNG")
    for label, raw_path in (("official", sys.argv[1]), ("native", sys.argv[2])):
        left, top, right, bottom = foreground_bounds(Path(raw_path))
        print(f"{label}: left={left} top={top} right={right} bottom={bottom}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
