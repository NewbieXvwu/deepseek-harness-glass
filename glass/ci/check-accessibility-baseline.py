#!/usr/bin/env python3
"""Validate the native accessibility baseline manifest structure and principles."""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASELINE_PATH = ROOT / "Sources/Spec/Fixtures/official-accessibility-baseline.json"

if not BASELINE_PATH.exists():
    print("Accessibility baseline fixture missing", file=sys.stderr)
    sys.exit(1)

baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
failures: list[str] = []

if baseline.get("schemaVersion") != 1:
    failures.append("accessibility baseline schemaVersion must be 1")
if baseline.get("officialSourceCommit") != "141eb6fef83422698aef7a981029e843e8161534":
    failures.append("accessibility baseline must pin the locked official source commit")
if "macOSDynamicType" not in baseline.get("principles", {}):
    failures.append("accessibility baseline must document the macOS dynamicTypeSize platform limitation")

for path in baseline.get("corePaths", []):
    source = ROOT / path["source"]
    if not source.exists():
        failures.append(f"{path['scene']}: source path does not exist: {path['source']}")

if failures:
    print("Accessibility baseline check failed:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Accessibility baseline: {len(baseline.get('corePaths', []))} core paths verified")
