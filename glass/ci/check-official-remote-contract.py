#!/usr/bin/env python3
"""Reject drift from the locked rc.1 Typert Remote and Gateway contract."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "tools/spec-generation/generate_official_remote_contract_manifest.py"
DEFAULT_MANIFEST = ROOT / "glass/Sources/Spec/Fixtures/official-remote-contract-manifest.json"
COMMIT = "a66e4702047846cdaa10c66c9d3df3951f5ea70d"
REVISION = "official-a66e470-remote-contract-r1"
FORBIDDEN_LEGACY = {"session.history", "session.models", "events.mux", "events.host", "session/history", "session/models", "events/mux", "events/host"}
REQUIRED_NAMESPACES = {
    "session", "workspace", "settings", "credentials", "llm", "subagents",
    "messageFeedback", "goals", "agentPresets",
}
REQUIRED_CARRIER = {
    "mux": "/api/remote.mux",
    "events": "$events",
    "eventResult": "$events/result",
    "download": "/api/session.export",
}


def fail(message: str) -> None:
    raise SystemExit(f"official Remote contract check failed: {message}")


def official_head(root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.STDOUT,
        ).strip()
    except subprocess.CalledProcessError as error:
        fail(f"cannot resolve official source commit: {error.output.strip()}")


def load(path: Path) -> dict[str, Any]:
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read manifest {path}: {error}")
    if not isinstance(decoded, dict):
        fail("manifest root must be an object")
    if decoded.get("schemaVersion") != 1:
        fail("unexpected schemaVersion")
    if decoded.get("officialSourceCommit") != COMMIT:
        fail("officialSourceCommit does not match rc.1 lock")
    if decoded.get("contractRevision") != REVISION:
        fail("contractRevision does not match reviewed rc.1 revision")
    return decoded


def validate_shape(manifest: dict[str, Any]) -> None:
    procedures = manifest.get("procedures")
    if not isinstance(procedures, list) or len(procedures) != 51:
        fail("procedures must contain exactly the 51 reviewed rc.1 endpoints")
    endpoints: list[str] = []
    for procedure in procedures:
        if not isinstance(procedure, dict) or not isinstance(procedure.get("endpoint"), str):
            fail("procedure entry lacks endpoint")
        endpoint = procedure["endpoint"]
        endpoints.append(endpoint)
        if procedure.get("mode") not in {"unary", "stream"}:
            fail(f"{endpoint}: invalid invocation mode")
        if not isinstance(procedure.get("parameters"), list) or not isinstance(procedure.get("injected"), list):
            fail(f"{endpoint}: parameters/injected must be arrays")
        if not isinstance(procedure.get("returnType"), str) or not procedure["returnType"]:
            fail(f"{endpoint}: missing returnType")
        if not isinstance(procedure.get("contractSignatureSHA256"), str) or not procedure["contractSignatureSHA256"].startswith("sha256:"):
            fail(f"{endpoint}: missing signature")
        if not isinstance(procedure.get("sourceSHA256"), str) or not procedure["sourceSHA256"].startswith("sha256:"):
            fail(f"{endpoint}: missing source hash")
    if len(endpoints) != len(set(endpoints)):
        fail("duplicate Remote endpoint")
    if set(endpoints) & FORBIDDEN_LEGACY:
        fail("legacy APIProxy endpoint is present")
    namespaces = {endpoint.split("/", 1)[0] for endpoint in endpoints if "/" in endpoint}
    missing_namespaces = REQUIRED_NAMESPACES - namespaces
    if missing_namespaces:
        fail("missing required Remote namespaces: " + ", ".join(sorted(missing_namespaces)))
    if "settings/update" in endpoints or "settings/replace" in endpoints:
        fail("unreviewed settings whole-section mutation escaped into the Glass contract")

    errors = manifest.get("closedRemoteErrors")
    if not isinstance(errors, list) or len(errors) != 38:
        fail("closedRemoteErrors must contain exactly the 38 reviewed codes")
    codes = [entry.get("code") for entry in errors if isinstance(entry, dict)]
    if len(codes) != len(errors) or not all(isinstance(code, str) for code in codes) or len(codes) != len(set(codes)):
        fail("closedRemoteErrors must contain unique string codes")
    for universal in ("gateway/bad-request", "gateway/cancelled", "gateway/internal", "gateway/method-unavailable", "gateway/service-unavailable"):
        if universal not in codes:
            fail(f"missing reviewed Gateway Remote error {universal}")

    carrier = manifest.get("carrier")
    if not isinstance(carrier, dict):
        fail("carrier must be an object")
    unary = carrier.get("unary")
    stream = carrier.get("streamMux")
    routes = carrier.get("nonJSONRoutes")
    if not isinstance(unary, dict) or unary.get("pathTemplate") != "/api/<namespace>/<method>":
        fail("unary /api namespace path contract drifted")
    if unary.get("requestEnvelope") != "client-request" or unary.get("responseEnvelope") != "server-response" or unary.get("correlationField") != "rpcId":
        fail("unary Connection envelope contract drifted")
    if not isinstance(stream, dict):
        fail("streamMux must be an object")
    if stream.get("path") != REQUIRED_CARRIER["mux"] or stream.get("eventStreamEndpoint") != REQUIRED_CARRIER["events"] or stream.get("eventResultEndpoint") != REQUIRED_CARRIER["eventResult"]:
        fail("Gateway Remote mux/event endpoints drifted")
    if stream.get("readyHostFields") != ["home"]:
        fail("Host ready facts drifted")
    if not isinstance(routes, list) or len(routes) != 1 or routes[0].get("path") != REQUIRED_CARRIER["download"]:
        fail("non-JSON session export route drifted")
    if routes[0].get("methods") != ["GET", "HEAD"] or routes[0].get("contentType") != "application/zip":
        fail("session export method/content contract drifted")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=Path)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    official_root = args.official_root.resolve()
    if official_head(official_root) != COMMIT:
        fail(f"official root must be locked at {COMMIT}")
    baseline = load(args.manifest.resolve())
    validate_shape(baseline)

    with tempfile.TemporaryDirectory(prefix="dsh-remote-contract-") as temporary:
        candidate_path = Path(temporary) / "candidate.json"
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--official-root", str(official_root), "--output", str(candidate_path)],
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            fail("fresh rc.1 generation failed:\n" + result.stderr + result.stdout)
        candidate = load(candidate_path)
        validate_shape(candidate)
    if candidate != baseline:
        fail("checked-in manifest differs from fresh rc.1 AST/carrier generation")
    print(
        f"official Remote contract OK: {len(baseline['procedures'])} procedures, "
        f"{len(baseline['closedRemoteErrors'])} closed errors at {COMMIT[:12]}"
    )


if __name__ == "__main__":
    main()
