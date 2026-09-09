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
    if not path.is_file():
        raise SystemExit(f"required upstream Ghost Plane contract source is missing: {path}")
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


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


def extract_ast(root: Path) -> tuple[list[dict[str, str]], list[str], dict[str, object]]:
    process = subprocess.run(
        [node_binary(root), str(AST_EXTRACTOR), str(root)],
        check=True,
        capture_output=True,
        text=True,
    )
    try:
        data = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit(f"AST ghost plane extractor emitted invalid JSON: {process.stdout}") from error
    module_loader = data.get("moduleLoader")
    if not isinstance(module_loader, dict):
        raise SystemExit("AST ghost plane extractor emitted no module-loader contract")
    return data.get("slots", []), data.get("dataSelectors", []), module_loader


def build(root: Path, source_commit: str) -> dict[str, object]:
    slots, ast_data_selectors, module_loader = extract_ast(root)
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
    selectors = sorted(required_data_selectors)

    red_slots = {
        "conversation.session",
        "conversation.session.header",
        "conversation.chat.node",
        "conversation.composer",
    }
    managed_slots = {"conversation.view"}

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
        raise SystemExit(f"unclassified official Ghost Plane slot anchor: {name}")

    reviewed_slots = []
    for slot in slots:
        name = slot["name"]
        reviewed_slots.append({
            **slot,
            "anchor": slot_anchor(name),
            "zone": "red" if name in red_slots else "managed" if name in managed_slots else "green",
        })

    expected_module_loader = {
        "bootGlobal": "__DSH_BOOT__",
        "registrationGlobal": "__ModuleLoader__",
        "registrationMethod": "load",
        "comboRouteTemplate": "/plugins/??${resources}&rev=${rev}",
        "bootBatchPhases": ["bootstrap", "application"],
        "initialURLFromBatches": True,
        "factoryRegistration": True,
    }
    if module_loader != expected_module_loader:
        raise SystemExit("official module-loader AST contract drifted from reviewed rc.1 semantics")

    route = str(module_loader["comboRouteTemplate"])
    single_resource = route.replace("${resources}", "<id>/client.js").replace("${rev}", "<rev>")
    combo_resource = route.replace("${resources}", "<id1>/client.js,<id2>/client.js").replace("${rev}", "<rev>")

    return {
        "schemaVersion": 1,
        "sourceCommit": source_commit,
        "sources": [{"path": relative, "sha256": sha256(root / relative)} for relative in SOURCE_PATHS],
        "selectors": selectors,
        "slots": sorted(reviewed_slots, key=lambda slot: slot["name"]),
        "moduleLoader": {
            "bootGlobal": module_loader["bootGlobal"],
            "registrationGlobal": module_loader["registrationGlobal"],
            "registrationMethod": module_loader["registrationMethod"],
            "singleResourcePathTemplate": single_resource,
            "comboPathTemplate": combo_resource,
            "bootBatchPhases": module_loader["bootBatchPhases"],
            "initialURLFromBatches": module_loader["initialURLFromBatches"],
            "factoryRegistration": module_loader["factoryRegistration"],
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
