#!/usr/bin/env python3
"""Generate the auditable source manifest for hand-maintained Swift RPC DTOs.

The locked official Zod schemas remain the authority. Swift DTOs are deliberately
hand-maintained in this first native release, but every supported facade method
must be linked to a schema file, source SHA-256 and fixture revision.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

COMMIT = "528c682e061696f5a160f363f236ecbf53cbd006"
FIXTURE_REVISION = "official-528c682e-web-ui-r1"
SCHEMA_ROOT = Path("packages/host/apiproxy/src/api")
METHODS = [
    ("host.describe", "HostDescribeResponse", "rpc.schema.ts", "hostDescribe"),
    ("session.list", "SessionListResponse", "sessions.schema.ts", "sessionList"),
    ("session.history", "SessionHistoryRequest/SessionHistoryResponse", "sessions.schema.ts", "sessionHistory"),
    ("session.prompt", "SessionPromptRequest/SessionPromptResponse", "sessions.schema.ts", "sessionPrompt"),
    ("session.cancel", "SessionCancelRequest/SessionCancelResponse", "sessions.schema.ts", "sessionCancel"),
    ("session.create", "SessionCreateRequest/SessionCreateResponse", "sessions.schema.ts", "sessionCreate"),
    ("session.search", "SessionSearchRequest/SessionSearchResponse", "sessions.schema.ts", "sessionSearch"),
    ("session.rename", "SessionRenameRequest/SessionRenameResponse", "sessions.schema.ts", "sessionRename"),
    ("session.fork", "SessionForkRequest/SessionForkResponse", "sessions.schema.ts", "sessionFork"),
    ("workspace.list", "WorkspaceListResponse", "workspace.schema.ts", "workspaceList"),
    ("workspace.create", "WorkspaceCreateRequest/WorkspaceCreateResponse", "workspace.schema.ts", "workspaceCreate"),
    ("workspace.rename", "WorkspaceRenameRequest/WorkspaceRenameResponse", "workspace.schema.ts", "workspaceRename"),
    ("workspace.delete", "WorkspaceDeleteRequest/WorkspaceDeleteResponse", "workspace.schema.ts", "workspaceDelete"),
    ("workspace.archiveSession", "WorkspaceArchiveSessionRequest/WorkspaceArchiveSessionResponse", "workspace.schema.ts", "workspaceArchiveSession"),
    ("settings.describe", "SettingsDescribeResponse", "settings.schema.ts", "settingsDescribe"),
    ("settings.mutate", "SettingsMutateRequest/SettingsNamespaceDTO", "settings.schema.ts", "settingsMutate"),
]


def sha(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    records = []
    for method, dto, filename, facade in METHODS:
        rel = SCHEMA_ROOT / filename
        source = args.official_root / rel
        if not source.is_file():
            raise SystemExit(f"missing locked official schema: {source}")
        records.append({
            "method": method,
            "swiftDTO": dto,
            "facade": facade,
            "sourcePath": rel.as_posix(),
            "sourceSHA256": sha(source.read_bytes()),
            "fixtureRevision": FIXTURE_REVISION,
        })
    payload = {
        "schemaVersion": 1,
        "officialSourceCommit": COMMIT,
        "fixtureRevision": FIXTURE_REVISION,
        "generation": "hand-maintained Swift DTO source manifest",
        "methods": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
