#!/usr/bin/env python3
"""Generate the Ghost Plane slot contract from upstream client source."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

AST_EXTRACTOR = Path(__file__).with_name("extract_ghost_plane_ast.mjs")
REQUIRED_SLOTS = {
    "conversation.session",
    "conversation.session.header",
    "conversation.chat.node",
    "conversation.chat.turnTail",
    "conversation.details.tool",
    "conversation.composer",
}
REQUIRED_SELECTORS = {
    "[data-conversation-scroll]",
    "[data-chat-flow]",
    "[data-chat-anchor-key]",
    "[data-chat-flow-key]",
    "[data-chat-flow-kind]",
    "[data-streaming]",
    "[data-phase]",
    "[data-composer-seat]",
}


def node_binary(root: Path | None = None) -> str:
    configured = os.environ.get("DSH_REFERENCE_NODE") or os.environ.get("NODE")
    if configured:
        return configured
    if root is not None:
        marker = root / ".reference-node-path"
        if marker.is_file():
            candidate = Path(marker.read_text(encoding="utf-8").strip()) / "bin/node"
            if candidate.is_file():
                return str(candidate)
    return "node"


def extract_ast(root: Path) -> tuple[list[dict[str, str]], list[str]]:
    process = subprocess.run(
        [node_binary(root), str(AST_EXTRACTOR), str(root)],
        check=True,
        capture_output=True,
        text=True,
    )
    try:
        data = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit(f"Ghost Plane AST extractor emitted invalid JSON: {process.stdout}") from error
    slots = data.get("slots")
    selectors = data.get("dataSelectors")
    if not isinstance(slots, list) or not slots:
        raise SystemExit("upstream SlotMap extraction produced no slots")
    if not isinstance(selectors, list):
        raise SystemExit("upstream Ghost Plane AST extraction produced no DOM selectors")
    return slots, selectors


def slot_anchor(name: str) -> str:
    if name == "conversation.session":
        return "conversation"
    if name.startswith("conversation.session.header"):
        return "header"
    if name.startswith("conversation.hero."):
        return "hero"
    if name.startswith("conversation.chat.") or name == "conversation.message.images":
        return "chat"
    if name.startswith("conversation.composer") or name.startswith("conversation.input."):
        return "composer"
    if name == "conversation.details.tool":
        return "details"
    if name == "conversation.view":
        return "managed-view"
    raise SystemExit(f"unclassified Ghost Plane slot anchor: {name}")


def build(root: Path) -> dict[str, object]:
    slots, selectors = extract_ast(root)
    names = {slot.get("name") for slot in slots if isinstance(slot, dict)}
    missing_slots = REQUIRED_SLOTS - names
    if missing_slots:
        raise SystemExit("upstream SlotMap lacks required Ghost Plane seats: " + ", ".join(sorted(missing_slots)))
    missing_selectors = REQUIRED_SELECTORS - set(selectors)
    if missing_selectors:
        raise SystemExit("upstream conversation DOM lacks required anchors: " + ", ".join(sorted(missing_selectors)))

    red_slots = {
        "conversation.session",
        "conversation.session.header",
        "conversation.chat.node",
        "conversation.composer",
    }
    managed_slots = {"conversation.view"}
    reviewed_slots: list[dict[str, str]] = []
    for slot in slots:
        if not isinstance(slot, dict):
            raise SystemExit("upstream SlotMap contains a malformed entry")
        name = slot.get("name")
        if not isinstance(name, str):
            raise SystemExit("upstream SlotMap entry has no name")
        reviewed_slots.append({
            **slot,
            "anchor": slot_anchor(name),
            "zone": "red" if name in red_slots else "managed" if name in managed_slots else "green",
        })
    return {"schemaVersion": 1, "slots": sorted(reviewed_slots, key=lambda slot: slot["name"])}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = build(args.official_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
