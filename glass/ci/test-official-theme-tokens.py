#!/usr/bin/env python3
"""Executable proof that stale structured theme catalogs are rejected."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "ci/check-official-theme-tokens.py"
CATALOG = ROOT / "Sources/Spec/Tokens/official-theme-tokens.json"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    with tempfile.TemporaryDirectory(prefix="dsh-theme-stale-catalog-") as temporary:
        mutated_catalog = Path(temporary) / "official-theme-tokens.json"
        document = json.loads(CATALOG.read_text(encoding="utf-8"))
        document["tokens"][0]["light"]["rawValue"] = "intentionally-stale-token"
        mutated_catalog.write_text(json.dumps(document), encoding="utf-8")
        result = subprocess.run([
            sys.executable, str(CHECKER),
            "--official-root", str(args.official_root),
            "--catalog", str(mutated_catalog),
        ], text=True, capture_output=True, check=False)
        if result.returncode == 0:
            raise SystemExit("stale official theme token catalog unexpectedly passed")
        if "catalog is stale" not in result.stderr and "catalog is stale" not in result.stdout:
            raise SystemExit(f"stale theme catalog failed for an unexpected reason:\n{result.stdout}\n{result.stderr}")
    print("Official theme structured provenance self-test passed.")


if __name__ == "__main__":
    main()
