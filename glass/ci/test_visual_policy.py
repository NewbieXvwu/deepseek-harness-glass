#!/usr/bin/env python3
"""Executable proof that visual-policy enforcement rejects a material mismatch."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
COMPARATOR = ROOT / "ci/compare_visual_pair.py"


def run(
    policy: Path,
    official: Path,
    native: Path,
    out_dir: Path,
    *,
    scene: str = "policy-self-test",
    column_fixtures: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable, str(COMPARATOR),
        "--official", str(official),
        "--native", str(native),
        "--out-dir", str(out_dir),
        "--scene", scene,
        "--policy", str(policy),
    ]
    if column_fixtures is not None:
        command.extend(["--column-fixtures", str(column_fixtures)])
    return subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
    )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="dsh-visual-policy-") as temporary:
        temp = Path(temporary)
        policy = temp / "policy.json"
        policy.write_text(json.dumps({
            "schemaVersion": 1,
            "materialDifferenceChannelThreshold": 12,
            "defaultPolicy": {"mode": "report-only"},
            "scenes": {
                "policy-self-test": {
                    "mode": "enforce",
                    "strict": {
                        "maxMateriallyChangedRatio": 0.0,
                        "maxMeanAbsoluteChannelDifference": 0.0,
                        "maxExactChangedRatio": 0.0,
                    },
                },
            },
        }), encoding="utf-8")
        official = temp / "official.png"
        identical = temp / "identical.png"
        different = temp / "different.png"
        Image.new("RGB", (8, 8), "white").save(official)
        Image.new("RGB", (8, 8), "white").save(identical)
        changed = Image.new("RGB", (8, 8), "white")
        changed.putpixel((0, 0), (0, 0, 0))
        changed.save(different)

        passing = run(policy, official, identical, temp / "pass")
        if passing.returncode != 0:
            raise SystemExit(f"identical visual policy self-test unexpectedly failed:\n{passing.stdout}\n{passing.stderr}")
        failing = run(policy, official, different, temp / "fail")
        if failing.returncode == 0:
            raise SystemExit("material visual mismatch unexpectedly passed enforce policy")
        report = json.loads((temp / "fail/policy-self-test-report.json").read_text(encoding="utf-8"))
        if report["policy"]["passed"] is not False:
            raise SystemExit("visual mismatch report did not record failed policy state")

        rail_fixture = temp / "columns.json"
        rail_fixture.write_text(json.dumps({
            "fixtures": [{
                "name": "collapsed-sidebar-compact-rail",
                "viewport": 1023,
                "expected": {"sidebar": 56, "center": 640, "details": 327},
            }],
        }), encoding="utf-8")
        rail_policy = temp / "rail-policy.json"
        rail_policy.write_text(json.dumps({
            "schemaVersion": 1,
            "materialDifferenceChannelThreshold": 12,
            "defaultPolicy": {"mode": "report-only"},
            "scenes": {
                "compact-rail-self-test": {
                    "mode": "enforce",
                    "strict": {
                        "maxContentMateriallyChangedRatio": 0.0,
                        "maxContentMeanAbsoluteChannelDifference": 0.0,
                        "maxContentExactChangedRatio": 0.0,
                    },
                },
            },
        }), encoding="utf-8")
        rail_official = temp / "rail-official.png"
        Image.new("RGB", (1023, 3), "white").save(rail_official)
        material_only = Image.new("RGB", (1023, 3), "white")
        material_only.putpixel((0, 0), (0, 0, 0))
        material_only.putpixel((1022, 2), (0, 0, 0))
        material_only_path = temp / "material-only.png"
        material_only.save(material_only_path)
        material_passing = run(
            rail_policy, rail_official, material_only_path, temp / "rail-material-pass",
            scene="compact-rail-self-test", column_fixtures=rail_fixture,
        )
        if material_passing.returncode != 0:
            raise SystemExit(f"compact rail material mask unexpectedly failed:\n{material_passing.stdout}\n{material_passing.stderr}")
        rail_report = json.loads((temp / "rail-material-pass/compact-rail-self-test-report.json").read_text(encoding="utf-8"))
        if rail_report["materialRegionsExcluded"] != [
            {"name": "sidebar", "x0": 0, "x1": 56, "y0": 0, "y1": 3},
            {"name": "details", "x0": 696, "x1": 1023, "y0": 0, "y1": 3},
        ]:
            raise SystemExit("compact rail material regions did not derive from the 1023px official fixture")
        content_changed = Image.new("RGB", (1023, 3), "white")
        content_changed.putpixel((56, 1), (0, 0, 0))
        content_changed_path = temp / "content-changed.png"
        content_changed.save(content_changed_path)
        content_failing = run(
            rail_policy, rail_official, content_changed_path, temp / "rail-content-fail",
            scene="compact-rail-self-test", column_fixtures=rail_fixture,
        )
        if content_failing.returncode == 0:
            raise SystemExit("compact rail content mismatch unexpectedly passed enforce policy")
    print("Visual policy enforcement self-test passed.")


if __name__ == "__main__":
    main()
