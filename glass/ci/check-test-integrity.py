#!/usr/bin/env python3
"""Detect tautological / mirror tests in the XCTest suites (report-only).

Scans glass/Tests/**/*.swift for assertion shapes that can never fail or that
only re-assert production code copied into the test:

  A. XCTAssertTrue/False on a static constant member      (XCTAssertTrue(Foo.startsCollapsed))
  B. XCTAssertEqual(x, .case(x))                          self-construction tautology
  C. XCTAssertEqual(x, x)                                 trivially identical sides

These shapes are machine-detectable proxies for "the test proves nothing".
Actionable behavior tests (contains(...), computed values with inputs, throws,
etc.) are not flagged. Output is advisory; hook it into CI as a hard gate once
the backlog is cleaned.

Heuristic, not a parser: it may under- or over-report; every hit is printed
with the full statement so a human can dismiss false positives.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "glass" / "Tests"

# A: XCTAssertTrue(SomeType.member) / XCTAssertFalse(SomeType.member)
#    member must be a bare property reference (no call parens), type starts uppercase.
STATIC_MEMBER = re.compile(
    r"(?m)^\s*XCTAssert(?:True|False)\(\s*([A-Z][A-Za-z0-9_]*)\.([A-Za-z0-9_]+)\s*\)\s*$"
)

# B: XCTAssertEqual(name, .case(name))  -- enum case self-construction
SELF_CASE = re.compile(
    r"(?m)^\s*XCTAssertEqual\(\s*([a-zA-Z_][A-Za-z0-9_]*)\s*,\s*\.[A-Za-z0-9_]+\(\s*\1\s*\)\s*\)\s*$"
)

# C: XCTAssertEqual(name, name) -- trivially identical sides
IDENTICAL = re.compile(
    r"(?m)^\s*XCTAssertEqual\(\s*([a-zA-Z_][A-Za-z0-9_]*)\s*,\s*\1\s*\)\s*$"
)

# D: let name = <expr> ... XCTAssertEqual(name, <same expr>)  -- compare-against-own-construction
LET_DEF = re.compile(r"(?m)^\s*let\s+([a-zA-Z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$")
DEF_COMPARE = re.compile(
    r"(?m)^\s*XCTAssertEqual\(\s*([a-zA-Z_][A-Za-z0-9_]*)\s*,\s*(.+?)\s*\)\s*$"
)


def _normalize(expr: str) -> str:
    return "".join(expr.split())


# Enum-case construction style: `.case(arg)` or `Type.case(arg)`.
CASE_STYLE = re.compile(r"^(?:(?:[A-Z][A-Za-z0-9_]*)?\.)?[a-z][A-Za-z0-9_]*\(")


def scan_file(path: Path) -> list[tuple[str, int, str]]:
    hits: list[tuple[str, int, str]] = []
    text = path.read_text(encoding="utf-8")
    for pattern, label in ((STATIC_MEMBER, "A-static-member"), (SELF_CASE, "B-self-case"), (IDENTICAL, "C-identical-sides")):
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            statement = match.group(0).strip()
            hits.append((label, line, statement))

    # D: compare-against-own-construction. Only flag shapes that cannot be a
    # meaningful idempotence/determinism assertion:
    #   - pure reference/literal:  XCTAssertEqual(x, x-computed-identical)
    #   - enum-case construction:  let x = .case(a) ... XCTAssertEqual(x, .case(a))
    # Function-call re-evaluation (f(input) == f(input)) is legitimately used
    # for idempotence and is NOT flagged.
    definitions = {name: _normalize(expr) for name, expr in LET_DEF.findall(text)}
    for match in DEF_COMPARE.finditer(text):
        name, right = match.group(1), match.group(2)
        right_norm = _normalize(right)
        if name not in definitions:
            continue
        assigned = definitions[name]
        if right_norm == assigned:
            # identical text: flag only when no call parens are involved
            if "(" not in right_norm:
                line = text.count("\n", 0, match.start()) + 1
                hits.append(("D-assign-then-compare", line, match.group(0).strip()))
            continue
        # enum-case style allowing a dropped type prefix: `.case(a)` vs `Type.case(a)`
        if CASE_STYLE.match(right_norm) and assigned.endswith(right_norm):
            line = text.count("\n", 0, match.start()) + 1
            hits.append(("D-assign-then-compare", line, match.group(0).strip()))
    return hits


def main() -> int:
    total = 0
    per_file: list[tuple[str, int]] = []
    for path in sorted(TESTS.rglob("*.swift")):
        if "RecoveryGate" in path.name:
            continue
        hits = scan_file(path)
        if not hits:
            continue
        for label, line, statement in hits:
            print(f"{path.relative_to(ROOT)}:{line}: [{label}] {statement}")
        per_file.append((str(path.relative_to(ROOT)), len(hits)))
        total += len(hits)
    print()
    print(f"scanned {len(list(TESTS.rglob('*.swift')))} test files; {len(per_file)} files flagged; {total} tautological assertions")
    for name, count in sorted(per_file, key=lambda item: -item[1]):
        print(f"  {count:>3}  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())