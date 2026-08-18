#!/usr/bin/env python3
"""Reject unregistered direct user-facing SwiftUI string literals."""

from __future__ import annotations

import argparse
import ast
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Sources/Spec/Locales/official-locales.json"
VISIBLE_LITERAL = re.compile(
    r"(?:\bText|\bLabel|\bButton|\.accessibilityLabel|\.accessibilityHint|\.alert)\s*\(\s*(?P<literal>\"(?:\\.|[^\"])*\")"
)


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=ROOT / "Sources/UI")
    return parser.parse_args()


def main() -> None:
    args = arguments()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    registered = {entry["value"] for entry in catalog["entries"]}
    violations: list[str] = []
    for path in sorted(args.source_root.rglob("*.swift")):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            for match in VISIBLE_LITERAL.finditer(line):
                value = ast.literal_eval(match.group("literal"))
                if value not in registered:
                    violations.append(f"{path}:{line_number}: unregistered visible literal {value!r}")
    if violations:
        raise SystemExit("\n".join(violations))
    print(f"Official locale literal lint passed: {args.source_root} has no unregistered direct visible strings.")


if __name__ == "__main__":
    main()
