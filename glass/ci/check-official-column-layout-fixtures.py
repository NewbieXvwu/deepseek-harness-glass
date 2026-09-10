#!/usr/bin/env python3
"""Compare checked three-column fixtures with fresh upstream computeColumns results."""

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


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--node", type=Path, required=True)
    return parser.parse_args()


def fixtures(document: object) -> list[dict[str, object]]:
    if not isinstance(document, dict):
        raise SystemExit("official column layout fixture root must be an object")
    rows = document.get("fixtures")
    if not isinstance(rows, list) or not rows:
        raise SystemExit("official column layout fixtures are empty")
    seen: set[str] = set()
    result: list[dict[str, object]] = []
    for row in rows:
        if not isinstance(row, dict):
            raise SystemExit("official column layout fixture must be an object")
        name = row.get("name")
        if not isinstance(name, str) or not name or name in seen:
            raise SystemExit(f"invalid or duplicate column fixture name: {name!r}")
        seen.add(name)
        for key in ("viewport", "sidebarPreference", "detailsPreference"):
            if not isinstance(row.get(key), (int, float)):
                raise SystemExit(f"fixture {name} has invalid {key}")
        expected = row.get("expected")
        if not isinstance(expected, dict) or not all(isinstance(expected.get(key), (int, float)) for key in ("sidebar", "center", "details")):
            raise SystemExit(f"fixture {name} has invalid expected columns")
        result.append({
            "name": name,
            "viewport": row["viewport"],
            "sidebarPreference": row["sidebarPreference"],
            "detailsPreference": row["detailsPreference"],
            "expected": {key: expected[key] for key in ("sidebar", "center", "details")},
        })
    return result


def main() -> None:
    args = arguments()
    checked = fixtures(json.loads(CATALOG.read_text(encoding="utf-8")))
    tsx_cli = args.official_root / "node_modules/tsx/dist/cli.mjs"
    if not tsx_cli.is_file():
        raise SystemExit(f"upstream tsx runtime is unavailable: {tsx_cli}")
    with tempfile.TemporaryDirectory(prefix="dsh-columns-") as temporary:
        generated_path = Path(temporary) / CATALOG.name
        subprocess.run([
            str(args.node), str(tsx_cli), str(GENERATOR),
            "--official-root", str(args.official_root),
            "--output", str(generated_path),
        ], check=True)
        generated = fixtures(json.loads(generated_path.read_text(encoding="utf-8")))
    if checked != generated:
        raise SystemExit("official column layout fixtures differ from fresh upstream computeColumns results")
    print(f"Official column layout fixture gate passed: {len(checked)} cases.")


if __name__ == "__main__":
    main()
