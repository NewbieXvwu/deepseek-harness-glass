#!/usr/bin/env python3
"""Reject transport/wire leakage from native Feature layers.

T4.5 keeps URLSession, URLRequest, RPC envelopes and JSONValue construction inside
Core/Transport. UI features and the session projection may reference typed domain
facades and DTOs only.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = [ROOT / "glass" / "Sources" / "UI", ROOT / "glass" / "Sources" / "Core" / "Session"]
FORBIDDEN = re.compile(
    r"\b(?:DSHAPIClient|DSHClientTransport|URLRequest)\b"
    r"|JSONValue\.(?:object|array|string|number|bool|null)"
    r"|\bRPC(?:ClientRequest|ClientResponse|ServerRequest|ServerResponse|Result)\s*\(",
)

violations: list[str] = []
for source_root in SOURCES:
    for path in sorted(source_root.rglob("*.swift")):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if FORBIDDEN.search(line):
                violations.append(f"{path.relative_to(ROOT)}:{line_number}: {line.strip()}")

if violations:
    print("T4.5 feature transport boundary failed:", file=sys.stderr)
    print("\n".join(violations), file=sys.stderr)
    sys.exit(1)
print("T4.5 feature transport boundary passed: Feature/UI source uses typed domain facades only.")
