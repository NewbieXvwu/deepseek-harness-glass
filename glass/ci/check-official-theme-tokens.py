#!/usr/bin/env python3
"""Compare checked theme token semantics with a fresh upstream CSS extraction."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ROOT.parent
CATALOG = ROOT / "Sources/Spec/Tokens/official-theme-tokens.json"
GENERATOR = REPOSITORY_ROOT / "tools/spec-generation/generate_official_theme_tokens.py"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    return parser.parse_args()


def token_semantics(document: dict[str, Any]) -> list[dict[str, Any]]:
    tokens = document.get("tokens")
    if not isinstance(tokens, list) or not tokens:
        raise SystemExit("official theme catalog has no tokens")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for token in tokens:
        if not isinstance(token, dict):
            raise SystemExit("official theme token must be an object")
        name = token.get("cssName")
        if not isinstance(name, str) or not name.startswith("--dsw-") or name in seen:
            raise SystemExit(f"invalid or duplicate official theme token {name!r}")
        seen.add(name)
        schemes: dict[str, Any] = {}
        for scheme in ("light", "dark"):
            value = token.get(scheme)
            if not isinstance(value, dict):
                raise SystemExit(f"token {name} has no {scheme} value")
            rgba = value.get("resolvedRGBA")
            if rgba is not None and not isinstance(rgba, dict):
                raise SystemExit(f"token {name} has invalid {scheme} RGBA")
            schemes[scheme] = {
                "rawValue": value.get("rawValue"),
                "resolvedValue": value.get("resolvedValue"),
                "resolvedRGBA": rgba,
            }
        result.append({"cssName": name, **schemes})
    return result


def main() -> None:
    args = arguments()
    checked = json.loads(args.catalog.read_text(encoding="utf-8"))
    checked_tokens = token_semantics(checked)

    with tempfile.TemporaryDirectory(prefix="dsh-theme-tokens-") as temporary:
        temporary_root = Path(temporary)
        generated_json = temporary_root / "official-theme-tokens.json"
        generated_swift = temporary_root / "OfficialThemeCatalog.swift"
        subprocess.run([
            sys.executable,
            str(GENERATOR),
            "--official-root", str(args.official_root),
            "--json-output", str(generated_json),
            "--swift-output", str(generated_swift),
        ], check=True)
        generated = json.loads(generated_json.read_text(encoding="utf-8"))
        generated_tokens = token_semantics(generated)

    if checked_tokens != generated_tokens:
        raise SystemExit("official theme token semantics differ from fresh upstream CSS extraction")
    print(f"Official theme token gate passed: {len(checked_tokens)} CSS tokens match fresh upstream extraction.")


if __name__ == "__main__":
    main()
