#!/usr/bin/env python3
"""Verify structured Host upgrade governance metadata.

This deliberately consumes JSON metadata and artifact paths only. It does not
open, parse, or match project Swift source text: protocol/reducer behavior stays
covered by their executable test targets.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Any


class ValidationError(Exception):
    pass


def load_json(path: Path) -> dict[str, Any]:
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(decoded, dict):
        raise ValidationError(f"JSON root must be an object: {path}")
    return decoded


def required_string(document: dict[str, Any], key: str, label: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise ValidationError(f"{label}.{key} must be a non-empty string")
    return value


def default_build(supported: dict[str, Any]) -> dict[str, Any]:
    build_id = required_string(supported, "defaultBuildId", "SupportedHostBuilds")
    builds = supported.get("builds")
    if not isinstance(builds, list):
        raise ValidationError("SupportedHostBuilds.builds must be an array")
    for build in builds:
        if isinstance(build, dict) and build.get("id") == build_id:
            return build
    raise ValidationError("SupportedHostBuilds.defaultBuildId must name a build")


def repository_path(root: Path, raw_path: str) -> Path:
    relative = Path(raw_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValidationError(f"artifact path escapes repository: {raw_path}")
    target = root / relative
    if not target.is_file():
        raise ValidationError(f"required upgrade artifact is missing: {raw_path}")
    return target


def validate_documents(
    root: Path,
    report: dict[str, Any],
    supported: dict[str, Any],
    ui_spec: dict[str, Any],
    locales: dict[str, Any],
    raw_events: dict[str, Any],
) -> None:
    if report.get("schemaVersion") != 1:
        raise ValidationError("HostUpgradeReport.schemaVersion must be 1")

    build = default_build(supported)
    host_build_id = required_string(report, "hostBuildId", "HostUpgradeReport")
    if host_build_id != required_string(build, "id", "SupportedHostBuilds.build"):
        raise ValidationError("HostUpgradeReport.hostBuildId must equal SupportedHostBuilds default build")

    commit = required_string(report, "officialSourceCommit", "HostUpgradeReport")
    expected_commits = {
        "SupportedHostBuilds": required_string(build, "officialSourceCommit", "SupportedHostBuilds.build"),
        "official-ui-spec-build": required_string(ui_spec, "sourceCommit", "official-ui-spec-build"),
        "official-locales": required_string(locales, "sourceCommit", "official-locales"),
        "official-raw-event-replay-fixtures": required_string(raw_events, "officialSourceCommit", "official-raw-event-replay-fixtures"),
    }
    mismatched = [name for name, value in expected_commits.items() if value != commit]
    if mismatched:
        raise ValidationError("official source commit mismatch: " + ", ".join(mismatched))

    revisions = {
        "uiSpecRevision": (build, "uiSpecRevision"),
        "protocolFixtureRevision": (build, "protocolFixtureRevision"),
        "rawEventFixtureRevision": (raw_events, "fixtureRevision"),
    }
    for report_key, (source, source_key) in revisions.items():
        if required_string(report, report_key, "HostUpgradeReport") != required_string(source, source_key, report_key):
            raise ValidationError(f"HostUpgradeReport.{report_key} is inconsistent with structured source metadata")

    governance = required_string(report, "governanceDocument", "HostUpgradeReport")
    repository_path(root, governance)
    artifacts = report.get("requiredArtifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        raise ValidationError("HostUpgradeReport.requiredArtifacts must be a non-empty object")
    for name, raw_path in artifacts.items():
        if not isinstance(name, str) or not isinstance(raw_path, str):
            raise ValidationError("HostUpgradeReport.requiredArtifacts must map strings to paths")
        repository_path(root, raw_path)

    stages = report.get("requiredReviewStages")
    required_stages = {
        "official-source-lock",
        "structured-spec-regeneration",
        "typed-dto-and-facade-contracts",
        "raw-event-reducer-and-transport-replay",
        "macos-visual-accessibility-performance-evidence",
        "supported-builds-release-gate",
    }
    if not isinstance(stages, list) or set(stages) != required_stages or len(stages) != len(required_stages):
        raise ValidationError("HostUpgradeReport.requiredReviewStages must contain each required governance stage exactly once")


def documents_at(root: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    report = load_json(root / "glass/Sources/Spec/HostUpgradeReport.json")
    supported = load_json(root / "glass/Sources/Spec/SupportedHostBuilds.json")
    ui_spec = load_json(root / "glass/Sources/Spec/OfficialUISpec/official-ui-spec-build.json")
    locales = load_json(root / "glass/Sources/Spec/Locales/official-locales.json")
    raw_events = load_json(root / "glass/Sources/Core/Resources/official-raw-event-replay-fixtures.json")
    return report, supported, ui_spec, locales, raw_events


def self_test(root: Path) -> None:
    documents = documents_at(root)
    validate_documents(root, *documents)
    report, supported, ui_spec, locales, raw_events = copy.deepcopy(documents)
    report["officialSourceCommit"] = "0" * 40
    try:
        validate_documents(root, report, supported, ui_spec, locales, raw_events)
    except ValidationError:
        pass
    else:
        raise AssertionError("mismatched official commit must be rejected")

    report = copy.deepcopy(documents[0])
    report["requiredArtifacts"]["remoteContract"] = "glass/Sources/Spec/Fixtures/missing.json"
    try:
        validate_documents(root, report, *documents[1:])
    except ValidationError:
        pass
    else:
        raise AssertionError("missing required artifact must be rejected")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = args.repo.resolve()
    try:
        documents = documents_at(root)
        validate_documents(root, *documents)
        if args.self_test:
            self_test(root)
    except (AssertionError, ValidationError) as error:
        print(f"host-upgrade-report check failed: {error}", file=sys.stderr)
        return 1
    print("host-upgrade-report check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
