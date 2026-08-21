#!/usr/bin/env python3
"""Validate the generated OfficialUISpec build against the locked Host catalog."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ROOT.parent
METADATA = ROOT / "Sources/Spec/OfficialUISpec/official-ui-spec-build.json"
SWIFT_BUILD = ROOT / "Sources/Spec/OfficialUISpecBuild.swift"
HOST_CATALOG = ROOT / "Sources/Spec/SupportedHostBuilds.json"
GENERATOR = REPOSITORY_ROOT / "tools/spec-generation/generate_official_ui_spec_build.ts"
GENERATOR_DIR = GENERATOR.parent
REQUIRED = {
    "sourceCommit", "hostBuildId", "uiSpecRevision", "localeRevision", "tokenRevision",
    "layoutRevision", "fixtureRevision", "generatedAt", "generator", "inputs",
}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, default=METADATA)
    parser.add_argument("--swift-build", type=Path, default=SWIFT_BUILD)
    parser.add_argument("--host-catalog", type=Path, default=HOST_CATALOG)
    parser.add_argument("--node", default="node", help="path to the Node.js binary")
    return parser.parse_args()


def main() -> None:
    args = arguments()
    # The TypeScript generator runs from its own tool directory so bare
    # `typescript` resolves from its package-local install. Resolve the caller
    # supplied official root first; otherwise a workflow-relative `.reference`
    # path is accidentally re-based under `tools/spec-generation`.
    official_root = args.official_root.resolve()
    metadata_path = args.metadata
    swift_build_path = args.swift_build
    host_catalog_path = args.host_catalog
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    missing = REQUIRED - metadata.keys()
    if missing:
        raise SystemExit("OfficialUISpec build metadata missing: " + ", ".join(sorted(missing)))
    if metadata.get("schemaVersion") != 1:
        raise SystemExit("OfficialUISpec build metadata schemaVersion must be 1")
    for field in ("localeRevision", "tokenRevision", "layoutRevision", "fixtureRevision"):
        value = metadata[field]
        if not isinstance(value, str) or not value.startswith("sha256:") or len(value) != 71:
            raise SystemExit(f"OfficialUISpec {field} must be a sha256 revision")
    inputs = metadata["inputs"]
    if not isinstance(inputs, list) or not inputs:
        raise SystemExit("OfficialUISpec build metadata must list source inputs")
    if not {entry.get("kind") for entry in inputs if isinstance(entry, dict)} >= {"locale", "token", "layout", "fixture"}:
        raise SystemExit("OfficialUISpec metadata must cover locale, token, layout and fixture inputs")

    catalog = json.loads(host_catalog_path.read_text(encoding="utf-8"))
    default_id = catalog["defaultBuildId"]
    build = next((item for item in catalog["builds"] if item["id"] == default_id), None)
    if build is None:
        raise SystemExit("SupportedHostBuilds has no default build")
    expected = {
        "hostBuildId": build["id"],
        "sourceCommit": build["officialSourceCommit"],
        "uiSpecRevision": build["uiSpecRevision"],
    }
    for field, value in expected.items():
        if metadata[field] != value:
            raise SystemExit(f"OfficialUISpec {field}={metadata[field]!r} does not match Host catalog {value!r}")

    with tempfile.TemporaryDirectory(prefix="dsh-official-spec-") as temporary:
        temporary_root = Path(temporary)
        regenerated_json = temporary_root / "official-ui-spec-build.json"
        regenerated_swift = temporary_root / "OfficialUISpecBuild.swift"
        subprocess.run([
            args.node, "--experimental-strip-types", str(GENERATOR),
            "--official-root", str(official_root),
            "--json-output", str(regenerated_json),
            "--swift-output", str(regenerated_swift),
        ], check=True, cwd=GENERATOR_DIR)
        if regenerated_json.read_bytes() != metadata_path.read_bytes():
            raise SystemExit("OfficialUISpec metadata is stale; regenerate from the locked official source")
        if regenerated_swift.read_bytes() != swift_build_path.read_bytes():
            raise SystemExit("OfficialUISpec Swift build ID is stale; regenerate from the locked official source")
    print(f"OfficialUISpec build gate passed: {metadata['hostBuildId']} {metadata['sourceCommit'][:8]}.")


if __name__ == "__main__":
    main()
