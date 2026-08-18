#!/usr/bin/env python3
"""Reject a Swift RPC DTO manifest that drifts from the locked official schemas."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

COMMIT = "99f6f02fecdb7dff40c3fbc9470f5907c29f74ca"
REVISION = "official-99f6f02-web-ui-r1"
EXPECTED_METHODS = {
    "host.describe", "session.list", "session.history", "session.prompt", "session.cancel", "session.create", "session.search", "session.rename", "session.fork",
    "workspace.list", "workspace.create", "workspace.rename", "workspace.delete", "workspace.archiveSession",
    "settings.describe", "settings.mutate",
}
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GENERATOR = REPOSITORY_ROOT / "tools/spec-generation/generate_official_rpc_dto_manifest.py"
DEFAULT_MANIFEST = REPOSITORY_ROOT / "glass/Sources/Spec/Fixtures/official-rpc-dto-manifest.json"


def fail(message: str) -> None:
    raise SystemExit(f"official RPC DTO manifest check failed: {message}")


def official_head(root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"], text=True, stderr=subprocess.STDOUT
        ).strip()
    except subprocess.CalledProcessError as error:
        fail(f"cannot resolve official source commit: {error.output.strip()}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=Path)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    official_root = args.official_root.resolve()
    manifest_path = args.manifest.resolve()
    if not GENERATOR.is_file():
        fail(f"missing generator: {GENERATOR}")
    if not manifest_path.is_file():
        fail(f"missing manifest: {manifest_path}")
    if official_head(official_root) != COMMIT:
        fail(f"official root must be locked at {COMMIT}")

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"invalid JSON: {error}")
    if manifest.get("schemaVersion") != 1:
        fail("unexpected schemaVersion")
    if manifest.get("officialSourceCommit") != COMMIT:
        fail("officialSourceCommit does not match locked commit")
    if manifest.get("fixtureRevision") != REVISION:
        fail("fixtureRevision does not match DTO fixture revision")
    methods = manifest.get("methods")
    if not isinstance(methods, list) or {item.get("method") for item in methods if isinstance(item, dict)} != EXPECTED_METHODS:
        fail("manifest must contain exactly the 16 supported facade methods")
    if len(methods) != len(EXPECTED_METHODS):
        fail("manifest contains duplicate methods")

    with tempfile.TemporaryDirectory(prefix="official-rpc-dto-manifest-") as directory:
        generated = Path(directory) / "manifest.json"
        subprocess.run(
            [sys.executable, str(GENERATOR), "--official-root", str(official_root), "--output", str(generated)],
            check=True,
        )
        expected = json.loads(generated.read_text(encoding="utf-8"))
    if manifest != expected:
        fail("checked-in manifest differs from a fresh schema-SHA generation")
    print(f"official RPC DTO manifest OK: {len(methods)} methods at {COMMIT[:12]}")


if __name__ == "__main__":
    main()
