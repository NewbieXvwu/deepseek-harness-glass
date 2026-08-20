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
SWIFT = ROOT / "Sources/Spec/OfficialLocaleCatalog.swift"
SPEC_BUILD = ROOT / "Sources/Spec/OfficialUISpec/official-ui-spec-build.json"
GENERATOR = REPOSITORY_ROOT / "tools/spec-generation/generate_official_locales.py"
EXPECTED_COMMIT = "141eb6fef83422698aef7a981029e843e8161534"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = arguments()
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
    swift = SWIFT.read_text(encoding="utf-8")
    if (f'static let sourceCommit = "{EXPECTED_COMMIT}"' not in swift
            or f'static let revision = "{revision}"' not in swift
            or f'static let sourceInputRevision = "{source_input_revision}"' not in swift):
        raise SystemExit("generated Swift locale catalog does not expose checked-in commit/revisions")

    with tempfile.TemporaryDirectory(prefix="dsh-official-locales-") as temporary:
        temporary_root = Path(temporary)
        regenerated_json = temporary_root / "official-locales.json"
        regenerated_swift = temporary_root / "OfficialLocaleCatalog.swift"
        subprocess.run([
            sys.executable, str(GENERATOR),
            "--official-root", str(args.official_root),
            "--json-output", str(regenerated_json),
            "--swift-output", str(regenerated_swift),
        ], check=True)
        if regenerated_json.read_bytes() != CATALOG.read_bytes() or regenerated_swift.read_bytes() != SWIFT.read_bytes():
            raise SystemExit("official locale catalog is stale; regenerate from the locked official source")
    print(f"Official locale gate passed: {len(entries)} entries / {len(by_id)} en+zh keys.")


if __name__ == "__main__":
    main()
