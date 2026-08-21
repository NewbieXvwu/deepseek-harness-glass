#!/usr/bin/env python3
"""Generate the reviewed Ghost Plane structural contract from locked upstream source."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

SOURCE_PATHS = (
    "packages/client/ui-conversation/src/client/contract/slots.ts",
    "packages/client/ui-conversation/src/client/skeleton/ConversationRoot.tsx",
    "packages/client/ui-conversation/src/client/chat/ChatView.tsx",
    "packages/client/ui-conversation/src/client/chat/ChatNodeSeat.tsx",
    "packages/client/ui-conversation/src/client/chat/AssistantMarkdown.tsx",
    "packages/client/modules/src/client/manifest.ts",
)
SLOT_RE = re.compile(r"^\s*'(?P<name>[A-Za-z][A-Za-z0-9.-]+)':\s*\{\s*kind:\s*'(?P<kind>[a-z]+)'\s*;?\s*scope:\s*'(?P<scope>[a-z-]+)'", re.MULTILINE)
DATA_RE = re.compile(r"data-[a-z0-9-]+")


def sha256(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def read_source(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise SystemExit(f"required upstream Ghost Plane contract source is missing: {relative}")
    return path.read_text(encoding="utf-8")


def build(root: Path, source_commit: str) -> dict[str, object]:
    sources = {relative: read_source(root, relative) for relative in SOURCE_PATHS}
    slot_source = sources[SOURCE_PATHS[0]]
    slots = [
        {"name": match.group("name"), "kind": match.group("kind"), "scope": match.group("scope")}
        for match in SLOT_RE.finditer(slot_source)
    ]
    if not slots:
        raise SystemExit("official SlotMap extraction produced no slots")
    required_slot_names = {
        "conversation.session", "conversation.session.header", "conversation.chat.node",
        "conversation.chat.turnTail", "conversation.details.tool", "conversation.composer",
    }
    actual_slot_names = {slot["name"] for slot in slots}
    missing_slots = required_slot_names - actual_slot_names
    if missing_slots:
        raise SystemExit("official SlotMap lacks required Ghost Plane seats: " + ", ".join(sorted(missing_slots)))

    dom_sources = "\n".join(sources[path] for path in SOURCE_PATHS[1:5])
    data_selectors = {f"[{attribute}]" for attribute in DATA_RE.findall(dom_sources)}
    required_data_selectors = {
        "[data-conversation-scroll]", "[data-chat-flow]", "[data-chat-anchor-key]",
        "[data-chat-flow-key]", "[data-streaming]", "[data-composer-seat]",
    }
    missing_selectors = required_data_selectors - data_selectors
    if missing_selectors:
        raise SystemExit("official conversation DOM lacks required anchors: " + ", ".join(sorted(missing_selectors)))
    selectors = sorted(data_selectors | {f"[data-slot={name}]" for name in required_slot_names} | {"[data-slot=tool.call.toolview]"})

    module_source = sources[SOURCE_PATHS[-1]]
    required_module_terms = ("__DSH_BOOT__", "__ModuleLoader__", "/plugins/<id>/client.js?rev=<rev>", "factory")
    if any(term not in module_source for term in required_module_terms):
        raise SystemExit("official module manifest source no longer supplies the expected loader wire contract")

    return {
        "schemaVersion": 1,
        "sourceCommit": source_commit,
        "sources": [{"path": relative, "sha256": sha256(root / relative)} for relative in SOURCE_PATHS],
        "selectors": selectors,
        "slots": sorted(slots, key=lambda slot: slot["name"]),
        "moduleLoader": {
            "bootGlobal": "__DSH_BOOT__",
            "registrationGlobal": "__ModuleLoader__",
            "registrationMethod": "load",
            "bundlePathTemplate": "/plugins/<id>/client.js?rev=<rev>",
            "factoryRegistration": True,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=Path)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.source_commit):
        raise SystemExit("source commit must be a 40-character lowercase SHA")
    result = build(args.official_root, args.source_commit)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
