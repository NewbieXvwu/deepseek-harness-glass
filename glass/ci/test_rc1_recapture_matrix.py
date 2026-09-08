#!/usr/bin/env python3
"""Guard the structured rc.1 visual recertification matrix."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VISUAL_SCENES = ROOT / "glass/Sources/Spec/Fixtures/visual-scenes.json"
POLICY = ROOT / "glass/Sources/Spec/Fixtures/visual-validation-policy.json"

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

REQUIRED_EVIDENCE = {
    "official-screenshot",
    "native-screenshot",
    "paired-viewport",
    "difference-ledger",
    "post-fix-recapture",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> None:
    visual = json.loads(VISUAL_SCENES.read_text(encoding="utf-8"))
    policy = json.loads(POLICY.read_text(encoding="utf-8"))

    visual_entries = {
        scene.get("id"): scene
        for scene in visual.get("scenes", [])
        if isinstance(scene, dict) and isinstance(scene.get("id"), str)
    }
    missing_visual = REQUIRED_SCENES - visual_entries.keys()
    require(not missing_visual, f"visual-scene fixture is missing: {sorted(missing_visual)}")
    require(
        visual.get("officialSourceCommit") == policy.get("officialSourceCommit"),
        "visual scene fixture and validation policy use different official commits",
    )

    policies = policy.get("scenes", {})
    require(isinstance(policies, dict), "visual validation policy has no scene map")
    for scene in sorted(REQUIRED_SCENES):
        visual_entry = visual_entries[scene]
        evidence = visual_entry.get("requiredEvidence")
        require(isinstance(evidence, list), f"{scene} has no structured evidence list")
        missing_evidence = REQUIRED_EVIDENCE - set(evidence)
        require(not missing_evidence, f"{scene} is missing evidence: {sorted(missing_evidence)}")

        entry = policies.get(scene)
        require(isinstance(entry, dict), f"rc.1 recertification policy is missing scene: {scene}")
        require(entry.get("mode") == "report-only", f"{scene} must remain report-only until paired review closes")
        require(entry.get("mustEnforceBeforeTodoCompletion") is True, f"{scene} must block TODO completion until enforce")
        require(entry.get("humanReviewRequired") is True, f"{scene} must require human difference classification")
        criteria = entry.get("humanReviewCriteria")
        require(isinstance(criteria, list) and bool(criteria), f"{scene} has no human review criteria")

    print(f"rc.1 visual recertification matrix gate passed: {len(REQUIRED_SCENES)} structured scenes are review-blocking.")


if __name__ == "__main__":
    main()
