#!/usr/bin/env python3
"""Fresh-extract the registered official SVG assets from the locked rc.1 TSX tree.

The checked manifest is generated from the same run as the SVG bytes. Every
entry records the upstream source hash, AST selector, and deterministic
transform, so additions, removals, or source drift are visible in review.
Generated SVG bytes are byte-compared by the provenance gate, so output drift
fails closed in CI.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import textwrap
from dataclasses import dataclass
from pathlib import Path

EXPECTED_COMMIT = "a66e4702047846cdaa10c66c9d3df3951f5ea70d"
GENERATOR_NAME = "generate_official_assets.py"
GENERATOR_VERSION = "1.0.0"

PROJECT_ROOT = Path(__file__).resolve().parents[2]
ICON_EXTRACTOR = PROJECT_ROOT / "tools/spec-generation/extract_official_icon_ast.mjs"
MAP_EXTRACTOR = PROJECT_ROOT / "tools/spec-generation/extract_official_map_svg_ast.mjs"

INDEX_SOURCE = "packages/client/ui-primitives/src/icons/index.tsx"
BRAND_SOURCE = "packages/client/ui-primitives/src/BrandWordmark.tsx"
FISH_SOURCE = "packages/client/ui-primitives/src/FishLogo.tsx"
PERMISSION_SOURCE = "packages/client/ui-conversation/src/client/skeleton/PermissionSelect.tsx"


@dataclass(frozen=True)
class Recipe:
    name: str
    source: str
    kind: str
    selector: str
    fill: str | None = None


RECIPES = (
    Recipe("brand-wordmark", BRAND_SOURCE, "component-inner", "BrandWordmark"),
    Recipe("fish-logo", FISH_SOURCE, "component-inner", "FishLogo", "#0F1115"),
    Recipe("fish", FISH_SOURCE, "component-inner", "FishLogo", "black"),
    Recipe("icon-new-chat", INDEX_SOURCE, "component-svg", "IconNewChatOutline16", "#0F1115"),
    Recipe("icon-panel-left", INDEX_SOURCE, "component-svg", "IconPanelLeftOutline16", "#0F1115"),
    Recipe("icon-search", INDEX_SOURCE, "component-svg", "IconSearchOutline16", "#0F1115"),
    Recipe("icon-personalization", INDEX_SOURCE, "component-svg", "IconPersonalizationOutline16", "#0F1115"),
    Recipe("icon-project-add", INDEX_SOURCE, "component-svg", "IconProjectAddOutline16", "#0F1115"),
    Recipe("icon-settings", INDEX_SOURCE, "component-svg", "IconSettingsOutline16", "#0F1115"),
    Recipe("icon-folder-close", INDEX_SOURCE, "component-svg", "IconFolderClose16", "#0F1115"),
    Recipe("icon-agent-preset", INDEX_SOURCE, "component-svg", "IconAgentPresetOutline16", "#0F1115"),
    Recipe("icon-permission-workspace-write", PERMISSION_SOURCE, "map-entry-svg", "permissionGlyphs:workspace-write"),
    Recipe("icon-plus", INDEX_SOURCE, "component-svg", "IconPlusOutline16", "#0F1115"),
    Recipe("icon-send-up", INDEX_SOURCE, "component-svg", "IconSendOutline16", "#0F1115"),
    Recipe("icon-close", INDEX_SOURCE, "component-svg", "IconCloseOutline16", "#0F1115"),
    Recipe("icon-chevron-down", INDEX_SOURCE, "component-svg", "IconChevronDownOutline14", "#0F1115"),
    Recipe("icon-folder-open", INDEX_SOURCE, "component-svg", "IconFolderOpen16", "#0F1115"),
    Recipe("icon-ellipsis", INDEX_SOURCE, "component-svg", "IconEllipsisOutline16", "#0F1115"),
    Recipe("icon-branch", INDEX_SOURCE, "component-svg", "IconBranchOutline16", "#0F1115"),
    Recipe("icon-archive", INDEX_SOURCE, "component-svg", "IconArchiveOutline20", "#0F1115"),
    Recipe("icon-stop", INDEX_SOURCE, "component-svg", "IconStopFill16", "#0F1115"),
    Recipe("icon-tool-search", INDEX_SOURCE, "component-svg", "IconSearchOutline16", "#0F1115"),
    Recipe("icon-tool-read", INDEX_SOURCE, "component-svg", "IconBrowseOutline16", "#0F1115"),
    Recipe("icon-tool-bash", INDEX_SOURCE, "component-svg", "IconApiOutline14", "#0F1115"),
    Recipe("icon-tool-edit", INDEX_SOURCE, "component-svg", "IconEditOutline16", "#0F1115"),
    Recipe("icon-tool-code", INDEX_SOURCE, "component-svg", "IconCodeOutline16", "#0F1115"),
    Recipe("icon-tool-others", INDEX_SOURCE, "component-svg", "IconSparkle16", "#0F1115"),
    Recipe("icon-check", INDEX_SOURCE, "component-svg", "IconCheckOutline14", "#0F1115"),
    Recipe("icon-checklist", INDEX_SOURCE, "component-svg", "IconChecklistOutline14", "#0F1115"),
    Recipe("icon-question", INDEX_SOURCE, "component-svg", "IconQuestionOutline14", "#0F1115"),
    Recipe("icon-goal", INDEX_SOURCE, "component-svg", "IconGoalOutline16", "#0F1115"),
    Recipe("icon-pause", INDEX_SOURCE, "component-svg", "IconPauseOutline16", "#0F1115"),
    Recipe("icon-play", INDEX_SOURCE, "component-svg", "IconPlayOutline16", "#0F1115"),
    Recipe("icon-trash", INDEX_SOURCE, "component-svg", "IconTrashOutline16", "#0F1115"),
    Recipe("icon-queue", INDEX_SOURCE, "component-svg", "IconQueueOutline14", "#0F1115"),
    Recipe("icon-chevron-left", INDEX_SOURCE, "component-svg", "IconChevronLeftOutline14", "#0F1115"),
    Recipe("icon-chevron-right", INDEX_SOURCE, "component-svg", "IconChevronRightOutline14", "#0F1115"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--manifest-output", type=Path, required=True)
    parser.add_argument("--node", default=os.environ.get("DSH_NODE") or os.environ.get("NODE") or "node")
    return parser.parse_args()


def git_blob_sha1(data: bytes) -> str:
    payload = b"blob " + str(len(data)).encode("ascii") + b"\0" + data
    return hashlib.sha1(payload).hexdigest()


def git(root: Path, *arguments: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *arguments], text=True).strip()


def run_node(node: str, script: Path, *arguments: str) -> str:
    completed = subprocess.run(
        [node, str(script), *arguments],
        cwd=script.parent,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise SystemExit(f"asset AST extraction failed via {script.name}: {detail}")
    return completed.stdout


def component_inner(node: str, official_root: Path, source: Path, component: str) -> str:
    output = run_node(node, ICON_EXTRACTOR, str(official_root), str(source), component, "--inner")
    return output.rstrip("\n")


def component_svg(node: str, official_root: Path, source: Path, component: str, fill: str) -> bytes:
    output = run_node(node, ICON_EXTRACTOR, str(official_root), str(source), component, fill)
    return (output.rstrip("\n") + "\n").encode("utf-8")


def wrapped_inner(kind: str, inner: str, fill: str | None) -> bytes:
    if kind == "brand-wordmark":
        body = inner.replace('fill="currentColor"', 'fill="#0F1115"').replace(
            'fill="var(--dsw-alias-label-primary-inverted)"', 'fill="#FFFFFF"'
        )
        root = '<svg xmlns="http://www.w3.org/2000/svg" width="182" height="24" viewBox="0 0 182 24" fill="none">'
    elif kind == "fish":
        if fill is None:
            raise AssertionError("fish wrapper requires a fill")
        body = inner.replace('fill="currentColor"', f'fill="{fill}"')
        root = '<svg xmlns="http://www.w3.org/2000/svg" width="23.16" height="17.04" viewBox="0 0 23.16 17.04" fill="none">'
    elif kind == "fish-legacy":
        body = textwrap.indent(textwrap.dedent(inner).strip(), "  ")
        body = body.replace('fill="currentColor" />', 'fill="black"/>')
        root = '<svg xmlns="http://www.w3.org/2000/svg" width="23.16" height="17.04" viewBox="0 0 23.16 17.04">'
    else:
        raise AssertionError(f"unknown wrapped asset kind: {kind}")
    return f"{root}\n{body}\n</svg>\n".encode("utf-8")


def extract(recipe: Recipe, node: str, official_root: Path) -> bytes:
    source = official_root / recipe.source
    if not source.is_file():
        raise SystemExit(f"official asset source is missing: {recipe.source}")
    if recipe.kind == "component-svg":
        if recipe.fill is None:
            raise AssertionError("component SVG requires a fill")
        return component_svg(node, official_root, source, recipe.selector, recipe.fill)
    if recipe.kind == "component-inner":
        inner = component_inner(node, official_root, source, recipe.selector)
        if recipe.name == "brand-wordmark":
            return wrapped_inner("brand-wordmark", inner, recipe.fill)
        if recipe.name == "fish":
            return wrapped_inner("fish-legacy", inner, recipe.fill)
        return wrapped_inner("fish", inner, recipe.fill)
    if recipe.kind == "map-entry-svg":
        map_name, separator, key = recipe.selector.partition(":")
        if not separator:
            raise AssertionError("map selector must be MAP:KEY")
        output = run_node(node, MAP_EXTRACTOR, str(official_root), str(source), map_name, key)
        return (output.rstrip("\n") + "\n").encode("utf-8")
    raise AssertionError(f"unknown extraction kind: {recipe.kind}")


def transform_record(recipe: Recipe) -> dict[str, object] | None:
    if recipe.name == "brand-wordmark":
        return {
            "root": {"width": 182, "height": 24, "viewBox": "0 0 182 24", "fill": "none"},
            "fills": {
                "currentColor": "#0F1115",
                "var(--dsw-alias-label-primary-inverted)": "#FFFFFF",
            },
        }
    if recipe.name in {"fish-logo", "fish"}:
        root: dict[str, object] = {"width": 23.16, "height": 17.04, "viewBox": "0 0 23.16 17.04"}
        if recipe.name == "fish-logo":
            root["fill"] = "none"
        return {"root": root, "currentColor": recipe.fill}
    if recipe.fill is not None:
        return {"currentColor": recipe.fill}
    return None


def main() -> None:
    args = parse_args()
    official_root = args.official_root.resolve()
    output_dir = args.output_dir.resolve()
    manifest_output = args.manifest_output.resolve()
    if git(official_root, "rev-parse", "HEAD") != EXPECTED_COMMIT:
        raise SystemExit(f"official root must be locked to {EXPECTED_COMMIT}")

    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_output.parent.mkdir(parents=True, exist_ok=True)

    source_paths = sorted({recipe.source for recipe in RECIPES})
    source_records: dict[str, dict[str, str]] = {}
    input_digest = hashlib.sha256()
    for relative_path in source_paths:
        data = (official_root / relative_path).read_bytes()
        blob_hash = git_blob_sha1(data)
        input_digest.update(relative_path.encode("utf-8"))
        input_digest.update(b"\0")
        input_digest.update(blob_hash.encode("ascii"))
        source_records[relative_path] = {"gitBlobSha1": blob_hash}

    asset_set_digest = hashlib.sha256()
    entries = []
    for recipe in RECIPES:
        data = extract(recipe, args.node, official_root)
        target = output_dir / f"{recipe.name}.svg"
        target.write_bytes(data)
        source_hash = source_records[recipe.source]["gitBlobSha1"]
        entry = {
            "name": recipe.name,
            "file": f"{recipe.name}.svg",
            "source": {
                "path": recipe.source,
                **source_records[recipe.source],
                "commit": EXPECTED_COMMIT,
            },
            "astSelector": {
                "kind": recipe.kind,
                "value": recipe.selector,
            },
        }
        transform = transform_record(recipe)
        if transform is not None:
            entry["transform"] = transform
        revision_record = {
            "name": recipe.name,
            "file": entry["file"],
            "sourcePath": recipe.source,
            "sourceGitBlobSha1": source_hash,
            "astSelector": entry["astSelector"],
            "transform": transform,
        }
        asset_set_digest.update(json.dumps(revision_record, sort_keys=True, separators=(",", ":")).encode("utf-8"))
        asset_set_digest.update(b"\n")
        entries.append(entry)

    manifest = {
        "schemaVersion": 1,
        "sourceCommit": EXPECTED_COMMIT,
        "sourceInputRevision": f"sha256:{input_digest.hexdigest()}",
        "assetSetRevision": f"sha256:{asset_set_digest.hexdigest()}",
        "generatedAt": git(official_root, "show", "-s", "--format=%cI", EXPECTED_COMMIT),
        "generator": {"name": GENERATOR_NAME, "version": GENERATOR_VERSION},
        "assets": entries,
    }
    manifest_output.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        f"Generated {len(entries)} official SVG assets from {len(source_records)} rc.1 TSX sources; "
        f"asset set revision {manifest['assetSetRevision']}."
    )


if __name__ == "__main__":
    main()
