#!/usr/bin/env python3
"""Generate the reviewed rc.1 Typert Remote/Gateway contract from locked source."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any

COMMIT = "a66e4702047846cdaa10c66c9d3df3951f5ea70d"
REVISION = "official-a66e470-remote-contract-r1"
ROOT = Path(__file__).resolve().parents[2]
EXTRACTOR = Path(__file__).with_name("extract_official_remote_contract_ast.mjs")
CARRIER_SOURCES = (
    "packages/api/gateway/src/stream-protocol.ts",
    "packages/api/gateway/src/remote-error-codes.ts",
    "packages/client/connection/src/client/rpc.ts",
    "packages/session-query/session-log-export/src/index.ts",
)


def digest_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def source_digest(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise SystemExit(f"missing locked rc.1 source: {relative}")
    return digest_bytes(path.read_bytes())


def canonical_signature(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return digest_bytes(payload.encode("utf-8"))


def extract_ast_contract(root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    process = subprocess.run(
        ["node", str(EXTRACTOR), str(root)], text=True, capture_output=True, check=False,
    )
    if process.returncode != 0:
        raise SystemExit("Remote AST extraction failed:\n" + process.stderr + process.stdout)
    try:
        decoded = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit(f"Remote AST extractor emitted invalid JSON: {error}") from error

    procedures_raw = decoded.get("procedures")
    if not isinstance(procedures_raw, list):
        raise SystemExit("Remote AST extractor emitted no procedures")
    procedures: list[dict[str, Any]] = []
    for procedure in procedures_raw:
        if not isinstance(procedure, dict):
            raise SystemExit("Remote AST extractor emitted a non-object procedure")
        source_path = procedure.get("sourcePath")
        if not isinstance(source_path, str):
            raise SystemExit("Remote procedure lacks sourcePath")
        reviewed = dict(procedure)
        reviewed["sourceSHA256"] = source_digest(root, source_path)
        reviewed["contractSignatureSHA256"] = canonical_signature({
            key: reviewed[key]
            for key in ("endpoint", "mode", "parameters", "injected", "returnType")
        })
        procedures.append(reviewed)

    errors_raw = decoded.get("closedRemoteErrors")
    if not isinstance(errors_raw, list):
        raise SystemExit("Remote AST extractor emitted no closedRemoteErrors")
    errors: list[dict[str, Any]] = []
    for error in errors_raw:
        if not isinstance(error, dict):
            raise SystemExit("Remote AST extractor emitted a non-object error")
        source_path = error.get("sourcePath")
        if not isinstance(source_path, str):
            raise SystemExit("Remote error lacks sourcePath")
        reviewed_error = dict(error)
        reviewed_error["sourceSHA256"] = source_digest(root, source_path)
        errors.append(reviewed_error)

    return sorted(procedures, key=lambda item: item["endpoint"]), sorted(errors, key=lambda item: item["code"])



def carrier(root: Path) -> dict[str, Any]:
    texts = {path: (root / path).read_text(encoding="utf-8") for path in CARRIER_SOURCES}
    stream = texts["packages/api/gateway/src/stream-protocol.ts"]
    if "REMOTE_STREAM_MUX_PATH = '/api/remote.mux'" not in stream:
        raise SystemExit("rc.1 Gateway mux path drifted")
    if "REMOTE_EVENT_STREAM_ENDPOINT = '$events'" not in stream or "REMOTE_EVENT_RESULT_ENDPOINT = '$events/result'" not in stream:
        raise SystemExit("rc.1 Gateway event endpoint drifted")
    if "readonly home: string" not in stream:
        raise SystemExit("rc.1 Host ready facts no longer expose home")
    rpc = texts["packages/client/connection/src/client/rpc.ts"]
    for token in ("client-request", "server-response", "rpcId"):
        if token not in rpc:
            raise SystemExit(f"rc.1 unary carrier no longer contains {token}")
    export = texts["packages/session-query/session-log-export/src/index.ts"]
    if "SESSION_LOG_EXPORT_PATH = '/api/session.export'" not in export:
        raise SystemExit("rc.1 session export path drifted")
    if "methods: ['GET', 'HEAD']" not in export:
        raise SystemExit("rc.1 session export methods drifted")
    return {
        "unary": {
            "pathTemplate": "/api/<namespace>/<method>",
            "requestEnvelope": "client-request",
            "responseEnvelope": "server-response",
            "correlationField": "rpcId",
            "sourcePath": "packages/client/connection/src/client/rpc.ts",
        },
        "streamMux": {
            "path": "/api/remote.mux",
            "eventStreamEndpoint": "$events",
            "eventResultEndpoint": "$events/result",
            "readyHostFields": ["home"],
            "sourcePath": "packages/api/gateway/src/stream-protocol.ts",
        },
        "nonJSONRoutes": [{
            "path": "/api/session.export",
            "methods": ["GET", "HEAD"],
            "contentType": "application/zip",
            "sourcePath": "packages/session-query/session-log-export/src/index.ts",
        }],
        "sources": [
            {"path": path, "sha256": source_digest(root, path)} for path in CARRIER_SOURCES
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = args.official_root.resolve()
    procedures, errors = extract_ast_contract(root)
    manifest = {
        "schemaVersion": 1,
        "officialSourceCommit": COMMIT,
        "contractRevision": REVISION,
        "generation": "locked rc.1 Typert Remote AST and Gateway carrier manifest",
        "procedures": procedures,
        "closedRemoteErrors": errors,
        "carrier": carrier(root),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

