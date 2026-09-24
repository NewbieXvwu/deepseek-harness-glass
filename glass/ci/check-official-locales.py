#!/usr/bin/env python3
"""Validate bilingual locale semantics against fresh upstream AST extraction."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ROOT.parent
CATALOG = ROOT / "Sources/Spec/Locales/official-locales.json"
GENERATOR = REPOSITORY_ROOT / "tools/spec-generation/generate_official_locales.ts"
GENERATOR_DIR = GENERATOR.parent
SEMANTIC_FIELDS = (
    "id",
    "namespace",
    "key",
    "language",
    "value",
    "interpolationParameters",
    "pluralCategory",
)


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--node", default="node", help="path to the Node.js binary")
    return parser.parse_args()


def semantics(document: dict) -> dict:
    entries = document.get("entries")
    if not isinstance(entries, list):
        raise SystemExit("locale catalog must have entries")
    return {
        "schemaVersion": document.get("schemaVersion"),
        "languages": document.get("languages"),
        "entries": [
            {field: entry.get(field) for field in SEMANTIC_FIELDS}
            for entry in entries
            if isinstance(entry, dict)
        ],
    }


def validate(document: dict) -> tuple[int, int]:
    if document.get("schemaVersion") != 1:
        raise SystemExit("locale catalog schemaVersion must be 1")
    if document.get("languages") != ["en", "zh"]:
        raise SystemExit("locale catalog must support en and zh")
    entries = document.get("entries")
    if not isinstance(entries, list) or not entries:
        raise SystemExit("locale catalog must have entries")

    by_id: dict[str, dict[str, dict]] = defaultdict(dict)
    for entry in entries:
        if not isinstance(entry, dict):
            raise SystemExit("locale entry must be an object")
        for field in SEMANTIC_FIELDS:
            if field not in entry:
                raise SystemExit(f"locale entry missing {field}")
        language = entry["language"]
        identifier = entry["id"]
        if language not in {"en", "zh"}:
            raise SystemExit(f"unsupported locale language {language!r}")
        if language in by_id[identifier]:
            raise SystemExit(f"duplicate locale entry {identifier} ({language})")
        parameters = entry["interpolationParameters"]
        if not isinstance(parameters, list) or parameters != sorted(set(parameters)):
            raise SystemExit(f"locale entry {identifier} interpolation parameters must be sorted and unique")
        by_id[identifier][language] = entry

    incomplete = [identifier for identifier, translations in by_id.items() if set(translations) != {"en", "zh"}]
    if incomplete:
        raise SystemExit("locale catalog has incomplete en/zh keys: " + ", ".join(sorted(incomplete)[:20]))
    for identifier, translations in by_id.items():
        if translations["en"]["interpolationParameters"] != translations["zh"]["interpolationParameters"]:
            raise SystemExit(f"locale interpolation mismatch between en and zh for {identifier}")
        if translations["en"]["pluralCategory"] != translations["zh"]["pluralCategory"]:
            raise SystemExit(f"locale plural category mismatch between en and zh for {identifier}")
    return len(entries), len(by_id)


def main() -> None:
    args = arguments()
    checked = json.loads(CATALOG.read_text(encoding="utf-8"))
    entry_count, key_count = validate(checked)

    with tempfile.TemporaryDirectory(prefix="dsh-locales-") as temporary:
        regenerated = Path(temporary) / "official-locales.json"
        subprocess.run([
            args.node,
            "--experimental-strip-types",
            str(GENERATOR),
            "--official-root",
            str(args.official_root.resolve()),
            "--json-output",
            str(regenerated),
        ], check=True, cwd=GENERATOR_DIR)
        fresh = json.loads(regenerated.read_text(encoding="utf-8"))
        validate(fresh)
        if semantics(checked) != semantics(fresh):
            raise SystemExit("locale semantics differ from fresh source extraction")

    print(f"Locale gate passed: {entry_count} entries / {key_count} complete en+zh keys.")


if __name__ == "__main__":
    main()
