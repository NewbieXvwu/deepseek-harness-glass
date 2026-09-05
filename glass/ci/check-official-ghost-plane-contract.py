#!/usr/bin/env python3
"""Fail when the locked upstream Ghost Plane structural contract drifts."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "tools/spec-generation/generate_ghost_plane_contract.py"
DEFAULT_CONTRACT = ROOT / "glass/Sources/Core/Resources/official-ghost-plane-contract.json"
EXPECTED_TOP_LEVEL = {"schemaVersion", "sourceCommit", "sources", "selectors", "slots", "moduleLoader"}
REQUIRED_SELECTORS = {
    "[data-conversation-scroll]", "[data-chat-flow]", "[data-chat-anchor-key]", "[data-chat-flow-key]",
    "[data-chat-flow-kind]", "[data-streaming]", "[data-phase]", "[data-composer-seat]",
}
REQUIRED_SLOTS = {
    "conversation.session", "conversation.session.header", "conversation.chat.node",
    "conversation.chat.turnTail", "conversation.details.tool", "conversation.composer",
}


def load_contract(path: Path) -> dict[str, object]:
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Ghost Plane contract fixture is unreadable: {exc}") from exc
    if not isinstance(decoded, dict) or set(decoded) != EXPECTED_TOP_LEVEL:
        raise SystemExit("Ghost Plane contract fixture has an invalid top-level schema")
    if decoded.get("schemaVersion") != 1:
        raise SystemExit("Ghost Plane contract fixture has an unsupported schema version")
    if not isinstance(decoded.get("sourceCommit"), str) or len(decoded["sourceCommit"]) != 40:
        raise SystemExit("Ghost Plane contract fixture has an invalid source commit")
    selectors = decoded.get("selectors")
    if not isinstance(selectors, list) or not REQUIRED_SELECTORS.issubset(set(selectors)):
        raise SystemExit("Ghost Plane contract fixture lacks required rc.1 DOM selectors")
    slots = decoded.get("slots")
    if not isinstance(slots, list) or not REQUIRED_SLOTS.issubset({item.get("name") for item in slots if isinstance(item, dict)}):
        raise SystemExit("Ghost Plane contract fixture lacks required official SlotMap seats")
    valid_zones = {"red", "green", "managed"}
    valid_anchors = {"conversation", "header", "hero", "chat", "composer", "details", "managed-view"}
    for item in slots:
        if not isinstance(item, dict):
            raise SystemExit("Ghost Plane contract fixture has a malformed slot entry")
        if not isinstance(item.get("sourcePath"), str) or not item["sourcePath"].startswith("packages/client/"):
            raise SystemExit(f"Ghost Plane slot lacks rc.1 source path: {item.get('name')}")
        if item.get("zone") not in valid_zones or item.get("anchor") not in valid_anchors:
            raise SystemExit(f"Ghost Plane slot lacks reviewed ownership admission: {item.get('name')}")
    if any(item.get("name") == "tool.call.toolview" for item in slots):
        raise SystemExit("legacy tool.call.toolview must not survive the rc.1 SlotMap")
    loader = decoded.get("moduleLoader")
    if loader != {
        "bootGlobal": "__DSH_BOOT__", "registrationGlobal": "__ModuleLoader__",
        "registrationMethod": "load",
        "singleResourcePathTemplate": "/plugins/??<id>/client.js&rev=<rev>",
        "comboPathTemplate": "/plugins/??<id1>/client.js,<id2>/client.js&rev=<rev>",
        "bootBatchPhases": ["bootstrap", "application"],
        "initialURLFromBatches": True,
        "factoryRegistration": True,
    }:
        raise SystemExit("Ghost Plane contract fixture has an unexpected ModuleLoader wire contract")
    return decoded


def generate(official_root: Path, source_commit: str) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="dsh-ghost-plane-contract-") as temporary:
        output = Path(temporary) / "actual.json"
        command = [
            sys.executable, str(GENERATOR), "--official-root", str(official_root),
            "--source-commit", source_commit, "--output", str(output),
        ]
        result = subprocess.run(command, text=True, capture_output=True, check=False)
        if result.returncode != 0:
            raise SystemExit("official Ghost Plane contract generation failed:\n" + result.stderr + result.stdout)
        return load_contract(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=Path)
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    args = parser.parse_args()
    expected = load_contract(args.contract)
    actual = generate(args.official_root, expected["sourceCommit"])
    if actual != expected:
        raise SystemExit(
            "official Ghost Plane contract drifted; regenerate and review "
            "glass/Sources/Core/Resources/official-ghost-plane-contract.json"
        )
    print(f"Official Ghost Plane contract gate passed: {len(actual['selectors'])} selectors, {len(actual['slots'])} slots.")


if __name__ == "__main__":
    main()
