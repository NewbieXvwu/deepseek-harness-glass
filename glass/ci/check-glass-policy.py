#!/usr/bin/env python3
"""Enforce explicit, narrow Liquid Glass policy in native UI sources."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
UI_ROOT = ROOT / "Sources" / "UI"
POLICY = UI_ROOT / "Primitives" / "GlassPolicy.swift"

failures: list[str] = []
policy = POLICY.read_text()
for required in (
    "case content",
    "case systemNavigation",
    "case regularGlassCustomControl",
    "case clearGlassMediaOverlay",
    "static let maximumCustomGlassControlsPerScene = 1",
    "func approvedGlassEffect",
):
    if required not in policy:
        failures.append(f"GlassPolicy.swift must contain {required!r}")

for path in UI_ROOT.rglob("*.swift"):
    source = path.read_text()
    relative = path.relative_to(ROOT)
    if path != POLICY and ".glassEffect(" in source:
        failures.append(f"{relative} must use approvedGlassEffect(policy:in:) instead of raw glassEffect")
    for policy_name in re.findall(r"\.approvedGlassEffect\(\.([A-Za-z]+)", source):
        if policy_name != "regularGlassCustomControl":
            failures.append(
                f"{relative} requests unsupported custom glass policy .{policy_name}; "
                "add a reviewed policy implementation before use"
            )

if failures:
    print("Glass policy check failed:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print("Glass policy: all custom glass effects are explicit, approved, and budgeted")
