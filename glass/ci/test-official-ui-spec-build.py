#!/usr/bin/env python3
"""Executable proof that an OfficialUISpec/Host catalog mismatch is rejected."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "ci/check-official-ui-spec-build.py"
CATALOG = ROOT / "Sources/Spec/SupportedHostBuilds.json"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    with tempfile.TemporaryDirectory(prefix="dsh-spec-host-mismatch-") as temporary:
        mutated_catalog = Path(temporary) / "SupportedHostBuilds.json"
        document = json.loads(CATALOG.read_text(encoding="utf-8"))
        document["builds"][0]["uiSpecRevision"] = "intentionally-incompatible-ui-spec"
        mutated_catalog.write_text(json.dumps(document), encoding="utf-8")
        result = subprocess.run([
            sys.executable, str(CHECKER),
            "--official-root", str(args.official_root),
            "--host-catalog", str(mutated_catalog),
        ], text=True, capture_output=True, check=False)
        if result.returncode == 0:
            raise SystemExit("OfficialUISpec/Host mismatch unexpectedly passed")
        if "does not match Host catalog" not in result.stderr and "does not match Host catalog" not in result.stdout:
            raise SystemExit(f"mismatch failed for an unexpected reason:\n{result.stdout}\n{result.stderr}")
    print("OfficialUISpec/Host mismatch self-test passed.")


if __name__ == "__main__":
    main()
