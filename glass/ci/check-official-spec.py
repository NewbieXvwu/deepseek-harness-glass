#!/usr/bin/env python3
"""D1 gate for current rc.1 UI-spec provenance and fresh-generated assets.

Locale and theme catalogs have dedicated AST/CSS regeneration gates in the same
CI job. This gate binds those current structured catalogs to the rc.1 source,
re-executes the upstream computeColumns implementation for layout drift, and
fresh-extracts every registered SVG from rc.1 TSX before byte-comparing it with
the app asset directory. The historical rc.2 monolithic catalog is retained as
audit evidence only and is never counted as a current specification input.
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
EXPECTED_COMMIT = "a66e4702047846cdaa10c66c9d3df3951f5ea70d"
LEGACY_COMMIT = "b150a551b8d465e31e418e1b2eaf5e79bbb7d28e"

LEGACY_CATALOG_PATH = ROOT / "Sources/Spec/OfficialUISpec/official-ui-catalog.rc2-historical.json"
ASSET_MANIFEST_PATH = ROOT / "Sources/Spec/OfficialUISpec/official-assets.json"
LOCALES_PATH = ROOT / "Sources/Spec/Locales/official-locales.json"
TOKENS_PATH = ROOT / "Sources/Spec/Tokens/official-theme-tokens.json"
LAYOUT_PATH = ROOT / "Sources/Spec/Fixtures/official-column-layout-fixtures.json"
SCENES_PATH = ROOT / "Sources/Spec/Fixtures/visual-scenes.json"
ASSET_DIR = ROOT / "assets"

ASSET_GENERATOR = PROJECT_ROOT / "tools/spec-generation/generate_official_assets.py"
LAYOUT_GENERATOR = PROJECT_ROOT / "tools/spec-generation/generate_official_column_layout_fixtures.ts"
ICON_AST_EXTRACTOR = PROJECT_ROOT / "tools/spec-generation/extract_official_icon_ast.mjs"
MAP_AST_EXTRACTOR = PROJECT_ROOT / "tools/spec-generation/extract_official_map_svg_ast.mjs"


def fail(message: str) -> None:
    print(f"D1 specification gate failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path, label: str) -> dict:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing {label}: {path}")
    except json.JSONDecodeError as error:
        fail(f"invalid {label} JSON: {error}")
    if not isinstance(document, dict):
        fail(f"{label} must be a JSON object")
    return document


def sha256_revision(value: object) -> bool:
    return isinstance(value, str) and value.startswith("sha256:") and len(value) == 71


def node24() -> Path:
    configured = os.environ.get("NODE24_BIN")
    if configured:
        candidate = Path(configured) / "node"
        if candidate.is_file():
            return candidate
    configured = os.environ.get("DSH_NODE") or os.environ.get("NODE")
    return Path(configured) if configured else Path("node")


def verify_current_catalog_provenance() -> tuple[int, int, int]:
    locales = load_json(LOCALES_PATH, "official locale catalog")
    tokens = load_json(TOKENS_PATH, "official theme catalog")
    layout = load_json(LAYOUT_PATH, "official layout fixtures")

    if locales.get("sourceCommit") != EXPECTED_COMMIT:
        fail("official locale catalog is not bound to rc.1")
    if not sha256_revision(locales.get("localeRevision")) or not sha256_revision(locales.get("sourceInputRevision")):
        fail("official locale catalog lacks current SHA-256 revisions")
    locale_entries = locales.get("entries")
    if not isinstance(locale_entries, list) or not locale_entries:
        fail("official locale catalog has no entries")

    if tokens.get("sourceCommit") != EXPECTED_COMMIT:
        fail("official theme catalog is not bound to rc.1")
    if not sha256_revision(tokens.get("themeRevision")) or not sha256_revision(tokens.get("sourceInputRevision")):
        fail("official theme catalog lacks current SHA-256 revisions")
    theme_tokens = tokens.get("tokens")
    if not isinstance(theme_tokens, list) or not theme_tokens:
        fail("official theme catalog has no tokens")

    if layout.get("sourceCommit") != EXPECTED_COMMIT:
        fail("official layout fixtures are not bound to rc.1")
    source = layout.get("source")
    if not isinstance(source, dict) or source.get("path") != "packages/client/ui-layout/src/client/columns.ts":
        fail("official layout fixtures lack the rc.1 computeColumns source record")
    source_hash = source.get("sha256")
    if not isinstance(source_hash, str) or len(source_hash) != 64:
        fail("official layout fixtures lack a source SHA-256")
    fixtures = layout.get("fixtures")
    if not isinstance(fixtures, list) or len(fixtures) < 32:
        fail("official layout fixture boundary set is incomplete")

    legacy = load_json(LEGACY_CATALOG_PATH, "historical rc.2 UI catalog")
    if legacy.get("officialSourceCommit") != LEGACY_COMMIT:
        fail("historical rc.2 UI catalog provenance changed")

    return len(locale_entries), len(theme_tokens), len(fixtures)


def verify_layout_fresh_extraction(official_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="dsh-layout-rc1-") as temporary:
        regenerated = Path(temporary) / "official-column-layout-fixtures.json"
        completed = subprocess.run(
            [
                str(node24()), "--experimental-strip-types", str(LAYOUT_GENERATOR),
                "--official-root", str(official_root),
                "--output", str(regenerated),
            ],
            cwd=LAYOUT_GENERATOR.parent,
            text=True,
            capture_output=True,
        )
        if completed.returncode != 0:
            fail(f"rc.1 computeColumns fixture regeneration failed: {completed.stderr.strip() or completed.stdout.strip()}")
        if regenerated.read_bytes() != LAYOUT_PATH.read_bytes():
            fail("official column layout fixtures drifted from fresh rc.1 computeColumns output")


def verify_asset_manifest_shape(manifest: dict) -> list[dict]:
    if manifest.get("schemaVersion") != 1 or manifest.get("sourceCommit") != EXPECTED_COMMIT:
        fail("official asset manifest has an invalid schema or source commit")
    if not sha256_revision(manifest.get("sourceInputRevision")) or not sha256_revision(manifest.get("assetSetRevision")):
        fail("official asset manifest lacks deterministic source/set revisions")
    generator = manifest.get("generator")
    if not isinstance(generator, dict) or generator.get("name") != "generate_official_assets.py":
        fail("official asset manifest lacks generator provenance")
    assets = manifest.get("assets")
    if not isinstance(assets, list) or not assets:
        fail("official asset manifest is empty")

    names: set[str] = set()
    files: set[str] = set()
    for entry in assets:
        if not isinstance(entry, dict):
            fail("official asset manifest entry must be an object")
        name = entry.get("name")
        filename = entry.get("file")
        if not isinstance(name, str) or not name or name in names:
            fail(f"invalid or duplicate asset name: {name!r}")
        if filename != f"{name}.svg" or filename in files:
            fail(f"asset {name} has an invalid or duplicate target file")
        source = entry.get("source")
        if not isinstance(source, dict) or source.get("commit") != EXPECTED_COMMIT:
            fail(f"asset {name} is not bound to the rc.1 source commit")
        if not isinstance(source.get("path"), str) or not source.get("path"):
            fail(f"asset {name} has no upstream TSX path")
        blob = source.get("gitBlobSha1")
        if not isinstance(blob, str) or len(blob) != 40 or any(character not in "0123456789abcdef" for character in blob):
            fail(f"asset {name} has no upstream Git blob content hash")
        selector = entry.get("astSelector")
        if not isinstance(selector, dict) or selector.get("kind") not in {"component-svg", "component-inner", "map-entry-svg"} or not selector.get("value"):
            fail(f"asset {name} lacks an AST selector")
        names.add(name)
        files.add(filename)

    checked_files = {path.name for path in ASSET_DIR.glob("*.svg")}
    if checked_files != files:
        added = sorted(checked_files - files)
        missing = sorted(files - checked_files)
        fail(f"asset manifest/file-set drift; unregistered={added}, missing={missing}")
    return assets


def verify_assets_fresh_extraction(manifest: dict, official_root: Path) -> None:
    assets = verify_asset_manifest_shape(manifest)
    for entry in assets:
        path = ASSET_DIR / entry["file"]
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as error:
            fail(f"asset {path.name} is not valid XML: {error}")
        if root.tag.rsplit("}", 1)[-1] != "svg":
            fail(f"asset {path.name} does not have an SVG root")

    with tempfile.TemporaryDirectory(prefix="dsh-assets-rc1-") as temporary:
        temporary_root = Path(temporary)
        output_dir = temporary_root / "assets"
        regenerated_manifest = temporary_root / "official-assets.json"
        completed = subprocess.run(
            [
                sys.executable, str(ASSET_GENERATOR),
                "--official-root", str(official_root),
                "--output-dir", str(output_dir),
                "--manifest-output", str(regenerated_manifest),
                "--node", str(node24()),
            ],
            text=True,
            capture_output=True,
        )
        if completed.returncode != 0:
            fail(f"official asset regeneration failed: {completed.stderr.strip() or completed.stdout.strip()}")
        if regenerated_manifest.read_bytes() != ASSET_MANIFEST_PATH.read_bytes():
            fail("official asset manifest drifted from fresh rc.1 TSX extraction")
        for entry in assets:
            filename = entry["file"]
            regenerated = output_dir / filename
            registered = ASSET_DIR / filename
            if not regenerated.is_file():
                fail(f"asset generator omitted registered file: {filename}")
            if regenerated.read_bytes() != registered.read_bytes():
                fail(f"fresh rc.1 asset output differs byte-for-byte: {filename}")


def verify_ast_structural_negatives(official_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="dsh-asset-ast-negatives-") as temporary:
        root = Path(temporary)
        malformed_icon = root / "malformed-icon.tsx"
        malformed_icon.write_text(
            "export const MissingSVG = ({ size = 16, className }: IconProps) => (\n"
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
                [str(node24()), str(ICON_AST_EXTRACTOR), str(official_root), str(malformed_icon), component],
                text=True,
                capture_output=True,
            )
            if completed.returncode == 0 or expected not in completed.stderr:
                fail(f"component AST extractor did not fail closed for {component}: {completed.stdout}{completed.stderr}")

        malformed_map = root / "malformed-map.tsx"
        malformed_map.write_text(
            "const glyphs = new Map([['bad', (<span>no svg</span>)]])\n",
            encoding="utf-8",
        )
        completed = subprocess.run(
            [str(node24()), str(MAP_AST_EXTRACTOR), str(official_root), str(malformed_map), "glyphs", "bad"],
            text=True,
            capture_output=True,
        )
        if completed.returncode == 0 or "exactly one SVG JSX element; found 0" not in completed.stderr:
            fail(f"map-entry AST extractor did not fail closed: {completed.stdout}{completed.stderr}")


def verify_scenes() -> int:
    scenes = load_json(SCENES_PATH, "visual scene catalog")
    if scenes.get("officialSourceCommit") != EXPECTED_COMMIT:
        fail("visual scene catalog differs from the locked rc.1 baseline")
    contract = scenes.get("captureContract", {})
    if contract.get("deviceScaleFactor") != 1 or not contract.get("logicalViewport"):
        fail("visual scene catalog must pin a 1x logical viewport capture contract")
    required = {"source-map", "official-screenshot", "native-screenshot", "layout-rectangles"}
    scene_list = scenes.get("scenes")
    if not isinstance(scene_list, list) or not scene_list:
        fail("visual scene catalog is empty")
    for scene in scene_list:
        if not scene.get("id") or not scene.get("officialComponents"):
            fail("each visual scene requires an id and official component mapping")
        if not required.issubset(set(scene.get("requiredEvidence", []))):
            fail(f"visual scene {scene.get('id')} lacks required comparison evidence")
    return len(scene_list)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    arguments = parse_args()
    official_root = arguments.official_root.resolve()
    if not (official_root / "package.json").is_file():
        fail(f"official root is not a repository root: {official_root}")
    try:
        commit = subprocess.check_output(["git", "-C", str(official_root), "rev-parse", "HEAD"], text=True).strip()
    except subprocess.CalledProcessError as error:
        fail(f"cannot resolve official source commit: {error}")
    if commit != EXPECTED_COMMIT:
        fail(f"official root must be rc.1 {EXPECTED_COMMIT}, got {commit}")

    locale_count, token_count, layout_count = verify_current_catalog_provenance()
    verify_layout_fresh_extraction(official_root)
    asset_manifest = load_json(ASSET_MANIFEST_PATH, "official asset manifest")
    verify_assets_fresh_extraction(asset_manifest, official_root)
    verify_ast_structural_negatives(official_root)
    scene_count = verify_scenes()
    print(
        "D1 rc.1 specification provenance passed: "
        f"{locale_count} locale entries, {token_count} theme tokens, "
        f"{layout_count} computeColumns fixtures, {len(asset_manifest['assets'])} fresh TSX assets, "
        f"{scene_count} visual scenes; historical rc.2 catalog excluded from current counts."
    )


if __name__ == "__main__":
    main()
