#!/usr/bin/env python3
"""Generate the reviewable T4.6 transport-contract baseline from locked apiproxy schemas.

The manifest is deliberately field-level and method-scoped. It is not a TypeScript
parser: the canonical evidence remains the complete schema file SHA. The explicit
field/discriminant lists document exactly which wire surface GlassCore has accepted,
so a future Host upgrade emits added/modified/removed contracts instead of silently
rewriting a golden fixture.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
from typing import Any

COMMIT = "99f6f02fecdb7dff40c3fbc9470f5907c29f74ca"
REVISION = "official-99f6f02-transport-contract-r1"

CONTRACTS: list[dict[str, Any]] = [
    {"id": "session.history", "kind": "rpc", "source": "packages/host/apiproxy/src/api/sessions.schema.ts", "symbols": ["sessionHistoryRequestSchema", "sessionHistoryValueSchema"], "requestFields": ["sessionId", "beforeSeq?", "maxMessages?"], "valueFields": ["events", "hasMore", "projections?"], "enums": []},
    {"id": "session.prompt", "kind": "rpc", "source": "packages/host/apiproxy/src/api/sessions.schema.ts", "symbols": ["sessionPromptRequestSchema", "sessionPromptValueSchema"], "requestFields": ["sessionId", "mode", "content", "clientTimeZone?"], "valueFields": ["accepted", "command?"], "enums": ["mode:queue", "mode:steer", "content.type:text", "content.type:image"]},
    {"id": "session.cancel", "kind": "rpc", "source": "packages/host/apiproxy/src/api/sessions.schema.ts", "symbols": ["sessionCancelRequestSchema", "sessionCancelValueSchema"], "requestFields": ["sessionId"], "valueFields": ["accepted"], "enums": []},
    {"id": "session.models", "kind": "rpc", "source": "packages/host/apiproxy/src/api/sessions.schema.ts", "symbols": ["sessionModelsRequestSchema", "sessionModelsValueSchema"], "requestFields": ["sessionId"], "valueFields": ["current", "routable", "groups", "failures"], "enums": []},
    {"id": "settings.describe", "kind": "rpc", "source": "packages/host/apiproxy/src/api/settings.schema.ts", "symbols": ["settingsDescribeRequestSchema", "settingsDescribeValueSchema"], "requestFields": [], "valueFields": ["writable", "hasDocument", "namespaces"], "enums": []},
    {"id": "settings.mutate", "kind": "rpc", "source": "packages/host/apiproxy/src/api/settings.schema.ts", "symbols": ["settingsMutateRequestSchema", "settingsMutateValueSchema"], "requestFields": ["ns", "ops", "expectedRevision?"], "valueFields": ["ns", "schema", "value", "base?", "user?", "applies", "secrets", "revision"], "enums": ["ops.op:set", "ops.op:unset", "applies:live", "applies:restart"]},
    {"id": "credentials.set", "kind": "rpc", "source": "packages/host/apiproxy/src/api/credentials.schema.ts", "symbols": ["credentialsSetRequestSchema", "credentialsSetValueSchema"], "requestFields": ["ref", "value"], "valueFields": [], "enums": []},
    {"id": "llm.providers", "kind": "rpc", "source": "packages/host/apiproxy/src/api/llm.schema.ts", "symbols": ["llmProvidersRequestSchema", "llmProvidersValueSchema"], "requestFields": [], "valueFields": ["providers"], "enums": []},
    {"id": "sse.mux", "kind": "sse", "source": "packages/host/apiproxy/src/api/events.schema.ts", "symbols": ["muxFrameSchema"], "requestFields": ["server-request.rpcId", "server-request.method", "server-request.payload"], "valueFields": [], "enums": ["session/event", "session/subscribed", "approval/requested", "approval/resolved", "question/requested", "question/resolved", "session/queue", "session/jobs", "session/projection", "stream/error"]},
    {"id": "sse.host", "kind": "sse", "source": "packages/host/apiproxy/src/api/events.schema.ts", "symbols": ["hostFrameSchema"], "requestFields": ["server-request.rpcId", "server-request.method", "server-request.payload"], "valueFields": [], "enums": ["host/session-added", "host/session-removed", "host/session-status", "host/agent-error", "host/workspace-changed", "host/workspace-removed", "host/workspace-order-changed", "host/archived-sessions-changed", "host/remote-event", "stream/error"]},
    {"id": "rpc.business-error", "kind": "rpc-error", "source": "packages/host/apiproxy/src/api/rpc.schema.ts", "symbols": ["rpcErrorSchema", "serverResponseSchema"], "requestFields": ["code", "message", "details"], "valueFields": [], "enums": ["bad-request", "cancelled", "session-not-found", "settings-conflict", "credential-rejected", "internal"]},
    {"id": "rpc.revision-conflict", "kind": "rpc-error", "source": "packages/host/apiproxy/src/api/rpc.schema.ts", "symbols": ["rpcErrorSchema"], "requestFields": ["code", "message", "details.ns", "details.expected", "details.actual"], "valueFields": [], "enums": ["settings-conflict"]},
]


def sha256(path: pathlib.Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    root = args.official_root
    entries: list[dict[str, Any]] = []
    for contract in CONTRACTS:
        source = root / contract["source"]
        text = source.read_text(encoding="utf-8")
        missing = [symbol for symbol in contract["symbols"] if symbol not in text]
        if missing:
            raise SystemExit(f"{contract['id']}: missing locked schema symbols {missing} in {contract['source']}")
        entry = dict(contract)
        entry["sourceSHA256"] = sha256(source)
        signature = json.dumps({key: entry[key] for key in ("id", "kind", "symbols", "requestFields", "valueFields", "enums")}, separators=(",", ":"), ensure_ascii=False)
        entry["contractSignatureSHA256"] = "sha256:" + hashlib.sha256(signature.encode()).hexdigest()
        entries.append(entry)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        "schemaVersion": 1,
        "officialSourceCommit": COMMIT,
        "contractRevision": REVISION,
        "generation": "locked official apiproxy schema contract manifest",
        "contracts": entries,
    }, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
