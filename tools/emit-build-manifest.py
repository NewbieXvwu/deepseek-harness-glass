#!/usr/bin/env python3
"""Emit the native app BuildManifest from structured supported-Host metadata."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class ManifestError(Exception):
    pass


def read_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ManifestError(f"cannot load {path}: {error}") from error
    if not isinstance(value, dict):
        raise ManifestError(f"expected object in {path}")
    return value


def field(document: dict[str, Any], key: str, label: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise ManifestError(f"{label}.{key} must be a non-empty string")
    return value


def default_build(supported: dict[str, Any]) -> dict[str, Any]:
    default_id = field(supported, "defaultBuildId", "SupportedHostBuilds")
    builds = supported.get("builds")
    if not isinstance(builds, list):
        raise ManifestError("SupportedHostBuilds.builds must be an array")
    for build in builds:
        if isinstance(build, dict) and build.get("id") == default_id:
            return build
    raise ManifestError("SupportedHostBuilds.defaultBuildId does not identify a build")


def make_manifest(repo: Path, app_source_revision: str) -> dict[str, Any]:
    spec = repo / "glass/Sources/Spec"
    supported = read_object(spec / "SupportedHostBuilds.json")
    report = read_object(spec / "HostUpgradeReport.json")
    build = default_build(supported)

    build_id = field(build, "id", "SupportedHostBuilds.build")
    if field(report, "hostBuildId", "HostUpgradeReport") != build_id:
        raise ManifestError("HostUpgradeReport.hostBuildId differs from default supported build")
    commit = field(build, "officialSourceCommit", "SupportedHostBuilds.build")
    if field(report, "officialSourceCommit", "HostUpgradeReport") != commit:
        raise ManifestError("HostUpgradeReport official source commit differs from default supported build")

    architectures = build.get("supportedArchitectures")
    if not isinstance(architectures, list) or not all(isinstance(item, str) and item for item in architectures):
        raise ManifestError("SupportedHostBuilds.build.supportedArchitectures must be a non-empty string array")

    return {
        "schemaVersion": 2,
        "appSourceRevision": app_source_revision,
        "hostBuildId": build_id,
        "officialSourceCommit": commit,
        "dshPackageVersion": field(build, "dshPackageVersion", "SupportedHostBuilds.build"),
        "webFrontendPackageVersion": field(build, "webFrontendPackageVersion", "SupportedHostBuilds.build"),
        "nodeRuntimeVersion": field(build, "nodeRuntimeVersion", "SupportedHostBuilds.build"),
        "minimumMacOS": field(build, "minimumMacOS", "SupportedHostBuilds.build"),
        "supportedArchitectures": architectures,
        "uiSpecRevision": field(report, "uiSpecRevision", "HostUpgradeReport"),
        "protocolFixtureRevision": field(report, "protocolFixtureRevision", "HostUpgradeReport"),
        "rawEventFixtureRevision": field(report, "rawEventFixtureRevision", "HostUpgradeReport"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--app-source-revision")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--payload-versions", action="store_true", help="write default dsh and frontend versions as one tab-delimited line")
    args = parser.parse_args()
    if args.payload_versions == (args.output is not None):
        parser.error("choose exactly one of --payload-versions or --output")
    if args.output is not None and not args.app_source_revision:
        parser.error("--app-source-revision is required with --output")
    try:
        manifest = make_manifest(args.repo.resolve(), args.app_source_revision or "payload-version-query")
    except ManifestError as error:
        print(f"build-manifest generation failed: {error}", file=sys.stderr)
        return 1
    if args.payload_versions:
        print(f"{manifest['dshPackageVersion']}\t{manifest['webFrontendPackageVersion']}")
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
