#!/usr/bin/env python3
"""Validate reproducible --dsw-* theme token extraction from locked upstream CSS."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ROOT.parent
CATALOG = ROOT / "Sources/Spec/Tokens/official-theme-tokens.json"
SWIFT = ROOT / "Sources/Spec/OfficialThemeCatalog.swift"
SPEC_BUILD = ROOT / "Sources/Spec/OfficialUISpec/official-ui-spec-build.json"
GENERATOR = REPOSITORY_ROOT / "tools/spec-generation/generate_official_theme_tokens.py"
EXPECTED_COMMIT = "528c682e061696f5a160f363f236ecbf53cbd006"
EXPECTED_SOURCE = "packages/client/ui-theme/src/styles/design-platform.css"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    document = json.loads(CATALOG.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != 1 or document.get("sourceCommit") != EXPECTED_COMMIT:
        raise SystemExit("official theme catalog has an invalid schema or source commit")
    revision = document.get("themeRevision")
    source_input_revision = document.get("sourceInputRevision")
    if not isinstance(revision, str) or not revision.startswith("sha256:") or len(revision) != 71:
        raise SystemExit("official theme catalog must carry a SHA-256 themeRevision")
    if not isinstance(source_input_revision, str) or not source_input_revision.startswith("sha256:") or len(source_input_revision) != 71:
        raise SystemExit("official theme catalog must carry a SHA-256 sourceInputRevision")
    spec = json.loads(SPEC_BUILD.read_text(encoding="utf-8"))
    if spec.get("tokenRevision") != source_input_revision:
        raise SystemExit("official theme source-input revision does not match OfficialUISpec tokenRevision")
    tokens = document.get("tokens")
    if not isinstance(tokens, list) or len(tokens) < 150:
        raise SystemExit("official theme catalog is unexpectedly incomplete")
    names: set[str] = set()
    for token in tokens:
        if not isinstance(token, dict):
            raise SystemExit("official theme token must be an object")
        name = token.get("cssName")
        if not isinstance(name, str) or not name.startswith("--dsw-") or name in names:
            raise SystemExit(f"invalid or duplicate official theme token {name!r}")
        names.add(name)
        source = token.get("source")
        if not isinstance(source, dict) or source.get("path") != EXPECTED_SOURCE or source.get("commit") != EXPECTED_COMMIT:
            raise SystemExit(f"token {name} lacks locked CSS source provenance")
        for scheme in ("light", "dark"):
            value = token.get(scheme)
            if not isinstance(value, dict) or not isinstance(value.get("rawValue"), str) or not isinstance(value.get("sourceLine"), int):
                raise SystemExit(f"token {name} has incomplete {scheme} value provenance")
    swift = SWIFT.read_text(encoding="utf-8")
    if (
        f'static let sourceCommit = "{EXPECTED_COMMIT}"' not in swift
        or f'static let revision = "{revision}"' not in swift
        or f'static let sourceInputRevision = "{source_input_revision}"' not in swift
    ):
        raise SystemExit("generated Swift theme catalog does not expose checked-in source revisions")
    with tempfile.TemporaryDirectory(prefix="dsh-theme-tokens-") as temporary:
        temporary_root = Path(temporary)
        regenerated_json = temporary_root / "official-theme-tokens.json"
        regenerated_swift = temporary_root / "OfficialThemeCatalog.swift"
        subprocess.run([
            sys.executable, str(GENERATOR),
            "--official-root", str(args.official_root),
            "--json-output", str(regenerated_json),
            "--swift-output", str(regenerated_swift),
        ], check=True)
        if regenerated_json.read_bytes() != CATALOG.read_bytes() or regenerated_swift.read_bytes() != SWIFT.read_bytes():
            raise SystemExit("official theme token catalog is stale; regenerate from the locked official source")
    print(f"Official theme token gate passed: {len(tokens)} CSS tokens.")


if __name__ == "__main__":
    main()
