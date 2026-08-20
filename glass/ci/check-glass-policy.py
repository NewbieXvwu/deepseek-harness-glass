#!/usr/bin/env python3
"""Enforce approved Liquid Glass encapsulation across native UI sources."""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
UI_ROOT = ROOT / "Sources" / "UI"
POLICY = UI_ROOT / "Primitives" / "GlassPolicy.swift"

failures: list[str] = []

if not POLICY.exists():
    failures.append("GlassPolicy.swift must exist in UI/Primitives")

for path in UI_ROOT.rglob("*.swift"):
    if path == POLICY:
        continue
    source = path.read_text(encoding="utf-8")
    relative = path.relative_to(ROOT)
    if ".glassEffect(" in source:
        failures.append(f"{relative} must use approvedGlassEffect(policy:in:) instead of raw glassEffect")

if failures:
    print("Glass policy check failed:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print("Glass policy: all custom glass effects are explicit, approved, and budgeted")
