#!/usr/bin/env python3
"""Fail on broken repository-relative Markdown links without external network access."""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
# Destination allows balanced one-level parentheses (e.g. Wikipedia titles).
LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^()\s]+(?:\([^()]*\)[^()\s]*)*)\)")
# Fenced code spans/tables are skipped: their content is not a real link.
FENCE_RE = re.compile(r"```.*?```", re.DOTALL)
SKIP_PREFIXES = ("http://", "https://", "mailto:", "tel:", "#")


def local_target(raw: str) -> str | None:
    value = raw.strip()
    if value.startswith("<") and value.endswith(">"):
        value = value[1:-1]
    if not value or value.startswith(SKIP_PREFIXES):
        return None
    value = value.split("#", 1)[0].split("?", 1)[0].strip()
    return unquote(value) or None


def main() -> int:
    failures: list[str] = []
    for markdown in ROOT.rglob("*.md"):
        if any(part in {".git", ".build", ".reference", "node_modules"} for part in markdown.parts):
            continue
        text = markdown.read_text(encoding="utf-8")
        text = FENCE_RE.sub("", text)
        for match in LINK_RE.finditer(text):
            target = local_target(match.group(1))
            if target is None:
                continue
            resolved = (markdown.parent / target).resolve()
            if not resolved.exists() or ROOT not in resolved.parents and resolved != ROOT:
                line = text.count("\n", 0, match.start()) + 1
                failures.append(f"{markdown.relative_to(ROOT)}:{line}: broken local link {target!r}")
    if failures:
        print("Markdown link check failed:", file=sys.stderr)
        print("\n".join(f"- {item}" for item in failures), file=sys.stderr)
        return 1
    print("Markdown link check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
