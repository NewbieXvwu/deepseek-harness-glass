#!/usr/bin/env python3
"""Generate an auditable visual comparison for one paired official/native UI state."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--scene", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    official = Image.open(args.official).convert("RGBA")
    native = Image.open(args.native).convert("RGBA")
    if official.size != native.size:
        raise SystemExit(
            f"paired screenshots must have identical dimensions: official={official.size}, native={native.size}"
        )

    official_rgb = np.asarray(official.convert("RGB"), dtype=np.int16)
    native_rgb = np.asarray(native.convert("RGB"), dtype=np.int16)
    absolute = np.abs(official_rgb - native_rgb)
    per_pixel = absolute.max(axis=2)
    changed = per_pixel > 0
    materially_changed = per_pixel > 12

    raw_diff = ImageChops.difference(official.convert("RGB"), native.convert("RGB"))
    amplified = raw_diff.point(lambda value: min(255, value * 6))
    diff_path = args.out_dir / f"{args.scene}-diff-amplified.png"
    amplified.save(diff_path)

    label_height = 34
    panel_width, panel_height = official.size
    contact = Image.new("RGB", (panel_width * 3, panel_height + label_height), "white")
    contact.paste(official.convert("RGB"), (0, label_height))
    contact.paste(native.convert("RGB"), (panel_width, label_height))
    contact.paste(amplified, (panel_width * 2, label_height))
    draw = ImageDraw.Draw(contact)
    for index, label in enumerate(("Official WebUI", "Native macOS", "Amplified absolute difference ×6")):
        x = index * panel_width + 12
        draw.text((x, 9), label, fill="black")
    contact_path = args.out_dir / f"{args.scene}-comparison.png"
    contact.save(contact_path)

    report = {
        "scene": args.scene,
        "official": str(args.official),
        "native": str(args.native),
        "dimensions": {"width": official.width, "height": official.height},
        "pixels": official.width * official.height,
        "exactChangedPixels": int(changed.sum()),
        "exactChangedRatio": round(float(changed.mean()), 8),
        "materiallyChangedPixels": int(materially_changed.sum()),
        "materiallyChangedRatio": round(float(materially_changed.mean()), 8),
        "meanAbsoluteChannelDifference": round(float(absolute.mean()), 6),
        "maxAbsoluteChannelDifference": int(absolute.max()),
        "artifacts": {
            "amplifiedDiff": diff_path.name,
            "contactSheet": contact_path.name,
        },
        "interpretation": (
            "This report detects measurable image differences. It is not by itself a completion verdict: "
            "reviewers must classify each difference as an official-layout/token/state mismatch or a documented "
            "system-material exception, then attach the result to the matching TODO task."
        ),
    }
    report_path = args.out_dir / f"{args.scene}-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
