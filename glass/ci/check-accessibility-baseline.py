#!/usr/bin/env python3
"""Validate the native accessibility baseline against locked official core paths."""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASELINE_PATH = ROOT / "Sources/Spec/Fixtures/official-accessibility-baseline.json"

baseline = json.loads(BASELINE_PATH.read_text())
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
        failures.append(f"{path['scene']}: source is missing: {path['source']}")
        continue
    text = source.read_text()
    for label in path.get("requiredLabels", []):
        if f"OfficialUISpec.Text.{label}" not in text:
            failures.append(f"{path['scene']}: missing OfficialUISpec.Text.{label} in {path['source']}")
    contract = path.get("focusContract", "")
    if not contract:
        failures.append(f"{path['scene']}: focus contract must be documented")

all_ui = "\n".join(path.read_text() for path in (ROOT / "Sources/UI").rglob("*.swift"))
for marker in baseline.get("requiredEnvironmentMarkers", []):
    if marker not in all_ui:
        failures.append(f"native UI must declare accessibility environment marker {marker!r}")

if failures:
    print("Accessibility baseline check failed:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Accessibility baseline: {len(baseline['corePaths'])} core paths and system preferences verified")
