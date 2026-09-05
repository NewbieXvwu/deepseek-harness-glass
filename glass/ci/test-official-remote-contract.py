#!/usr/bin/env python3
"""Negative self-tests for the rc.1 Remote contract drift gate."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "glass/ci/check-official-remote-contract.py"
BASELINE = ROOT / "glass/Sources/Spec/Fixtures/official-remote-contract-manifest.json"


def invoke(official_root: Path, manifest: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECK), "--official-root", str(official_root), "--manifest", str(manifest)],
        text=True,
        capture_output=True,
        check=False,
    )


def main() -> None:
    official_root = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(".reference/deepseek-harness")
    if not official_root.is_dir():
        raise SystemExit("pass the locked official rc.1 source root")
    baseline = invoke(official_root, BASELINE)
    if baseline.returncode != 0:
        raise SystemExit("baseline Remote contract unexpectedly failed:\n" + baseline.stdout + baseline.stderr)

    with tempfile.TemporaryDirectory(prefix="dsh-remote-contract-test-") as temporary:
        temp = Path(temporary)
        decoded = json.loads(BASELINE.read_text(encoding="utf-8"))

        legacy = temp / "legacy.json"
        legacy_doc = json.loads(json.dumps(decoded))
        legacy_doc["procedures"][0]["endpoint"] = "session.history"
        legacy.write_text(json.dumps(legacy_doc), encoding="utf-8")
        result = invoke(official_root, legacy)
        if result.returncode == 0 or "legacy APIProxy endpoint" not in result.stderr:
            raise SystemExit("legacy APIProxy endpoint unexpectedly passed")

        tampered = temp / "tampered.json"
        tampered_doc = json.loads(json.dumps(decoded))
        target = next(item for item in tampered_doc["procedures"] if item["endpoint"] == "session/follow")
        target["mode"] = "unary"
        tampered.write_text(json.dumps(tampered_doc), encoding="utf-8")
        result = invoke(official_root, tampered)
        if result.returncode == 0 or "differs from fresh rc.1" not in result.stderr:
            raise SystemExit("tampered Remote procedure unexpectedly passed")

        export_drift = temp / "export-drift.json"
        export_doc = json.loads(json.dumps(decoded))
        export_doc["carrier"]["nonJSONRoutes"][0]["methods"] = ["GET"]
        export_drift.write_text(json.dumps(export_doc), encoding="utf-8")
        result = invoke(official_root, export_drift)
        if result.returncode == 0 or "session export method/content" not in result.stderr:
            raise SystemExit("tampered non-JSON route unexpectedly passed")

        error_drift = temp / "error-drift.json"
        error_doc = json.loads(json.dumps(decoded))
        error_doc["closedRemoteErrors"] = error_doc["closedRemoteErrors"][:-1]
        error_drift.write_text(json.dumps(error_doc), encoding="utf-8")
        result = invoke(official_root, error_drift)
        if result.returncode == 0 or "38 reviewed codes" not in result.stderr:
            raise SystemExit("truncated Remote error union unexpectedly passed")

    print("Official Remote contract gate self-test passed.")


if __name__ == "__main__":
    main()
