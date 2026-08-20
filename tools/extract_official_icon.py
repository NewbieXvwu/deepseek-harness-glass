#!/usr/bin/env python3
"""Extract one named icon SVG from pinned official TSX through a TypeScript AST."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def find_official_root(source: Path) -> Path:
    for parent in (source, *source.parents):
        if (parent / "package.json").is_file() and (parent / "packages").is_dir():
            return parent
    raise SystemExit(f"cannot find official repository root above {source}")


def node_for(official_root: Path) -> Path:
    configured = official_root / ".reference-node-path"
    if configured.is_file():
        candidate = Path(configured.read_text(encoding="utf-8").strip()) / "bin" / "node"
        if candidate.is_file():
            return candidate
    configured_environment = os.environ.get("NODE")
    return Path(configured_environment) if configured_environment else Path("node")


if len(sys.argv) not in (4, 5):
    raise SystemExit("usage: extract_official_icon.py SOURCE.tsx COMPONENT OUTPUT.svg [FILL]")

source_path = Path(sys.argv[1]).resolve()
component = sys.argv[2]
output_path = Path(sys.argv[3])
fill = sys.argv[4] if len(sys.argv) == 5 else "#0F1115"
project_root = Path(__file__).resolve().parents[1]
official_root = find_official_root(source_path)
node = node_for(official_root)
extractor = project_root / "tools" / "spec-generation" / "extract_official_icon_ast.mjs"

try:
    result = subprocess.run(
        [str(node), str(extractor), str(official_root), str(source_path), component, fill],
        check=True,
        text=True,
        capture_output=True,
    )
except subprocess.CalledProcessError as error:
    detail = error.stderr.strip() or error.stdout.strip() or str(error)
    raise SystemExit(f"AST icon extraction failed for {component}: {detail}") from error

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(result.stdout + "\n", encoding="utf-8")
