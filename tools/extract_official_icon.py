#!/usr/bin/env python3
"""Extract one named icon SVG from the pinned official ui-primitives TSX source."""
from __future__ import annotations

import re
import sys
from pathlib import Path

if len(sys.argv) not in (4, 5):
    raise SystemExit("usage: extract_official_icon.py SOURCE.tsx COMPONENT OUTPUT.svg [FILL]")

source_path = Path(sys.argv[1])
component = sys.argv[2]
output_path = Path(sys.argv[3])
fill = sys.argv[4] if len(sys.argv) == 5 else "#0F1115"
source = source_path.read_text(encoding="utf-8")

start_match = re.search(rf"export const {re.escape(component)} = \(\{{ size = (\d+), className \}}: IconProps\) => \(", source)
if start_match is None:
    raise SystemExit(f"component not found: {component}")

fragment = source[start_match.end():]
svg_start = fragment.find("<svg")
svg_end = fragment.find("</svg>")
if svg_start < 0 or svg_end < 0:
    raise SystemExit(f"SVG fragment not found: {component}")
svg = fragment[svg_start:svg_end + len("</svg>")]
size = start_match.group(1)
svg = svg.replace("width={size}", f'width="{size}"').replace("height={size}", f'height="{size}"')
svg = re.sub(r'\sclassName=\{className\}', "", svg)
svg = svg.replace("fill=\"currentColor\"", f"fill=\"{fill}\"")
svg = svg.replace("fillRule=", "fill-rule=").replace("clipRule=", "clip-rule=").replace("clipPath=", "clip-path=")
svg = re.sub(r"([A-Za-z][-A-Za-z0-9:]*)=\{(\d+)\}", r'\1="\2"', svg)
svg = svg.replace("aria-hidden", "aria-hidden")
output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(svg + "\n", encoding="utf-8")
