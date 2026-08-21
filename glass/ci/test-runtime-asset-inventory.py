#!/usr/bin/env python3
"""Behavioral self-test for the runtime asset SwiftPM target graph contract."""

from __future__ import annotations

import importlib.util
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

    print("Runtime asset target graph self-test passed.")


if __name__ == "__main__":
    main()
