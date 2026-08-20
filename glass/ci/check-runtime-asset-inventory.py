#!/usr/bin/env python3
"""Validate the auditable runtime-asset migration inventory for T1.1."""

from __future__ import annotations

import json
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

    if (ROOT / "Sources/main.swift").exists():
        raise SystemExit("legacy Sources/main.swift must not remain after App lifecycle migration")
    app_entry = ROOT / "Sources/App/DeepSeekHarnessGlassApp.swift"
    if "@main" not in app_entry.read_text(encoding="utf-8"):
        raise SystemExit("module App entry must own the only @main declaration")

    source_text = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / "Sources").rglob("*.swift"))
    if "127.0.0.1:3080" in source_text or "__DSH_BOOT__" in source_text:
        raise SystemExit("external 3080 DSH attachment is prohibited by the fixed Host boundary")
    print(f"Runtime asset inventory gate passed: {len(assets)} classified assets.")


if __name__ == "__main__":
    main()
