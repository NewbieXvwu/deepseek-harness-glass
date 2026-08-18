#!/usr/bin/env python3
"""Fail closed when the app's declared Host baseline diverges from its bundled payload."""

from __future__ import annotations

import argparse
from datetime import date
import json
import plistlib
import subprocess
from pathlib import Path


LOCKED_SOURCE = "99f6f02fecdb7dff40c3fbc9470f5907c29f74ca"
REQUIRED_BUILD_FIELDS = (
    "id",
    "officialSourceCommit",
    "dshPackageVersion",
    "webFrontendPackageVersion",
    "nodeRuntimeVersion",
    "minimumAppVersion",
    "minimumMacOS",
    "ciRunner",
    "minimumXcodeMajor",
    "protocolFixtureRevision",
    "uiSpecRevision",
    "supportedArchitectures",
    "verificationState",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--payload-dir", type=Path, required=True)
    parser.add_argument("--node", type=Path, required=True)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def main() -> None:
    args = parse_args()
    root = args.root.resolve()
    catalog = load_json(root / "Sources/Spec/SupportedHostBuilds.json")
    builds = catalog.get("builds")
    if not isinstance(builds, list):
        raise SystemExit("SupportedHostBuilds.json builds must be an array")
    matching = [build for build in builds if build.get("id") == catalog.get("defaultBuildId")]
    if len(matching) != 1:
        raise SystemExit("SupportedHostBuilds.json must contain exactly one default build")
    build = matching[0]
    missing = [field for field in REQUIRED_BUILD_FIELDS if build.get(field) in (None, "", [])]
    if missing:
        raise SystemExit(f"supported build is missing required fields: {', '.join(missing)}")
    if build["officialSourceCommit"] != LOCKED_SOURCE:
        raise SystemExit("supported build officialSourceCommit does not match the locked official source")
    if build["verificationState"] not in {"planned", "verified"}:
        raise SystemExit("supported build verificationState must be planned or verified")
    verified_at = build.get("verifiedAt")
    if build["verificationState"] == "verified":
        if not isinstance(verified_at, str):
            raise SystemExit("verified supported build must include verifiedAt as an ISO date")
        try:
            date.fromisoformat(verified_at)
        except ValueError as error:
            raise SystemExit("verifiedAt must be an ISO-8601 date") from error
    elif verified_at is not None:
        raise SystemExit("planned supported build must not claim a verification date")

    info_path = root / "Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleShortVersionString") != build["minimumAppVersion"]:
        raise SystemExit("minimumAppVersion does not match CFBundleShortVersionString")

    lock = load_json(root / "ci/dsh-backend-payload/package-lock.json")
    declared = lock.get("packages", {}).get("", {}).get("dependencies", {})
    payload = args.payload_dir.resolve()
    expected = {
        "@deepseek-ai/dsh": build["dshPackageVersion"],
        "@deepseek-ai/dsh-web-frontend": build["webFrontendPackageVersion"],
    }
    for package, version in expected.items():
        if declared.get(package) != version:
            raise SystemExit(f"lockfile root dependency for {package} is not exact {version}")
        manifest = load_json(payload / "node_modules" / package / "package.json")
        if manifest.get("version") != version:
            raise SystemExit(f"bundled payload version for {package} is not {version}")

    actual_node = subprocess.check_output([str(args.node), "--version"], text=True).strip().removeprefix("v")
    if actual_node != build["nodeRuntimeVersion"]:
        raise SystemExit(f"bundled Node version {actual_node} does not match {build['nodeRuntimeVersion']}")

    print(
        "Supported Host build gate passed: "
        f"{build['id']} payload={build['dshPackageVersion']} web={build['webFrontendPackageVersion']} "
        f"node={actual_node} official={build['officialSourceCommit'][:7]}"
    )


if __name__ == "__main__":
    main()
