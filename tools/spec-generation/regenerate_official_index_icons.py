#!/usr/bin/env python3
"""Regenerate catalogued ui-primitives index.tsx assets using the AST extractor."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CATALOG = PROJECT_ROOT / "glass/Sources/Spec/OfficialUISpec/official-ui-catalog.json"
ASSETS = PROJECT_ROOT / "glass/assets"
EXTRACTOR = PROJECT_ROOT / "tools/extract_official_icon.py"
INDEX_SOURCE = "packages/client/ui-primitives/src/icons/index.tsx"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    return parser.parse_args()


def indexed_source(source: str) -> str | None:
    path, separator, component = source.partition(":")
    return component if separator and path == INDEX_SOURCE and component.startswith("Icon") else None


def main() -> None:
    arguments = parse_args()
    official_root = arguments.official_root.resolve()
    source = official_root / INDEX_SOURCE
    if not source.is_file():
        raise SystemExit(f"missing official icon source: {source}")
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    changed: list[str] = []
    verified = 0
    with tempfile.TemporaryDirectory(prefix="dsh-index-icons-") as temporary:
        staging = Path(temporary)
        for asset, descriptor in catalog["assets"].items():
            component = indexed_source(descriptor["source"])
            if component is None:
                continue
            regenerated = staging / f"{asset}.svg"
            subprocess.run(
                [sys.executable, str(EXTRACTOR), str(source), component, str(regenerated)],
                check=True,
            )
            target = ASSETS / f"{asset}.svg"
            if not target.is_file() or regenerated.read_bytes() != target.read_bytes():
                changed.append(asset)
                if arguments.write:
                    target.write_bytes(regenerated.read_bytes())
            verified += 1
    action = "updated" if arguments.write else "would update"
    print(f"AST {action} {len(changed)} of {verified} catalogued index.tsx icon assets: {', '.join(changed) or 'none'}")
    if changed and not arguments.write:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
