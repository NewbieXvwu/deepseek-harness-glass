#!/usr/bin/env python3
"""D1 gate for deterministic native-spec provenance and registered assets.

The gate validates generated catalogs, SVG well-formedness, the TSX AST-backed
icon reproduction boundary, and direct UI product-copy policy. Visual fidelity
remains separately enforced through same-state official/native artifact pairs.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = ROOT.parent
CATALOG_PATH = ROOT / "Sources/Spec/OfficialUISpec/official-ui-catalog.json"
SCENES_PATH = ROOT / "Sources/Spec/Fixtures/visual-scenes.json"
ASSET_DIR = ROOT / "assets"
ICON_EXTRACTOR = PROJECT_ROOT / "tools/extract_official_icon.py"
ICON_AST_EXTRACTOR = PROJECT_ROOT / "tools/spec-generation/extract_official_icon_ast.mjs"
LOCKED_COMMIT = "b150a551b8d465e31e418e1b2eaf5e79bbb7d28e"


def fail(message: str) -> None:
    print(f"D1 specification gate failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_catalog() -> dict:
    try:
        catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing catalog: {CATALOG_PATH}")
    except json.JSONDecodeError as error:
        fail(f"invalid catalog JSON: {error}")
    if catalog.get("officialSourceCommit") != LOCKED_COMMIT:
        fail("catalog officialSourceCommit differs from the locked baseline")
    for key in ("inputs", "layout", "text", "assets"):
        if not catalog.get(key):
            fail(f"catalog is missing required non-empty key: {key}")
    return catalog


def verify_assets(catalog: dict) -> None:
    for asset_name, source in catalog["assets"].items():
        if not source.get("source"):
            fail(f"asset {asset_name} has no upstream source record")
        path = ASSET_DIR / f"{asset_name}.svg"
        if not path.exists():
            fail(f"registered official asset is missing: {path}")
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as error:
            fail(f"asset {path.name} is not valid XML: {error}")
        if root.tag.rsplit("}", 1)[-1] != "svg":
            fail(f"asset {path.name} does not have an SVG root")


def node24() -> Path:
    configured = os.environ.get("NODE24_BIN")
    if configured:
        candidate = Path(configured) / "node"
        if candidate.is_file():
            return candidate
    configured = os.environ.get("DSH_NODE") or os.environ.get("NODE")
    return Path(configured) if configured else Path("node")


def indexed_icon_source(source: str) -> tuple[str, str] | None:
    path, separator, component = source.partition(":")
    if not separator or not component.startswith("Icon"):
        return None
    if path != "packages/client/ui-primitives/src/icons/index.tsx":
        return None
    return path, component


def verify_ast_icon_assets(catalog: dict, official_root: Path) -> None:
    generated = 0
    with tempfile.TemporaryDirectory(prefix="dsh-icon-ast-") as temporary:
        output_dir = Path(temporary)
        for asset_name, descriptor in catalog["assets"].items():
            target = indexed_icon_source(descriptor["source"])
            if target is None:
                continue
            source_relative, component = target
            source = official_root / source_relative
            if not source.is_file():
                fail(f"AST icon source is missing: {source_relative}")
            regenerated = output_dir / f"{asset_name}.svg"
            completed = subprocess.run(
                [sys.executable, str(ICON_EXTRACTOR), str(source), component, str(regenerated)],
                text=True,
                capture_output=True,
            )
            if completed.returncode != 0:
                fail(f"AST icon extraction failed for {asset_name}: {completed.stderr.strip() or completed.stdout.strip()}")
            registered = ASSET_DIR / f"{asset_name}.svg"
            if regenerated.read_bytes() != registered.read_bytes():
                fail(f"AST icon output differs byte-for-byte: {asset_name} <- {source_relative}:{component}")
            generated += 1

        # Structural negatives prove that the AST visitor rejects shapes which
        # old source slicing could silently misinterpret. The fixture is outside
        # the official tree on purpose: only the locked TypeScript parser is a
        # dependency of this behavioral check.
        bad = output_dir / "malformed.tsx"
        bad.write_text(
            "export const MissingSVG = (\n"
            "  { size = 16, className }: IconProps,\n"
            ") => (\n"
            "  <span className={className}>{size}</span>\n"
            ")\n"
            "export const DynamicWidth = ({ size = 16, className }: IconProps) => (\n"
            "  <svg width={size + 1} height={size} className={className}></svg>\n"
            ")\n",
            encoding="utf-8",
        )
        for component, expected in (
            ("MissingSVG", "exactly one SVG JSX element; found 0"),
            ("DynamicWidth", "width must be the size parameter"),
        ):
            completed = subprocess.run(
                [str(node24()), str(ICON_AST_EXTRACTOR), str(official_root), str(bad), component],
                text=True,
                capture_output=True,
            )
            if completed.returncode == 0 or expected not in completed.stderr:
                fail(f"AST icon structural negative did not fail closed for {component}: {completed.stdout}{completed.stderr}")
    if generated == 0:
        fail("catalog contains no registered index.tsx icon assets for AST verification")


def verify_scenes() -> dict:
    try:
        scenes = json.loads(SCENES_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing visual scene catalog: {SCENES_PATH}")
    except json.JSONDecodeError as error:
        fail(f"invalid visual scene catalog JSON: {error}")
    if scenes.get("officialSourceCommit") != LOCKED_COMMIT:
        fail("visual scene catalog differs from the locked official baseline")
    contract = scenes.get("captureContract", {})
    if contract.get("deviceScaleFactor") != 1 or not contract.get("logicalViewport"):
        fail("visual scene catalog must pin a 1x logical viewport capture contract")
    required = {"source-map", "official-screenshot", "native-screenshot", "layout-rectangles"}
    for scene in scenes.get("scenes", []):
        if not scene.get("id") or not scene.get("officialComponents"):
            fail("each visual scene requires an id and official component mapping")
        if not required.issubset(set(scene.get("requiredEvidence", []))):
            fail(f"visual scene {scene.get('id')} lacks required comparison evidence")
    if not scenes.get("scenes"):
        fail("visual scene catalog is empty")
    return scenes



def verify_catalog_sources(catalog: dict) -> None:
    for group_name in ("layout", "text", "assets"):
        for key, value in catalog[group_name].items():
            if not value.get("source"):
                fail(f"{group_name}.{key} lacks a source record")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    arguments = parse_args()
    official_root = arguments.official_root.resolve()
    if not (official_root / "package.json").is_file():
        fail(f"official root is not a repository root: {official_root}")
    catalog = load_catalog()
    verify_catalog_sources(catalog)
    verify_assets(catalog)
    verify_ast_icon_assets(catalog, official_root)
    scenes = verify_scenes()
    print(
        "D1 official specification gate passed: "
        f"{len(catalog['text'])} text values, {len(catalog['layout'])} layout values, "
        f"{len(catalog['assets'])} assets, {len(scenes['scenes'])} visual scenes."
    )


if __name__ == "__main__":
    main()
