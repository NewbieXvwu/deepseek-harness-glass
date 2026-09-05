#!/usr/bin/env python3
"""Generate the reviewed Ghost Plane structural contract from locked upstream source."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

SOURCE_PATHS = (
    "packages/client/ui-conversation/src/client/contract/slots.ts",
    "packages/client/ui-chat/src/client/contract/slots.ts",
    "packages/client/ui-conversation/src/client/skeleton/ConversationRoot.tsx",
    "packages/client/ui-chat/src/client/chat/ChatView.tsx",
    "packages/client/ui-chat/src/client/chat/ChatNodeSeat.tsx",
    "packages/client/ui-chat/src/client/chat/AssistantMarkdown.tsx",
    "packages/client/modules/src/client/manifest.ts",
    "packages/client/modules/src/index.ts",
)
AST_EXTRACTOR = Path(__file__).with_name("extract_ghost_plane_ast.mjs")


def sha256(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def read_source(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise SystemExit(f"required upstream Ghost Plane contract source is missing: {relative}")
    return path.read_text(encoding="utf-8")


def node_binary() -> str:
    configured = os.environ.get("DSH_REFERENCE_NODE") or os.environ.get("NODE")
    if configured:
        return configured
    marker = Path("/home/ubuntu/reference/deepseek-harness/.reference-node-path")
    if marker.is_file():
        return str(Path(marker.read_text(encoding="utf-8").strip()) / "bin/node")
    return "node"


def extract_ast(root: Path) -> tuple[list[dict[str, str]], list[str]]:
    process = subprocess.run(
        [node_binary(), str(AST_EXTRACTOR), str(root)],
        check=True,
        capture_output=True,
        text=True,
    )
    try:
        data = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit(f"AST ghost plane extractor emitted invalid JSON: {process.stdout}") from error
    return data.get("slots", []), data.get("dataSelectors", [])


def build(root: Path, source_commit: str) -> dict[str, object]:
    sources = {relative: read_source(root, relative) for relative in SOURCE_PATHS}
    slots, ast_data_selectors = extract_ast(root)
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

    data_selectors = set(ast_data_selectors)
    required_data_selectors = {
        "[data-conversation-scroll]", "[data-chat-flow]", "[data-chat-anchor-key]",
        "[data-chat-flow-key]", "[data-chat-flow-kind]", "[data-streaming]",
        "[data-phase]", "[data-composer-seat]",
    }
    missing_selectors = required_data_selectors - data_selectors
    if missing_selectors:
        raise SystemExit("official conversation DOM lacks required anchors: " + ", ".join(sorted(missing_selectors)))
    selectors = sorted(required_data_selectors | {f"[data-slot={name}]" for name in required_slot_names} | {"[data-slot=tool.call.toolview]"})

    module_manifest = sources["packages/client/modules/src/client/manifest.ts"]
    module_host = sources["packages/client/modules/src/index.ts"]
    if any(term not in module_manifest for term in ("__DSH_BOOT__", "__ModuleLoader__", "factory", "batches", "initialUrl")):
        raise SystemExit("official module manifest source no longer supplies the rc.1 loader wire contract")
    if "return `/plugins/??${resources}&rev=${rev}`" not in module_host:
        raise SystemExit("official module host no longer supplies the rc.1 combo bundle route")

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
            "singleResourcePathTemplate": "/plugins/??<id>/client.js&rev=<rev>",
            "comboPathTemplate": "/plugins/??<id1>/client.js,<id2>/client.js&rev=<rev>",
            "bootBatchPhases": ["bootstrap", "application"],
            "initialURLFromBatches": True,
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
