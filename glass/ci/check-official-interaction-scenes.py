#!/usr/bin/env python3
"""Validate the locked upstream interaction-scene directory used for visual capture."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parent
SCENES = ROOT / "Sources/Spec/Fixtures/official-interaction-scenes.json"
CUT18_SCENES = ROOT / "Sources/Spec/Fixtures/official-interaction-scenes-cut1.8.json"
VISUAL_POLICY = ROOT / "Sources/Spec/Fixtures/visual-validation-policy.json"
EXPECTED_COMMIT = "a66e4702047846cdaa10c66c9d3df3951f5ea70d"
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
    "models-settings-provider-zh",
    "plugins-settings-zh",
    "settings-font-size-zh",
    "queued-image-light",
    "history-image-lightbox",
    "markdown-wide-table-scaling",
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


def registered_path(root: Path, path: str, require_artifact: bool) -> None:
    parts = Path(path).parts
    if not parts:
        raise SystemExit(f"empty registered scene path: {path!r}")

    first = parts[0]
    if first in ("apps", "packages", "snapshots"):
        target = root / path
        if not target.is_file():
            raise SystemExit(f"registered upstream scene path does not exist under official root: {path}")
    elif first == "artifacts" and len(parts) >= 2 and parts[1] == "official-webui":
        # Catalog-only scenes may be registered before their visual recapture is
        # complete. Once a scene also has a visual-validation policy, it belongs
        # to the paired artifact pipeline and its registered files must exist on
        # macOS after the baseline cache/capture step has populated the root.
        artifact_root = REPO_ROOT / "artifacts" / "official-webui"
        if require_artifact and artifact_root.exists() and not (REPO_ROOT / path).is_file():
            raise SystemExit(f"registered paired official WebUI artifact does not exist: {path}")
    else:
        raise SystemExit(f"unrecognized or unsupported path root prefix for registered scene path: {path}")


def main() -> None:
    args = arguments()
    policy = json.loads(VISUAL_POLICY.read_text(encoding="utf-8"))
    if policy.get("schemaVersion") != 1 or policy.get("officialSourceCommit") != EXPECTED_COMMIT:
        raise SystemExit("visual validation policy has an invalid schema or source commit")
    policy_scenes = policy.get("scenes")
    if not isinstance(policy_scenes, dict):
        raise SystemExit("visual validation policy must contain a scene map")
    if "rc.2" in json.dumps(policy_scenes).lower():
        raise SystemExit("visual validation policy still references rc.2 as active review evidence")

    documents = [
        json.loads(SCENES.read_text(encoding="utf-8")),
        json.loads(CUT18_SCENES.read_text(encoding="utf-8")),
    ]
    for document in documents:
        if document.get("schemaVersion") != 1 or document.get("officialSourceCommit") != EXPECTED_COMMIT:
            raise SystemExit("official interaction scene catalog has an invalid schema or source commit")
    contract = documents[0].get("captureContract")
    if not isinstance(contract, dict) or contract.get("deviceScaleFactor") != 1 or not isinstance(contract.get("accessibility"), dict):
        raise SystemExit("official interaction catalog must pin a 1x accessibility capture contract")
    scenes: list[object] = []
    for document in documents:
        entries = document.get("scenes")
        if not isinstance(entries, list):
            raise SystemExit("official interaction scene catalog must contain a scene array")
        scenes.extend(entries)
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
        paired_visual_scene = identifier in policy_scenes
        registered_path(args.official_root, scene["officialTest"], paired_visual_scene)
        registered_path(args.official_root, scene["ariaBaseline"], paired_visual_scene)
        fixture = scene["hostFixture"]
        if not isinstance(fixture, dict) or not fixture.get("kind") or not fixture.get("workspace"):
            raise SystemExit(f"scene {identifier} has an incomplete Host fixture contract")
        replay = fixture.get("replayFixture")
        if replay is not None:
            if not isinstance(replay, str):
                raise SystemExit(f"scene {identifier} has a non-string replayFixture")
            registered_path(args.official_root, replay, paired_visual_scene)
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
        registered_path(args.official_root, scene["screenshotBaseline"], paired_visual_scene)
    missing_scenes = REQUIRED_SCENES - ids
    if missing_scenes:
        raise SystemExit("interaction scene catalog lacks required coverage: " + ", ".join(sorted(missing_scenes)))

    deliverables = policy_scenes.get("deliverables-light")
    if not isinstance(deliverables, dict) or deliverables.get("viewport") != {"width": 780, "height": 900, "devicePixelRatio": 1}:
        raise SystemExit("visual validation policy lacks the rc.1 780px deliverables contract")
    criteria = deliverables.get("humanReviewCriteria")
    if not isinstance(criteria, list) or not criteria or not all(isinstance(c, str) and c for c in criteria):
        raise SystemExit("visual validation policy has an empty or invalid humanReviewCriteria list for deliverables")

    print(f"Official interaction scene gate passed: {len(scenes)} scenarios with {len(ids & REQUIRED_SCENES)} required coverage entries.")


if __name__ == "__main__":
    main()
