#!/usr/bin/env python3
"""Enforce system sidebar and inspector structural materials without custom NSVisualEffectView hacks."""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
STRUCTURAL_ROOTS = [ROOT / "Sources/UI/Shell", ROOT / "Sources/UI/Sidebar", ROOT / "Sources/UI/Conversation"]

failures: list[str] = []

for source_root in STRUCTURAL_ROOTS:
    if not source_root.exists():
        continue
    for path in source_root.rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        if "NSVisualEffectView" in source:
            failures.append(f"{path.relative_to(ROOT)} must rely on system NSSplitView materials rather than ad-hoc NSVisualEffectView")

if failures:
    print("Native structural material policy failed:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print("Native structural material policy: system sidebar/inspector material only")
