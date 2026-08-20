#!/usr/bin/env python3
"""Validate the locked upstream interaction-scene directory used for visual capture."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCENES = ROOT / "Sources/Spec/Fixtures/official-interaction-scenes.json"
EXPECTED_COMMIT = "141eb6fef83422698aef7a981029e843e8161534"
REQUIRED_SCENES = {
    "startup-empty-hero",
    "welcome-no-workspace-light",
    "jobs-expanded-light",
    "empty-session-workspace",
    "streaming-answer",
    "tool-call-details",
    "approval-composer-light",
    "question-composer-light",
    "queue-actions-narrow",
    "settings-general-zh",
    "dark-theme-cascade",
    "sidebar-rail-narrow-light",
    "details-closed-and-reopen",
    "error-recovery-reload",
}
REQUIRED_FIELDS = {
    "id", "officialTest", "sourceLines", "hostFixture", "viewport", "colorScheme",
    "accessibility", "actions", "expectedVisibleText", "expectedLayoutTree",
    "ariaBaseline", "screenshotBaseline", "nativeEntry",
}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    return parser.parse_args()


def upstream_path(root: Path, path: str) -> None:
    if path.startswith("apps/") and not (root / path).is_file():
        raise SystemExit(f"registered upstream scene path does not exist: {path}")


def main() -> None:
    args = arguments()
    document = json.loads(SCENES.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != 1 or document.get("officialSourceCommit") != EXPECTED_COMMIT:
        raise SystemExit("official interaction scene catalog has an invalid schema or source commit")
    contract = document.get("captureContract")
    if not isinstance(contract, dict) or contract.get("deviceScaleFactor") != 1 or not isinstance(contract.get("accessibility"), dict):
        raise SystemExit("official interaction catalog must pin a 1x accessibility capture contract")
    scenes = document.get("scenes")
    if not isinstance(scenes, list):
        raise SystemExit("official interaction scene catalog must contain a scene array")
    ids: set[str] = set()
    for scene in scenes:
        if not isinstance(scene, dict):
            raise SystemExit("official interaction scene must be an object")
        missing = REQUIRED_FIELDS - set(scene)
        if missing:
            raise SystemExit(f"scene {scene.get('id', '<unknown>')} is missing fields: {', '.join(sorted(missing))}")
        identifier = scene["id"]
        if not isinstance(identifier, str) or identifier in ids:
            raise SystemExit(f"scene has invalid or duplicate id: {identifier!r}")
        ids.add(identifier)
        upstream_path(args.official_root, scene["officialTest"])
        upstream_path(args.official_root, scene["ariaBaseline"])
        fixture = scene["hostFixture"]
        if not isinstance(fixture, dict) or not fixture.get("kind") or not fixture.get("workspace"):
            raise SystemExit(f"scene {identifier} has an incomplete Host fixture contract")
        replay = fixture.get("replayFixture")
        if replay is not None:
            if not isinstance(replay, str):
                raise SystemExit(f"scene {identifier} has a non-string replayFixture")
            upstream_path(args.official_root, replay)
        viewport = scene["viewport"]
        if not isinstance(viewport, dict) or not all(isinstance(viewport.get(key), int) and viewport[key] > 0 for key in ("width", "height")):
            raise SystemExit(f"scene {identifier} has an invalid viewport")
        if scene["colorScheme"] not in {"light", "dark"}:
            raise SystemExit(f"scene {identifier} has an invalid colorScheme")
        accessibility = scene["accessibility"]
        if not isinstance(accessibility, dict) or not all(isinstance(accessibility.get(key), bool) for key in ("reduceTransparency", "increaseContrast", "reduceMotion", "keyboardOnly")):
            raise SystemExit(f"scene {identifier} has an incomplete accessibility contract")
        for list_field in ("actions", "expectedVisibleText", "expectedLayoutTree"):
            value = scene[list_field]
            if not isinstance(value, list) or not value or not all(isinstance(item, str) and item for item in value):
                raise SystemExit(f"scene {identifier} has an empty or invalid {list_field}")
        if not isinstance(scene["screenshotBaseline"], str) or not scene["screenshotBaseline"].endswith(".png"):
            raise SystemExit(f"scene {identifier} lacks a PNG screenshot baseline contract")
    missing_scenes = REQUIRED_SCENES - ids
    if missing_scenes:
        raise SystemExit("interaction scene catalog lacks required coverage: " + ", ".join(sorted(missing_scenes)))
    print(f"Official interaction scene gate passed: {len(scenes)} scenarios with {len(ids & REQUIRED_SCENES)} required coverage entries.")


if __name__ == "__main__":
    main()
