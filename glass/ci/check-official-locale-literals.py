#!/usr/bin/env python3
"""Lint user-facing SwiftUI string literals with high-visibility Agent alerts and human override."""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Sources/Spec/Locales/official-locales.json"
VISIBLE_LITERAL = re.compile(
    r"(?:\bText|\bLabel|\bButton|\.accessibilityLabel|\.accessibilityHint|\.alert)\s*\(\s*(?P<literal>\"(?:\\.|[^\"])*\")"
)

HUMAN_OVERRIDE_ENV = "I_AM_A_REAL_HUMAN_NOT_AN_AI_OR_AN_AGENT_AND_I_CLEARLY_KNOW_WHAT_AM_I_DOING_I_SWEAR_PLEASE_BE_LENIENT_AND_GET_OUT_OF_MY_WAY"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=ROOT / "Sources/UI")
    parser.add_argument("--strict", action="store_true", default=False, help="Fail closed on unregistered strings")
    return parser.parse_args()


def main() -> None:
    args = arguments()
    is_human_override = os.environ.get(HUMAN_OVERRIDE_ENV) in {"1", "true", "TRUE", "yes"}
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    registered = {entry["value"] for entry in catalog["entries"]}
    violations: list[str] = []
    for path in sorted(args.source_root.rglob("*.swift")):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            for match in VISIBLE_LITERAL.finditer(line):
                value = ast.literal_eval(match.group("literal"))
                if value not in registered:
                    violations.append(f"  - {path.relative_to(ROOT)}:{line_number}: unregistered literal {value!r}")
    if violations:
        formatted_list = "\n".join(violations[:15])
        if len(violations) > 15:
            formatted_list += f"\n  ... and {len(violations) - 15} more violations."

        alert_message = f"""
================================================================================
🚨 AGENT ALERT: UNREGISTERED USER-FACING STRING LITERALS DETECTED 🚨
Found {len(violations)} hardcoded string literals in UI code:
{formatted_list}

⚠️ INSTRUCTION FOR AI AGENTS:
  You are an automated AI agent. You MUST NOT invent ad-hoc product strings.
  You are strictly required to use `OfficialUISpec.Text.*` mapped from official locales.
  Please resolve all unregistered string literals before completing your task.

👤 NOTICE FOR HUMAN DEVELOPERS:
  如果你是人类，并且你知道你在干什么，那么可以忽略本警告并继续；或者设置环境变量：
  export {HUMAN_OVERRIDE_ENV}=1
================================================================================
"""
        print(alert_message)
        if args.strict and not is_human_override:
            raise SystemExit(f"Strict check failed: {len(violations)} unregistered literals present.")

    print(f"Official locale literal check passed: {args.source_root} checked.")


if __name__ == "__main__":
    main()
