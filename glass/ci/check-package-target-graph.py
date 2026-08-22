#!/usr/bin/env python3
"""Validate the declared SwiftPM target graph from `swift package describe` JSON.

This gate intentionally inspects SwiftPM's resolved package metadata rather than
reading any project Swift source. It protects dependency direction in a way that
is falsifiable by a target-edge mutation yet invariant under implementation
refactors, per the PR #5 quality principles.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]

EXPECTED: dict[str, tuple[str, set[str]]] = {
    "GlassSpec": ("Sources/Spec", set()),
    "GlassPortableCore": ("Sources/PortableCore", set()),
    "GlassCore": ("Sources/Core", {"GlassSpec"}),
    "GlassUI": ("Sources/UI", {"GlassCore", "GlassSpec", "GlassPortableCore"}),
    "GlassSnapshot": ("Sources/Snapshot", {"GlassCore", "GlassSpec", "GlassUI"}),
    "GlassPluginPlane": ("Sources/PluginPlane", {"GlassCore", "GlassSpec"}),
    "DeepSeekHarnessGlassApp": ("Sources/App", {"GlassCore", "GlassSpec", "GlassUI", "GlassSnapshot"}),
}


def dependency_name(value: Any) -> str | None:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        for key in ("name", "target", "byName"):
            candidate = value.get(key)
            if isinstance(candidate, str):
                return candidate
    return None


def validate(description: dict[str, Any]) -> list[str]:
    targets = description.get("targets")
    if not isinstance(targets, list):
        return ["SwiftPM describe output has no target list"]

    by_name = {
        target.get("name"): target
        for target in targets
        if isinstance(target, dict) and isinstance(target.get("name"), str)
    }
    failures: list[str] = []
    for name, (expected_path, expected_dependencies) in EXPECTED.items():
        target = by_name.get(name)
        if target is None:
            failures.append(f"missing required target {name}")
            continue
        actual_path = target.get("path")
        if actual_path != expected_path:
            failures.append(f"{name} path is {actual_path!r}, expected {expected_path!r}")
        raw_dependencies = target.get("target_dependencies", target.get("dependencies", []))
        if not isinstance(raw_dependencies, list):
            failures.append(f"{name} dependency metadata is not a list")
            continue
        actual_dependencies = {item for item in (dependency_name(value) for value in raw_dependencies) if item is not None}
        internal_dependencies = actual_dependencies & set(EXPECTED)
        if internal_dependencies != expected_dependencies:
            failures.append(
                f"{name} internal dependencies are {sorted(internal_dependencies)!r}, "
                f"expected {sorted(expected_dependencies)!r}"
            )
    return failures


def package_description() -> dict[str, Any]:
    result = subprocess.run(
        ["swift", "package", "describe", "--type", "json"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"swift package describe failed:\n{result.stderr}")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit(f"swift package describe emitted invalid JSON: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit("swift package describe JSON root must be an object")
    return value


def main() -> None:
    failures = validate(package_description())
    if failures:
        raise SystemExit("SwiftPM target graph gate failed:\n" + "\n".join(f"- {failure}" for failure in failures))
    print("SwiftPM target graph gate passed: declared target paths and dependency direction are exact.")


if __name__ == "__main__":
    main()
