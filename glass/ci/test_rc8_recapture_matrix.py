#!/usr/bin/env python3
"""Guard the RC8 T5/T7 recertification screenshot matrix wiring.

The matrix is intentionally a source-level contract: each named scene must be
registered by the authoritative visual scene fixture, have a review-only policy
that blocks TODO completion until upgraded, be emitted by the official capture
script, and be mentioned by the native workflow's artifact/comparison paths.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VISUAL_SCENES = ROOT / "glass/Sources/Spec/Fixtures/visual-scenes.json"
POLICY = ROOT / "glass/Sources/Spec/Fixtures/visual-validation-policy.json"
CAPTURE = ROOT / "tools/reference-capture/capture-official-welcome.e2e.ts"
WORKFLOW = ROOT / ".github/workflows/native-ui.yml"

# T5 (window/shell/material/accessibility) plus T7.3 (workspace management)
# must be recaptured against the locked RC8 WebUI before their TODO rows may
# close. Conversation/tooling scenes belong to later T8/T9 renderer work.
CAPTURE_MARKERS = {
    "welcome-no-workspace-light": "`welcome-no-workspace-${colorScheme}`",
    "welcome-no-workspace-dark": "`welcome-no-workspace-${colorScheme}`",
    "jobs-expanded-light": "`jobs-expanded-${colorScheme}`",
    "jobs-expanded-dark": "`jobs-expanded-${colorScheme}`",
    "sidebar-rail-narrow-light": "`sidebar-rail-narrow-${colorScheme}`",
    "sidebar-rail-narrow-dark": "`sidebar-rail-narrow-${colorScheme}`",
    "workspace-search-light": "`workspace-search-${colorScheme}`",
    "workspace-search-dark": "`workspace-search-${colorScheme}`",
    "workspace-rename-light": "`${kind}-${colorScheme}`",
    "workspace-rename-dark": "`${kind}-${colorScheme}`",
    "session-rename-light": "`${kind}-${colorScheme}`",
    "session-rename-dark": "`${kind}-${colorScheme}`",
    "workspace-delete-light": "`${kind}-${colorScheme}`",
    "workspace-delete-dark": "`${kind}-${colorScheme}`",
    "approval-composer-light": "'approval-composer-light'",
    "question-composer-light": "'question-composer-light'",
}

REQUIRED_SCENES = frozenset({
    "welcome-no-workspace-light",
    "welcome-no-workspace-dark",
    "jobs-expanded-light",
    "jobs-expanded-dark",
    "sidebar-rail-narrow-light",
    "sidebar-rail-narrow-dark",
    "approval-composer-light",
    "question-composer-light",
    "workspace-search-light",
    "workspace-search-dark",
    "workspace-rename-light",
    "workspace-rename-dark",
    "session-rename-light",
    "session-rename-dark",
    "workspace-delete-light",
    "workspace-delete-dark",
})


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> None:
    visual = json.loads(VISUAL_SCENES.read_text(encoding="utf-8"))
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    capture = CAPTURE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    visual_ids = {scene["id"] for scene in visual["scenes"]}
    require(REQUIRED_SCENES <= visual_ids, f"visual-scene fixture is missing: {sorted(REQUIRED_SCENES - visual_ids)}")
    require(
        visual["officialSourceCommit"] == policy["officialSourceCommit"],
        "visual scene fixture and validation policy use different official commits",
    )

    policies = policy["scenes"]
    for scene in sorted(REQUIRED_SCENES):
        entry = policies.get(scene)
        require(entry is not None, f"RC8 recertification policy is missing scene: {scene}")
        require(entry.get("mode") == "report-only", f"{scene} must remain report-only until paired review closes")
        require(entry.get("mustEnforceBeforeTodoCompletion") is True, f"{scene} must block TODO completion until enforce")
        require(entry.get("humanReviewRequired") is True, f"{scene} must require human difference classification")
        require(bool(entry.get("humanReviewCriteria")), f"{scene} has no human review criteria")
        marker = CAPTURE_MARKERS[scene]
        require(marker in capture, f"official capture script does not emit or name RC8 scene: {scene}")
        require(scene in workflow, f"native workflow does not assert or compare RC8 scene: {scene}")

    print(f"RC8 recertification matrix gate passed: {len(REQUIRED_SCENES)} T5/T7 scenes are wired.")


if __name__ == "__main__":
    main()
