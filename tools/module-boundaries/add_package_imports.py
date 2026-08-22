#!/usr/bin/env python3
"""Add conditional testable module imports required by the SwiftPM boundary build."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2] / "glass" / "Sources"
IMPORT_BLOCKS = {
    "UI": "#if DEEPSEEK_HARNESS_PACKAGE\n@testable import GlassCore\n@testable import GlassSpec\n#endif\n",
    "Snapshot": "#if DEEPSEEK_HARNESS_PACKAGE\n@testable import GlassCore\n@testable import GlassSpec\n@testable import GlassUI\n#endif\n",
    "App": "#if DEEPSEEK_HARNESS_PACKAGE\n@testable import GlassCore\n@testable import GlassSpec\n@testable import GlassUI\n@testable import GlassSnapshot\n#endif\n",
    "Core": "#if DEEPSEEK_HARNESS_PACKAGE\n@testable import GlassSpec\n#endif\n",
}


def find_insertion_index(lines: list[str]) -> int:
    """Find the insertion index for package imports.

    Skips leading empty lines, line/block comments (//, /* ... */),
    and compiler directive lines (#if, #elseif, #else, #endif).
    """
    insert_at = 0
    in_block_comment = False
    while insert_at < len(lines):
        line = lines[insert_at]
        stripped = line.strip()

        if in_block_comment:
            if "*/" in stripped:
                in_block_comment = False
            insert_at += 1
            continue

        if stripped == "":
            insert_at += 1
            continue

        if stripped.startswith("/*"):
            if "*/" not in stripped:
                in_block_comment = True
            insert_at += 1
            continue

        if stripped.startswith("//"):
            insert_at += 1
            continue

        if stripped.startswith(("#if", "#elseif", "#else", "#endif")):
            insert_at += 1
            continue

        break

    return insert_at


def main() -> None:
    changed = 0
    for layer, block in IMPORT_BLOCKS.items():
        for path in sorted((ROOT / layer).rglob("*.swift")):
            source = path.read_text(encoding="utf-8")
            if "DEEPSEEK_HARNESS_PACKAGE" in source:
                continue
            lines = source.splitlines(keepends=True)
            insert_at = find_insertion_index(lines)
            lines.insert(insert_at, block)
            path.write_text("".join(lines), encoding="utf-8")
            changed += 1
    print(f"Added conditional package imports to {changed} source files.")


if __name__ == "__main__":
    main()
