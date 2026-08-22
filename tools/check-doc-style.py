#!/usr/bin/env python3
"""Gate AI-generated documentation style: flag filler/cliché phrasing.

Reviews are expensive because generated prose is verbose and repetitive.
This scanner fails on the worst offenders (empty signposting, redundant
hedging, generic AI filler) so a human only sees docs that already read
cleanly. Report-only by default; run with CI enforcement once the existing
tree is clean.

Filler lists are deliberately short and unambiguous to avoid false
positives on legitimate technical prose.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CN_FILLER = [
    "综上所述", "总而言之", "值得注意的是", "值得一提的是", "显而易见",
    "众所周知", "毋庸置疑", "由此可见", "不难发现", "众所周知的是",
    "下面我们将", "接下来我们将", "让我们来看看", "简单来说", "简而言之",
    "一言以蔽之", "这充分体现了", "这标志着", "此举不仅",
    "在本章中", "本章将", "本文档将", "我们注意到",
    "如上所述", "如前所述", "通过上述", "基于以上",
    "完成上述", "这项工作", "该任务的主要目的", "其核心思想是",
    "需要指出的是", "需要说明的是", "必须强调的是",
]
EN_FILLER = [
    "it is important to note", "it is worth noting", "note that it is",
    "it goes without saying", "needless to say", "as we all know",
    "in conclusion", "to summarize", "let's take a look", "let us take a look",
    "in this chapter", "in this section we", "we will now",
    "as mentioned above", "as previously mentioned", "as we can see",
    "as you can see", "basically", "essentially", "in a nutshell",
    "the main idea is", "the key takeaway", "all in all",
    "last but not least", "first and foremost",
]

# Redundant comparison constructions in prose (AI-typical).
REDUNDANT_RE = [
    re.compile(r"\b(?:successfully|effectively|significantly) (?:implemented|addressed|fixed|resolved|achieved)\b", re.I),
    re.compile(r"\b(?:ensure|guarantee)[sd]? that the (?:behavior|behaviour|logic|implementation) (?:is|remains) (?:correct|consistent|correct and consistent)\b", re.I),
]

LONG_SENTENCE_LIMIT = 160  # chars per line — generated prose loves run-ons


def scan_file(path: Path) -> list[tuple[str, int, str]]:
    hits: list[tuple[str, int, str]] = []
    text = path.read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        lower = stripped.lower()
        for filler in CN_FILLER:
            if filler in stripped:
                hits.append(("filler-cn", lineno, filler))
        for filler in EN_FILLER:
            if filler in lower:
                hits.append(("filler-en", lineno, filler))
        for pattern in REDUNDANT_RE:
            if pattern.search(stripped):
                hits.append(("redundant", lineno, pattern.pattern))
        if len(stripped) > LONG_SENTENCE_LIMIT:
            if "|" in stripped and stripped.count("|") >= 2:
                continue  # markdown table row — expected to stay single-line
            if stripped.startswith("[") and "](http" in stripped:
                continue  # plain reference/citation line
            if stripped.startswith("```"):
                continue
            hits.append(("long-line", lineno, f"{len(stripped)} chars"))
    return hits


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--fail", action="store_true", help="exit 1 when filler or long lines remain")
    args = parser.parse_args()

    total = 0
    failures = 0
    for path in sorted(ROOT.rglob("*.md")):
        if any(part in {".git", ".build", "node_modules", ".reference"} for part in path.parts):
            continue
        hits = scan_file(path)
        if not hits:
            continue
        print(f"== {path.relative_to(ROOT)}")
        for kind, lineno, detail in hits:
            print(f"   {lineno}: [{kind}] {detail}")
            total += 1
            if args.fail:
                failures += 1
    print()
    print(f"doc-style: {total} filler/verbose hits across tracked Markdown")
    if args.fail and failures:
        print("doc-style gate failed: generate prose should be concise and single-line-bounded")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())