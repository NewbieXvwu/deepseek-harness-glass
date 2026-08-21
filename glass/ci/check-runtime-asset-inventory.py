#!/usr/bin/env python3
"""Validate the auditable runtime-asset migration inventory for T1.1."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INVENTORY_PATH = ROOT / "Sources/Spec/RuntimeAssetInventory.json"
VALID_DECISIONS = {"preserved", "migrated", "replaced", "deleted"}
REQUIRED_IDS = {
    "legacy-app-entry",
    "window-lifecycle",
    "menu-bar-residency",
    "owned-host-lifecycle",
    "external-port-attachment",
    "snapshot-export",
    "host-user-data-and-logs",
    "bundled-node-and-payload",
    "backend-repair-tool",
    "app-metadata-assets-signing",
    "native-quality-ci",
    "release-workflow",
    "webview-shell",
}


def native_app_target_failures(package: object) -> list[str]:
    """Return target-graph failures without inspecting application source text."""
    if not isinstance(package, dict):
        return ["SwiftPM target graph must be an object"]
    targets = package.get("targets")
    if not isinstance(targets, list):
        return ["SwiftPM target graph has no target array"]
    app_targets = [
        target for target in targets
        if isinstance(target, dict)
        and target.get("type") == "executable"
        and target.get("name") == "DeepSeekHarnessGlassApp"
        and target.get("path") == "Sources/App"
    ]
    if len(app_targets) != 1:
        return ["runtime asset migration requires exactly one DeepSeekHarnessGlassApp executable target at Sources/App"]
    return []


def verify_native_app_target() -> None:
    """Validate the compiled-package ownership boundary, not Swift source text."""
    result = subprocess.run(
        ["swift", "package", "describe", "--type", "json"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit("unable to inspect SwiftPM target graph for runtime asset inventory: " + result.stderr.strip())
    try:
        package = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit(f"SwiftPM target graph is not valid JSON: {error}") from error
    failures = native_app_target_failures(package)
    if failures:
        raise SystemExit("; ".join(failures))


def main() -> None:
    document = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != 1:
        raise SystemExit("runtime asset inventory schemaVersion must be 1")
    if document.get("supportBuild") != "dsh-0.1.0-rc.8-official-141eb6f":
        raise SystemExit("runtime asset inventory must name the verified fixed Host build")
    assets = document.get("assets")
    if not isinstance(assets, list):
        raise SystemExit("runtime asset inventory assets must be an array")
    seen: set[str] = set()
    for asset in assets:
        if not isinstance(asset, dict):
            raise SystemExit("every runtime asset must be an object")
        asset_id = asset.get("id")
        if not isinstance(asset_id, str) or not asset_id:
            raise SystemExit("every runtime asset must have a non-empty id")
        if asset_id in seen:
            raise SystemExit(f"duplicate runtime asset id: {asset_id}")
        seen.add(asset_id)
        for field in ("source", "responsibility", "decision", "destination", "verification"):
            if not isinstance(asset.get(field), str) or not asset[field].strip():
                raise SystemExit(f"runtime asset {asset_id} is missing {field}")
        if asset["decision"] not in VALID_DECISIONS:
            raise SystemExit(f"runtime asset {asset_id} has invalid decision {asset['decision']!r}")
    missing = REQUIRED_IDS - seen
    if missing:
        raise SystemExit("runtime asset inventory misses: " + ", ".join(sorted(missing)))

    verify_native_app_target()

    print(f"Runtime asset inventory gate passed: {len(assets)} classified assets.")


if __name__ == "__main__":
    main()
