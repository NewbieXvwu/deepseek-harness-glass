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


def run(policy: Path, official: Path, native: Path, out_dir: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable, str(COMPARATOR),
            "--official", str(official),
            "--native", str(native),
            "--out-dir", str(out_dir),
            "--scene", "policy-self-test",
            "--policy", str(policy),
        ],
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
    print("Visual policy enforcement self-test passed.")


if __name__ == "__main__":
    main()
