#!/usr/bin/env python3
"""Static D1 gate for the native SwiftUI migration.

This gate intentionally validates only deterministic provenance facts:
- the versioned catalog is structurally sound and bound to the locked commit;
- every registered SVG is one valid root document;
- native UI code does not introduce direct Text("...") product strings.

It never claims that a screenshot alone proves fidelity; visual and behavior
reviews remain separate evidence gates.
"""
from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "Sources/Spec/OfficialUISpec/official-ui-catalog.json"
SCENES_PATH = ROOT / "Sources/Spec/Fixtures/visual-scenes.json"
ASSET_DIR = ROOT / "assets"
UI_ROOT = ROOT / "Sources/UI"
LOCKED_COMMIT = "141eb6fef83422698aef7a981029e843e8161534"


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


def verify_scenes() -> dict:
    try:
        scenes = json.loads(SCENES_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing visual scene catalog: {SCENES_PATH}")
    except json.JSONDecodeError as error:
        fail(f"invalid visual scene JSON: {error}")
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


def verify_ui_text() -> None:
    # UI product copy must resolve through OfficialUISpec or a future generated
    # OfficialLocale value. Code identifiers, debug logs and non-UI sources are
    # deliberately out of scope for this first gate.
    literal = re.compile(r'\bText\s*\(\s*"([^"\\]|\\.)*"')
    violations: list[str] = []
    for path in UI_ROOT.rglob("*.swift"):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if literal.search(line):
                violations.append(f"{path.relative_to(ROOT)}:{line_number}: {line.strip()}")
    if violations:
        fail("direct UI text literals are prohibited:\n" + "\n".join(violations))


def verify_catalog_sources(catalog: dict) -> None:
    for group_name in ("layout", "text", "assets"):
        for key, value in catalog[group_name].items():
            if not value.get("source"):
                fail(f"{group_name}.{key} lacks a source record")


def main() -> None:
    catalog = load_catalog()
    verify_catalog_sources(catalog)
    verify_assets(catalog)
    scenes = verify_scenes()
    verify_ui_text()
    print(
        "D1 official specification gate passed: "
        f"{len(catalog['text'])} text values, {len(catalog['layout'])} layout values, "
        f"{len(catalog['assets'])} assets, {len(scenes['scenes'])} visual scenes."
    )


if __name__ == "__main__":
    main()
