#!/usr/bin/env python3
"""Compare the checked Ghost Plane slot contract with fresh upstream extraction."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "tools/spec-generation/generate_ghost_plane_contract.py"
DEFAULT_CONTRACT = ROOT / "glass/Sources/Core/Resources/official-ghost-plane-contract.json"
REQUIRED_SLOTS = {
    "conversation.session",
    "conversation.session.header",
    "conversation.chat.node",
    "conversation.chat.turnTail",
    "conversation.details.tool",
    "conversation.composer",
}
VALID_ZONES = {"red", "green", "managed"}
VALID_ANCHORS = {"conversation", "header", "hero", "chat", "composer", "details", "managed-view"}


def slots(document: object) -> list[dict[str, str]]:
    if not isinstance(document, dict):
        raise SystemExit("Ghost Plane contract root must be an object")
    rows = document.get("slots")
    if not isinstance(rows, list) or not rows:
        raise SystemExit("Ghost Plane contract has no slots")
    result: list[dict[str, str]] = []
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            raise SystemExit("Ghost Plane slot must be an object")
        projected: dict[str, str] = {}
        for field in ("name", "kind", "scope", "sourcePath", "anchor", "zone"):
            value = row.get(field)
            if not isinstance(value, str) or not value:
                raise SystemExit(f"Ghost Plane slot has invalid {field}: {row.get('name')!r}")
            projected[field] = value
        if projected["name"] in seen:
            raise SystemExit(f"duplicate Ghost Plane slot: {projected['name']}")
        seen.add(projected["name"])
        if projected["zone"] not in VALID_ZONES or projected["anchor"] not in VALID_ANCHORS:
            raise SystemExit(f"Ghost Plane slot has invalid ownership: {projected['name']}")
        result.append(projected)
    missing = REQUIRED_SLOTS - seen
    if missing:
        raise SystemExit("Ghost Plane contract lacks required slots: " + ", ".join(sorted(missing)))
    return sorted(result, key=lambda row: row["name"])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=Path)
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    args = parser.parse_args()
    checked = slots(json.loads(args.contract.read_text(encoding="utf-8")))
    with tempfile.TemporaryDirectory(prefix="dsh-ghost-plane-contract-") as temporary:
        output = Path(temporary) / "actual.json"
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--official-root", str(args.official_root), "--output", str(output)],
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise SystemExit("Ghost Plane contract generation failed:\n" + result.stderr + result.stdout)
        generated = slots(json.loads(output.read_text(encoding="utf-8")))
    if generated != checked:
        raise SystemExit("checked Ghost Plane slot ownership differs from fresh upstream extraction")
    print(f"Ghost Plane slot contract gate passed: {len(checked)} slots.")


if __name__ == "__main__":
    main()
