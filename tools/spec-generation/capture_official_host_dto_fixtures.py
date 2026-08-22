#!/usr/bin/env python3
"""Capture schema-valid request/response fixtures from an isolated pinned dsh Host.

The script deliberately avoids credentials and prompt execution. Every payload is
valid under the locked apiproxy Zod source; unsupported state is represented by the
Host's closed business-error branch rather than an intentionally malformed request.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import tempfile
import uuid
from typing import Any

COMMIT = "b150a551b8d465e31e418e1b2eaf5e79bbb7d28e"
REVISION = "official-b150a55-web-ui-r1"


def result_value(response: dict[str, Any]) -> dict[str, Any] | None:
    result = response.get("result")
    if not isinstance(result, dict) or result.get("ok") is not True:
        return None
    value = result.get("value")
    return value if isinstance(value, dict) else None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    records: list[dict[str, Any]] = []

    def call(method: str, payload: dict[str, Any]) -> dict[str, Any]:
        request = {"type": "client-request", "rpcId": str(uuid.uuid4()), "method": method, "payload": payload}
        curl = subprocess.run(
            [
                "curl", "--silent", "--show-error", "--connect-timeout", "5", "--max-time", "10",
                "-X", "POST", f"{args.base_url}/api/{method}",
                "-H", "Content-Type: application/json", "-H", "Accept: application/json",
                "--data-binary", json.dumps(request),
            ],
            check=False, capture_output=True, text=True,
        )
        raw = curl.stdout.strip()
        try:
            response: dict[str, Any] | None = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            response = {"nonJSON": raw, "stderr": curl.stderr}
        records.append({"method": method, "request": request, "curlExit": curl.returncode, "response": response})
        return response if isinstance(response, dict) else {}

    # Read-only baseline methods first. The order after this mirrors the current
    # native facade's 16 Host calls and keeps destructive identifiers impossible
    # to collide with a real user environment because DSH_HOME is isolated.
    call("host.describe", {})
    call("workspace.list", {})
    call("session.list", {})
    call("settings.describe", {})

    with tempfile.TemporaryDirectory(prefix="dsh-glass-rpc-fixture-") as directory:
        workspace_path = pathlib.Path(directory) / "workspace"
        workspace_path.mkdir()
        workspace_response = call("workspace.create", {"path": str(workspace_path)})
        workspace_value = result_value(workspace_response) or {}
        workspace = workspace_value.get("workspace")
        workspace_id = workspace.get("workspaceId") if isinstance(workspace, dict) else None

        # Capture the request shape with optional fields omitted (Swift's
        # Encodable synthesis uses encodeIfPresent for these fields).
        if isinstance(workspace_id, str) and workspace_id:
            call("session.create", {"workspaceId": workspace_id})
        else:
            call("session.create", {})

    # The remaining calls use a deliberately impossible but Zod-valid identifier.
    # They must reach the official closed business-error result branch, never the
    # malformed-payload branch, and cannot mutate the temporary workspace.
    missing_session = "fixture-missing"
    missing_workspace = "fixture-missing"
    call("session.history", {"sessionId": missing_session})
    call("session.prompt", {
        "sessionId": missing_session,
        "mode": "queue",
        "content": [{"type": "text", "text": "fixture"}],
        "clientTimeZone": "UTC",
    })
    call("session.cancel", {"sessionId": missing_session})
    call("session.search", {"query": "fixture"})
    call("session.rename", {"sessionId": missing_session, "title": "fixture"})
    call("session.fork", {"sessionId": missing_session})
    call("workspace.rename", {"workspaceId": missing_workspace, "title": "fixture"})
    call("workspace.delete", {"workspaceId": missing_workspace})
    call("workspace.archiveSession", {"sessionId": missing_session})
    call("settings.mutate", {"ns": "fixture", "ops": []})

    methods = [record["method"] for record in records]
    if len(methods) != 16 or len(set(methods)) != 16:
        raise SystemExit(f"fixture capture expected 16 unique methods, got {methods}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        "schemaVersion": 1,
        "officialSourceCommit": COMMIT,
        "fixtureRevision": REVISION,
        "endpointClass": "isolated local pinned dsh web",
        "records": records,
    }, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
