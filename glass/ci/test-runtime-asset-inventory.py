#!/usr/bin/env python3
"""Behavioral self-test for the runtime asset SwiftPM target graph contract."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "ci/check-runtime-asset-inventory.py"

spec = importlib.util.spec_from_file_location("runtime_asset_inventory", CHECKER)
if spec is None or spec.loader is None:
    raise SystemExit("unable to load runtime asset inventory checker")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def app_target(path: str = "Sources/App") -> dict[str, object]:
    return {
        "name": "DeepSeekHarnessGlassApp",
        "type": "executable",
        "path": path,
    }


def minimal_asset(asset_id: str, decision: str = "preserved", destination: str = "Sources/App/DeepSeekHarnessGlassApp.swift", source: str = "Sources/Snapshot/SnapshotExporter.swift") -> dict[str, str]:
    return {
        "id": asset_id,
        "source": source,
        "responsibility": "Auditable responsibility description",
        "decision": decision,
        "destination": destination,
        "verification": "Auditable verification method",
    }


def minimal_valid_document() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "supportBuild": "dsh-0.1.1-rc.2-official-b150a55",
        "assets": [minimal_asset(aid) for aid in sorted(module.REQUIRED_IDS)],
    }


def test_core_inventory_rules() -> None:
    # 1. Baseline minimal valid document
    valid_doc = minimal_valid_document()
    failures = module.validate_inventory_document(valid_doc, repo_root=ROOT.parent)
    if failures:
        raise SystemExit(f"valid minimal inventory document unexpectedly failed: {failures}")

    # 2. Duplicate asset ID
    dup_doc = copy.deepcopy(valid_doc)
    dup_doc["assets"].append(minimal_asset("legacy-app-entry"))
    dup_failures = module.validate_inventory_document(dup_doc)
    if not any("duplicate runtime asset id: legacy-app-entry" in f for f in dup_failures):
        raise SystemExit("duplicate asset ID was not rejected")

    # 3. Invalid decision enum
    bad_dec_doc = copy.deepcopy(valid_doc)
    bad_dec_doc["assets"][0]["decision"] = "unsupported_enum"
    bad_dec_failures = module.validate_inventory_document(bad_dec_doc)
    if not any("invalid decision 'unsupported_enum'" in f for f in bad_dec_failures):
        raise SystemExit("invalid decision enum was not rejected")

    # 4. Missing required field
    missing_field_doc = copy.deepcopy(valid_doc)
    missing_field_doc["assets"][0]["responsibility"] = "   "
    missing_field_failures = module.validate_inventory_document(missing_field_doc)
    if not any("missing responsibility" in f for f in missing_field_failures):
        raise SystemExit("missing required string field was not rejected")

    # 5. Missing required asset ID
    missing_id_doc = copy.deepcopy(valid_doc)
    missing_id_doc["assets"] = [a for a in missing_id_doc["assets"] if a["id"] != "legacy-app-entry"]
    missing_id_failures = module.validate_inventory_document(missing_id_doc)
    if not any("runtime asset inventory misses" in f and "legacy-app-entry" in f for f in missing_id_failures):
        raise SystemExit("missing required asset ID was not rejected")

    # 6. Non-existent file path existence check
    bad_path_doc = copy.deepcopy(valid_doc)
    bad_path_doc["assets"][0]["destination"] = "Sources/App/NonExistent_Fake_File.swift"
    bad_path_failures = module.validate_inventory_document(bad_path_doc, repo_root=ROOT.parent)
    if not any("destination path does not exist" in f for f in bad_path_failures):
        raise SystemExit("non-existent destination path was not rejected")


def main() -> None:
    baseline = {"targets": [app_target()]}
    if module.native_app_target_failures(baseline):
        raise SystemExit("valid app target graph unexpectedly failed")

    wrong_path = {"targets": [app_target("Sources/Wrong")]}
    if not module.native_app_target_failures(wrong_path):
        raise SystemExit("wrong native app target path was not rejected")

    duplicate_entry = {"targets": [app_target(), app_target()]}
    if not module.native_app_target_failures(duplicate_entry):
        raise SystemExit("duplicate native app entry was not rejected")

    if not module.native_app_target_failures({"targets": []}):
        raise SystemExit("missing native app target was not rejected")

    test_core_inventory_rules()

    print("Runtime asset target graph & core inventory rules self-test passed.")


if __name__ == "__main__":
    main()
