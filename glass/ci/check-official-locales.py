#!/usr/bin/env python3
"""Validate reproducible official locale catalog provenance and bilingual completeness."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ROOT.parent
CATALOG = ROOT / "Sources/Spec/Locales/official-locales.json"
SPEC_BUILD = ROOT / "Sources/Spec/OfficialUISpec/official-ui-spec-build.json"
GENERATOR = REPOSITORY_ROOT / "tools/spec-generation/generate_official_locales.ts"
GENERATOR_DIR = GENERATOR.parent
EXPECTED_COMMIT = "528c682e061696f5a160f363f236ecbf53cbd006"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--node", default="node", help="path to the Node.js binary")
    return parser.parse_args()


def main() -> None:
    args = arguments()
    # The generator is deliberately executed from its package-local dependency
    # directory. Preserve the workflow caller's official-root semantics by
    # resolving it before that cwd switch.
    official_root = args.official_root.resolve()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    if catalog.get("schemaVersion") != 1 or catalog.get("sourceCommit") != EXPECTED_COMMIT:
        raise SystemExit("official locale catalog has an invalid schema or source commit")
    if catalog.get("languages") != ["en", "zh"]:
        raise SystemExit("official locale catalog must explicitly support en and zh")
    revision = catalog.get("localeRevision")
    source_input_revision = catalog.get("sourceInputRevision")
    for field, value in (("localeRevision", revision), ("sourceInputRevision", source_input_revision)):
        if not isinstance(value, str) or not value.startswith("sha256:") or len(value) != 71:
            raise SystemExit(f"official locale catalog must have a SHA-256 {field}")
    spec_build = json.loads(SPEC_BUILD.read_text(encoding="utf-8"))
    if spec_build.get("localeRevision") != source_input_revision:
        raise SystemExit("official locale catalog sourceInputRevision does not match OfficialUISpec build localeRevision")
    entries = catalog.get("entries")
    if not isinstance(entries, list) or not entries:
        raise SystemExit("official locale catalog must have entries")
    by_id: dict[str, dict[str, dict[str, object]]] = defaultdict(dict)
    for entry in entries:
        if not isinstance(entry, dict):
            raise SystemExit("official locale entry must be an object")
        for field in ("id", "namespace", "key", "language", "value", "interpolationParameters", "pluralCategory", "source"):
            if field not in entry:
                raise SystemExit(f"official locale entry missing {field}")
        language = entry["language"]
        identifier = entry["id"]
        if language not in {"en", "zh"}:
            raise SystemExit(f"unsupported locale language {language!r}")
        if language in by_id[identifier]:
            raise SystemExit(f"duplicate locale entry {identifier} ({language})")
        source = entry["source"]
        if not isinstance(source, dict) or source.get("commit") != EXPECTED_COMMIT or not isinstance(source.get("path"), str) or not isinstance(source.get("line"), int):
            raise SystemExit(f"locale entry {identifier} lacks source path/line/commit provenance")
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
    with tempfile.TemporaryDirectory(prefix="dsh-official-locales-") as temporary:
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
            raise SystemExit("official locale JSON catalog is stale; regenerate from the locked official source")
    print(f"Official locale data provenance passed: {len(entries)} entries / {len(by_id)} en+zh keys; compiled runtime parity is covered by XCTest.")


if __name__ == "__main__":
    main()
