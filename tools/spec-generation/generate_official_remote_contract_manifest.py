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
REMOTE_SOURCES = (
    "packages/preset/agent-presets/src/index.ts",
    "packages/api/settings-controller/src/index.ts",
    "packages/api/settings-controller/src/credentials.ts",
    "packages/goal/goal/src/index.ts",
    "packages/llm/llm/src/index.ts",
    "packages/feedback/message-feedback/src/index.ts",
    "packages/subagent/subagent/src/index.ts",
    "packages/api/session-controller/src/index.ts",
    "packages/api/workspace-controller/src/index.ts",
)
ERROR_SCAN_ROOTS = (
    "packages/preset/agent-presets/src",
    "packages/api/settings-controller/src",
    "packages/goal/goal/src",
    "packages/llm/llm/src",
    "packages/feedback/message-feedback/src",
    "packages/subagent/subagent/src",
    "packages/api/session-controller/src",
    "packages/api/workspace-controller/src",
    "packages/core/session/src",
    "packages/workspace/workspace/src",
)
CARRIER_SOURCES = (
    "packages/api/gateway/src/stream-protocol.ts",
    "packages/api/gateway/src/remote-error-codes.ts",
    "packages/client/connection/src/client/rpc.ts",
    "packages/session-query/session-log-export/src/index.ts",
)
EXTRA_GATEWAY_ERRORS = {"gateway/method-unavailable", "gateway/service-unavailable"}


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


def extract_procedures(root: Path) -> list[dict[str, Any]]:
    process = subprocess.run(
        ["node", str(EXTRACTOR), str(root)], text=True, capture_output=True, check=False,
    )
    if process.returncode != 0:
        raise SystemExit("Remote AST extraction failed:\n" + process.stderr + process.stdout)
    try:
        decoded = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit(f"Remote AST extractor emitted invalid JSON: {error}") from error
    procedures = decoded.get("procedures")
    if not isinstance(procedures, list):
        raise SystemExit("Remote AST extractor emitted no procedures")
    result: list[dict[str, Any]] = []
    for procedure in procedures:
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
        result.append(reviewed)
    if len(result) != 51:
        raise SystemExit(f"reviewed rc.1 Remote surface expected 51 procedures, found {len(result)}")
    return sorted(result, key=lambda item: item["endpoint"])


def declared_error_details(root: Path) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    property_pattern = re.compile(r"['\"]([^'\"]+/[^'\"]+)['\"]\s*:\s*([^\n;]+(?:\{[^}]*\})?)")
    for scan_root in ERROR_SCAN_ROOTS:
        for path in sorted((root / scan_root).rglob("*.ts")):
            if path.name == "directory-picker.ts":
                continue
            text = path.read_text(encoding="utf-8")
            if "RemoteErrorDetailsMap" not in text:
                continue
            for code, details in property_pattern.findall(text):
                result[code] = {
                    "detailsType": re.sub(r"\s+", " ", details).strip(),
                    "sourcePath": path.relative_to(root).as_posix(),
                }
    protocol = root / "packages/typert/protocol/src/types.ts"
    text = protocol.read_text(encoding="utf-8")
    for code, details in property_pattern.findall(text):
        result[code] = {
            "detailsType": re.sub(r"\s+", " ", details).strip(),
            "sourcePath": protocol.relative_to(root).as_posix(),
        }
    gateway = root / "packages/api/gateway/src/remote-error-codes.ts"
    text = gateway.read_text(encoding="utf-8")
    for code, details in property_pattern.findall(text):
        if code in EXTRA_GATEWAY_ERRORS:
            result[code] = {
                "detailsType": re.sub(r"\s+", " ", details).strip(),
                "sourcePath": gateway.relative_to(root).as_posix(),
            }
    return result


def thrown_error_codes(root: Path) -> set[str]:
    pattern = re.compile(r"new\s+RemoteError\(\s*['\"]([^'\"]+)['\"]")
    result: set[str] = set()
    for scan_root in ERROR_SCAN_ROOTS:
        for path in sorted((root / scan_root).rglob("*.ts")):
            if path.name == "directory-picker.ts":
                continue
            result.update(pattern.findall(path.read_text(encoding="utf-8")))
    return result


def extract_errors(root: Path) -> list[dict[str, str]]:
    codes = thrown_error_codes(root) | EXTRA_GATEWAY_ERRORS
    declarations = declared_error_details(root)
    missing = sorted(codes - declarations.keys())
    if missing:
        raise SystemExit("Remote errors lack declared details: " + ", ".join(missing))
    if len(codes) != 38:
        raise SystemExit(f"reviewed rc.1 closed Remote error surface expected 38 codes, found {len(codes)}")
    result = []
    for code in sorted(codes):
        item = {"code": code, **declarations[code]}
        item["sourceSHA256"] = source_digest(root, item["sourcePath"])
        result.append(item)
    return result


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
    manifest = {
        "schemaVersion": 1,
        "officialSourceCommit": COMMIT,
        "contractRevision": REVISION,
        "generation": "locked rc.1 Typert Remote AST and Gateway carrier manifest",
        "procedures": extract_procedures(root),
        "closedRemoteErrors": extract_errors(root),
        "carrier": carrier(root),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
