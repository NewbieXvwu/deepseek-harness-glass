#!/usr/bin/env python3
"""Fresh-generate the registered upstream SVG assets and compare app bytes."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = ROOT.parent
ASSET_DIR = ROOT / "assets"
ASSET_GENERATOR = PROJECT_ROOT / "tools/spec-generation/generate_official_assets.py"


def fail(message: str) -> None:
    print(f"D1 asset gate failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def node24() -> Path:
    configured = os.environ.get("NODE24_BIN")
    if configured:
        candidate = Path(configured) / "node"
        if candidate.is_file():
            return candidate
    configured = os.environ.get("DSH_NODE") or os.environ.get("NODE")
    return Path(configured) if configured else Path("node")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    official_root = parse_args().official_root.resolve()
    if not (official_root / "package.json").is_file():
        fail(f"source root has no package.json: {official_root}")

    with tempfile.TemporaryDirectory(prefix="dsh-assets-") as temporary:
        generated_dir = Path(temporary) / "assets"
        completed = subprocess.run(
            [
                sys.executable,
                str(ASSET_GENERATOR),
                "--official-root", str(official_root),
                "--output-dir", str(generated_dir),
                "--node", str(node24()),
            ],
            text=True,
            capture_output=True,
        )
        if completed.returncode != 0:
            fail(f"asset generation failed: {completed.stderr.strip() or completed.stdout.strip()}")

        generated = {path.name for path in generated_dir.glob("*.svg")}
        checked = {path.name for path in ASSET_DIR.glob("*.svg")}
        if generated != checked:
            fail(
                f"asset file set differs; extra={sorted(checked - generated)}, "
                f"missing={sorted(generated - checked)}"
            )
        for filename in sorted(generated):
            if (generated_dir / filename).read_bytes() != (ASSET_DIR / filename).read_bytes():
                fail(f"generated asset differs: {filename}")

    print(f"D1 asset gate passed: {len(generated)} SVG assets match fresh upstream extraction.")


if __name__ == "__main__":
    main()
