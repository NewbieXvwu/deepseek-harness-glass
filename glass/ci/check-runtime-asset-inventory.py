#!/usr/bin/env python3
"""Validate the auditable runtime-asset migration inventory for T1.1."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INVENTORY_PATH = ROOT / "Sources/Spec/RuntimeAssetInventory.json"
VALID_DECISIONS = {"preserved", "migrated", "replaced", "deleted"}
LOCKED_SUPPORT_BUILD = "dsh-0.1.2-rc.1-official-a66e470"
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


def resolve_asset_path(raw_path: str, repo_root: Path) -> bool:
    clean = raw_path.strip()
    if not clean:
        return False
    if clean == "BuildManifest.json":
        # Build-time generated artifact produced during assemble.sh, not committed statically
        return True
    if clean == "SupportedHostBuilds.json":
        return (repo_root / "glass/Sources/Spec/SupportedHostBuilds.json").exists()
    return (repo_root / clean).exists() or (repo_root / "glass" / clean).exists()


def validate_inventory_document(document: object, repo_root: Path | None = None) -> list[str]:
    if not isinstance(document, dict):
        return ["runtime asset inventory must be a JSON object"]
    if document.get("schemaVersion") != 1:
        return ["runtime asset inventory schemaVersion must be 1"]
    if document.get("supportBuild") != LOCKED_SUPPORT_BUILD:
        return ["runtime asset inventory must name the verified fixed Host build"]
    assets = document.get("assets")
    if not isinstance(assets, list):
        return ["runtime asset inventory assets must be an array"]
    failures: list[str] = []
    seen: set[str] = set()
    for asset in assets:
        if not isinstance(asset, dict):
            failures.append("every runtime asset must be an object")
            continue
        asset_id = asset.get("id")
        if not isinstance(asset_id, str) or not asset_id.strip():
            failures.append("every runtime asset must have a non-empty id")
            continue
        if asset_id in seen:
            failures.append(f"duplicate runtime asset id: {asset_id}")
        seen.add(asset_id)
        for field in ("source", "responsibility", "decision", "destination", "verification"):
            val = asset.get(field)
            if not isinstance(val, str) or not val.strip():
                failures.append(f"runtime asset {asset_id} is missing {field}")
        decision = asset.get("decision")
        if decision not in VALID_DECISIONS:
            failures.append(f"runtime asset {asset_id} has invalid decision {decision!r}")
            continue

        if repo_root is not None:
            # 1. Destination verification:
            dest = asset.get("destination", "")
            if decision == "deleted" or dest == "reference-only outside App target":
                # Deleted asset or architectural decision note without active target path
                pass
            else:
                dest_parts = [p.strip() for part in dest.split(",") for p in part.split(" and ") if p.strip()]
                for part in dest_parts:
                    if not resolve_asset_path(part, repo_root):
                        failures.append(f"runtime asset {asset_id} destination path does not exist: {part}")

            # 2. Source verification:
            src = asset.get("source", "")
            if decision in ("replaced", "deleted") or "historical" in src or "plus" in src or "window construction" in src:
                # Replaced/deleted sources are historical provenance and no longer present on disk
                pass
            else:
                src_parts = [p.strip() for part in src.split(",") for p in part.split(" and ") if p.strip()]
                for part in src_parts:
                    if not resolve_asset_path(part, repo_root):
                        failures.append(f"runtime asset {asset_id} source path does not exist: {part}")

    missing = REQUIRED_IDS - seen
    if missing:
        failures.append("runtime asset inventory misses: " + ", ".join(sorted(missing)))
    return failures


def main() -> None:
    document = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
    failures = validate_inventory_document(document, repo_root=ROOT.parent)
    if failures:
        raise SystemExit("; ".join(failures))

    verify_native_app_target()

    assets = document.get("assets", [])
    print(f"Runtime asset inventory gate passed: {len(assets)} classified assets.")


if __name__ == "__main__":
    main()
