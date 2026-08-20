#!/usr/bin/env python3
"""Generate deterministic, schema-valid T4.6 transport replay fixtures.

These are contract fixtures, not user data and not mocked protocol shapes. Every
method/path/discriminant is bound by `official-transport-contract-manifest.json`
to the locked official apiproxy schemas. Values are deliberately inert: no real
credential, user workspace, prompt execution or remote request is represented.
"""
from __future__ import annotations

import argparse
import json
import pathlib

COMMIT = "141eb6fef83422698aef7a981029e843e8161534"
REVISION = "official-141eb6f-transport-contract-r1"


def request(rpc_id: str, method: str, payload: dict) -> dict:
    return {"type": "client-request", "rpcId": rpc_id, "method": method, "payload": payload}


def success(rpc_id: str, value: dict) -> dict:
    return {"type": "server-response", "rpcId": rpc_id, "result": {"ok": True, "value": value}}


def failure(rpc_id: str, code: str, message: str, details: dict) -> dict:
    return {"type": "server-response", "rpcId": rpc_id, "result": {"ok": False, "error": {"code": code, "message": message, "details": details}}}


def server_request(rpc_id: str, method: str, payload: dict) -> dict:
    return {"type": "server-request", "rpcId": rpc_id, "method": method, "payload": payload}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    records = [
        {"contract": "session.history", "request": request("contract-history", "session.history", {"sessionId": "contract-session", "beforeSeq": 8, "maxMessages": 20}), "response": success("contract-history", {"events": [], "hasMore": False, "projections": {"asOfSeq": -1, "values": {}}})},
        {"contract": "session.prompt", "request": request("contract-prompt", "session.prompt", {"sessionId": "missing-contract-session", "mode": "queue", "content": [{"type": "text", "text": "contract fixture; never dispatched"}], "clientTimeZone": "UTC"}), "response": failure("contract-prompt", "session-not-found", "session not found", {"sessionId": "missing-contract-session"})},
        {"contract": "session.cancel", "request": request("contract-cancel", "session.cancel", {"sessionId": "contract-session"}), "response": success("contract-cancel", {"accepted": True})},
        {"contract": "session.models", "request": request("contract-models", "session.models", {"sessionId": "contract-session"}), "response": success("contract-models", {"current": {"provider": "deepseek-official", "model": "deepseek-v4-flash"}, "routable": True, "groups": [], "failures": []})},
        {"contract": "settings.describe", "request": request("contract-settings-describe", "settings.describe", {}), "response": success("contract-settings-describe", {"writable": True, "hasDocument": True, "namespaces": []})},
        {"contract": "settings.mutate", "request": request("contract-settings-mutate", "settings.mutate", {"ns": "contract", "ops": [{"op": "set", "path": ["theme"], "value": "light"}], "expectedRevision": 4}), "response": failure("contract-settings-mutate", "settings-conflict", "settings revision conflict", {"ns": "contract", "expected": 4, "actual": 5})},
        {"contract": "credentials.set", "request": request("contract-credentials-set", "credentials.set", {"ref": "DSH_GLASS_CONTRACT_TEST_TOKEN", "value": "fixture-value-not-a-secret"}), "response": success("contract-credentials-set", {})},
        {"contract": "llm.providers", "request": request("contract-llm-providers", "llm.providers", {}), "response": success("contract-llm-providers", {"providers": []})},
    ]
    sse = [
        {"contract": "sse.mux", "frame": server_request("contract-event-8", "session/event", {"type": "session/event", "sessionId": "contract-session", "event": {"type": "turn/start", "seq": 8, "time": 1, "data": {} }})},
        {"contract": "sse.mux", "frame": server_request("contract-projection-9", "session/projection", {"type": "session/projection", "sessionId": "contract-session", "key": "title", "value": "fixture", "seq": 9})},
        {"contract": "sse.host", "frame": server_request("contract-host-status", "host/session-status", {"type": "host/session-status", "sessionId": "contract-session", "running": False})},
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        "schemaVersion": 1,
        "officialSourceCommit": COMMIT,
        "contractRevision": REVISION,
        "fixtureRevision": "official-141eb6f-transport-fixtures-r1",
        "fixtureClass": "schema-valid deterministic transport replay",
        "secretPolicy": "All credential-like values are literal non-secret fixture strings; no user configuration or Host credentials are captured.",
        "records": records,
        "sseFrames": sse,
    }, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
