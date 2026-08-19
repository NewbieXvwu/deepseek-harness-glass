#!/usr/bin/env python3
"""Generate and enforce an auditable official/native visual comparison policy."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageChops, ImageDraw


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--scene", required=True)
    parser.add_argument("--policy", type=Path)
    parser.add_argument(
        "--column-fixtures",
        type=Path,
        help="Official column layout fixtures used to derive system-material regions.",
    )
    return parser.parse_args()


def material_regions(fixtures_path: Path | None, width: int, height: int) -> list[dict[str, Any]]:
    """Derive the sidebar and inspector bands from the official layout fixtures.

    AppKit draws those two columns with WindowServer-owned system materials
    whose exact pixels the WebUI cannot reproduce, so they are excluded from
    the content-layer comparison instead of being hardcoded here. The bands
    are taken from the fixture whose viewport matches the captured width, so
    the exclusion always tracks the spec rather than drifting from it.
    """
    if fixtures_path is None:
        return []
    with fixtures_path.open(encoding="utf-8") as handle:
        document = json.load(handle)
    match = next(
        (f for f in document.get("fixtures", []) if int(f.get("viewport", -1)) == width),
        None,
    )
    if match is None:
        raise SystemExit(
            f"no official column fixture with viewport {width}; cannot derive material regions"
        )
    expected = match["expected"]
    sidebar = int(expected["sidebar"])
    details = int(expected["details"])
    regions: list[dict[str, Any]] = []
    if sidebar > 0:
        regions.append({"name": "sidebar", "x0": 0, "x1": sidebar, "y0": 0, "y1": height})
    if details > 0:
        regions.append({"name": "details", "x0": width - details, "x1": width, "y0": 0, "y1": height})
    return regions


def load_policy(path: Path | None, scene: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if path is None:
        return {"mode": "report-only"}, {"source": None, "materialDifferenceChannelThreshold": 12}
    with path.open(encoding="utf-8") as handle:
        document = json.load(handle)
    scene_policy = document.get("scenes", {}).get(scene, document.get("defaultPolicy", {}))
    if not isinstance(scene_policy, dict):
        raise SystemExit(f"visual policy for scene {scene!r} must be an object")
    if scene_policy.get("mode") not in {"report-only", "enforce"}:
        raise SystemExit("visual policy mode must be report-only or enforce")
    return scene_policy, {
        "source": str(path),
        "schemaVersion": document.get("schemaVersion"),
        "officialSourceCommit": document.get("officialSourceCommit"),
        "materialDifferenceChannelThreshold": document.get("materialDifferenceChannelThreshold", 12),
    }


def threshold_results(metrics: dict[str, float], policy: dict[str, Any]) -> list[dict[str, Any]]:
    strict = policy.get("strict", {})
    if not strict:
        return []
    accepted = {
        "maxMateriallyChangedRatio": "materiallyChangedRatio",
        "maxMeanAbsoluteChannelDifference": "meanAbsoluteChannelDifference",
        "maxExactChangedRatio": "exactChangedRatio",
        "maxContentMateriallyChangedRatio": "contentMateriallyChangedRatio",
        "maxContentExactChangedRatio": "contentExactChangedRatio",
        "maxContentMeanAbsoluteChannelDifference": "contentMeanAbsoluteChannelDifference",
    }
    results: list[dict[str, Any]] = []
    for policy_key, metric_key in accepted.items():
        if policy_key not in strict:
            continue
        if metric_key not in metrics:
            raise SystemExit(
                f"policy sets {policy_key} but {metric_key} was not computed; "
                "pass --column-fixtures so material regions can be excluded"
            )
        maximum = float(strict[policy_key])
        actual = float(metrics[metric_key])
        results.append({
            "metric": metric_key,
            "maximum": maximum,
            "actual": actual,
            "passed": actual <= maximum,
        })
    return results


def main() -> None:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    policy, policy_metadata = load_policy(args.policy, args.scene)

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
    material_channel_threshold = int(policy_metadata["materialDifferenceChannelThreshold"])
    changed = per_pixel > 0
    materially_changed = per_pixel > material_channel_threshold

    # Content-layer mask: everything except the system-material columns.
    regions = material_regions(args.column_fixtures, official.width, official.height)
    content_mask = np.ones(per_pixel.shape, dtype=bool)
    for region in regions:
        content_mask[region["y0"]:region["y1"], region["x0"]:region["x1"]] = False

    metrics = {
        "exactChangedRatio": round(float(changed.mean()), 8),
        "materiallyChangedRatio": round(float(materially_changed.mean()), 8),
        "meanAbsoluteChannelDifference": round(float(absolute.mean()), 6),
        "maxAbsoluteChannelDifference": int(absolute.max()),
    }
    if regions and content_mask.any():
        content_absolute = absolute[content_mask]
        metrics.update({
            "contentExactChangedRatio": round(float(changed[content_mask].mean()), 8),
            "contentMateriallyChangedRatio": round(float(materially_changed[content_mask].mean()), 8),
            "contentMeanAbsoluteChannelDifference": round(float(content_absolute.mean()), 6),
            "contentMaxAbsoluteChannelDifference": int(content_absolute.max()),
        })

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
        draw.text((index * panel_width + 12, 9), label, fill="black")
    contact_path = args.out_dir / f"{args.scene}-comparison.png"
    contact.save(contact_path)

    thresholds = threshold_results(metrics, policy)
    passed = all(item["passed"] for item in thresholds)
    report = {
        "scene": args.scene,
        "official": str(args.official),
        "native": str(args.native),
        "dimensions": {"width": official.width, "height": official.height},
        "pixels": official.width * official.height,
        "exactChangedPixels": int(changed.sum()),
        "materiallyChangedPixels": int(materially_changed.sum()),
        "materialDifferenceChannelThreshold": material_channel_threshold,
        "materialRegionsExcluded": regions,
        **metrics,
        "policy": {
            **policy_metadata,
            "mode": policy.get("mode"),
            "thresholds": thresholds,
            "passed": passed if thresholds else None,
            "systemRenderingExceptions": policy.get("systemRenderingExceptions", []),
            "humanReviewRequired": policy.get("humanReviewRequired", False),
            "humanReviewCriteria": policy.get("humanReviewCriteria", []),
        },
        "artifacts": {
            "amplifiedDiff": diff_path.name,
            "contactSheet": contact_path.name,
        },
        "interpretation": (
            "A report-only scene requires human classification and is never visual completion evidence. "
            "An enforce scene fails CI when a strict metric exceeds policy; a pass still requires the policy's "
            "documented human review before a TODO item may be checked."
        ),
    }
    report_path = args.out_dir / f"{args.scene}-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))

    if policy.get("mode") == "enforce" and not passed:
        failures = ", ".join(
            f"{item['metric']}={item['actual']} > {item['maximum']}"
            for item in thresholds if not item["passed"]
        )
        raise SystemExit(f"visual policy failed for {args.scene}: {failures}")


if __name__ == "__main__":
    main()
