#!/usr/bin/env python3
"""Validate reproducible Swift fixtures from official ui-layout computeColumns."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ROOT.parent
CATALOG = ROOT / "Sources/Spec/Fixtures/official-column-layout-fixtures.json"
GENERATOR = REPOSITORY_ROOT / "tools/spec-generation/generate_official_column_layout_fixtures.ts"
EXPECTED_COMMIT = "141eb6fef83422698aef7a981029e843e8161534"
EXPECTED_SOURCE = "packages/client/ui-layout/src/client/columns.ts"
EXPECTED_SHA256 = "c2f002126fc671aeaad058eae310d265f7b1f9b77223686c0fe4619cda4e71e2"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--node", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    document = json.loads(CATALOG.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != 1 or document.get("sourceCommit") != EXPECTED_COMMIT:
        raise SystemExit("official column layout fixtures have invalid schema or source commit")
    source = document.get("source")
    if not isinstance(source, dict) or source.get("path") != EXPECTED_SOURCE or source.get("sha256") != EXPECTED_SHA256:
        raise SystemExit("official column layout fixtures have invalid source provenance")
    fixtures = document.get("fixtures")
    if not isinstance(fixtures, list) or len(fixtures) < 30:
        raise SystemExit("official column layout fixtures are unexpectedly incomplete")
    names: set[str] = set()
    for fixture in fixtures:
        if not isinstance(fixture, dict) or not isinstance(fixture.get("name"), str) or fixture["name"] in names:
            raise SystemExit("official column layout fixtures have missing or duplicate names")
        names.add(fixture["name"])
        if not all(isinstance(fixture.get(key), (int, float)) for key in ("viewport", "sidebarPreference", "detailsPreference")):
            raise SystemExit(f"fixture {fixture['name']} has invalid numeric inputs")
        expected = fixture.get("expected")
        if not isinstance(expected, dict) or not all(isinstance(expected.get(key), (int, float)) for key in ("sidebar", "center", "details")):
            raise SystemExit(f"fixture {fixture['name']} has invalid expected columns")
    tsx_cli = args.official_root / "node_modules/tsx/dist/cli.mjs"
    if not tsx_cli.is_file():
        raise SystemExit(f"locked official tsx runtime is unavailable: {tsx_cli}")
    with tempfile.TemporaryDirectory(prefix="dsh-columns-") as temporary:
        regenerated = Path(temporary) / CATALOG.name
        subprocess.run([
            str(args.node), str(tsx_cli), str(GENERATOR),
            "--official-root", str(args.official_root),
            "--output", str(regenerated),
        ], check=True)
        if regenerated.read_bytes() != CATALOG.read_bytes():
            raise SystemExit("official column layout fixtures are stale; regenerate from locked computeColumns")
    print(f"Official column layout fixture gate passed: {len(fixtures)} cases.")


if __name__ == "__main__":
    main()
