#!/usr/bin/env python3
"""Validate bilingual locale semantics and fresh generated runtime output."""

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
SWIFT_CATALOG = ROOT / "Sources/Spec/OfficialLocaleCatalog.swift"
GENERATOR = REPOSITORY_ROOT / "tools/spec-generation/generate_official_locales.ts"
GENERATOR_DIR = GENERATOR.parent


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--node", default="node", help="path to the Node.js binary")
    return parser.parse_args()


def main() -> None:
    args = arguments()
    official_root = args.official_root.resolve()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    if catalog.get("schemaVersion") != 1:
        raise SystemExit("locale catalog schemaVersion must be 1")
    if catalog.get("languages") != ["en", "zh"]:
        raise SystemExit("locale catalog must support en and zh")

    entries = catalog.get("entries")
    if not isinstance(entries, list) or not entries:
        raise SystemExit("locale catalog must have entries")
    by_id: dict[str, dict[str, dict[str, object]]] = defaultdict(dict)
    for entry in entries:
        if not isinstance(entry, dict):
            raise SystemExit("locale entry must be an object")
        for field in ("id", "namespace", "key", "language", "value", "interpolationParameters", "pluralCategory"):
            if field not in entry:
                raise SystemExit(f"locale entry missing {field}")
        language = entry["language"]
        identifier = entry["id"]
        if language not in {"en", "zh"}:
            raise SystemExit(f"unsupported locale language {language!r}")
        if language in by_id[identifier]:
            raise SystemExit(f"duplicate locale entry {identifier} ({language})")
        parameters = entry["interpolationParameters"]
        if parameters != sorted(set(parameters)):
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

    with tempfile.TemporaryDirectory(prefix="dsh-locales-") as temporary:
        temporary_root = Path(temporary)
        regenerated_json = temporary_root / "official-locales.json"
        regenerated_swift = temporary_root / "OfficialLocaleCatalog.swift"
        subprocess.run([
            args.node, "--experimental-strip-types", str(GENERATOR),
            "--official-root", str(official_root),
            "--json-output", str(regenerated_json),
            "--swift-output", str(regenerated_swift),
        ], check=True, cwd=GENERATOR_DIR)
        if regenerated_json.read_bytes() != CATALOG.read_bytes():
            raise SystemExit("locale JSON differs from fresh source extraction")
        if regenerated_swift.read_bytes() != SWIFT_CATALOG.read_bytes():
            raise SystemExit("locale Swift catalog differs from fresh source extraction")

    print(f"Locale gate passed: {len(entries)} entries / {len(by_id)} complete en+zh keys.")


if __name__ == "__main__":
    main()
