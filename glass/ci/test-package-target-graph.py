#!/usr/bin/env python3
"""Behavioral self-test for the structured SwiftPM target graph gate."""

from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "ci/check-package-target-graph.py"

spec = importlib.util.spec_from_file_location("package_target_graph", CHECKER)
if spec is None or spec.loader is None:
    raise SystemExit("unable to load package target graph checker")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def description() -> dict[str, object]:
    targets: list[dict[str, object]] = []
    for name, (path, dependencies) in module.EXPECTED.items():
        targets.append({"name": name, "path": path, "target_dependencies": sorted(dependencies)})
    return {"targets": targets}


def main() -> None:
    baseline = description()
    if module.validate(baseline):
        raise SystemExit("valid target graph unexpectedly failed")

    reverse_edge = description()
    core = next(target for target in reverse_edge["targets"] if target["name"] == "GlassCore")
    core["target_dependencies"] = ["GlassSpec", "GlassUI"]
    if not any("GlassCore internal dependencies" in failure for failure in module.validate(reverse_edge)):
        raise SystemExit("illegal Core-to-UI edge was not rejected")

    wrong_path = description()
    ui = next(target for target in wrong_path["targets"] if target["name"] == "GlassUI")
    ui["path"] = "Sources/Wrong"
    if not any("GlassUI path" in failure for failure in module.validate(wrong_path)):
        raise SystemExit("wrong GlassUI path was not rejected")

    print("SwiftPM target graph gate self-test passed.")


if __name__ == "__main__":
    main()
