#!/usr/bin/env python3
"""Fail closed on declared Swift module boundary and forbidden dependency regressions."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources"
PACKAGE = ROOT / "Package.swift"
TARGETS = {
    "GlassSpec": 'path: "Sources/Spec"',
    "GlassCore": 'path: "Sources/Core"',
    "GlassUI": 'path: "Sources/UI"',
    "GlassSnapshot": 'path: "Sources/Snapshot"',
    "DeepSeekHarnessGlassApp": 'path: "Sources/App"',
}


def swift_sources(layer: str) -> list[Path]:
    return sorted((SOURCES / layer).rglob("*.swift"))


def text(paths: list[Path]) -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in paths)


def reject(value: bool, message: str) -> None:
    if value:
        raise SystemExit(message)


def main() -> None:
    package = PACKAGE.read_text(encoding="utf-8")
    for target, path in TARGETS.items():
        if f'name: "{target}"' not in package or path not in package:
            raise SystemExit(f"Package.swift must declare target {target} at {path}")
    for dependency in ('dependencies: ["GlassSpec"]', 'dependencies: ["GlassCore", "GlassSpec"]',
                       'dependencies: ["GlassCore", "GlassSpec", "GlassUI"]'):
        if dependency not in package:
            raise SystemExit(f"Package.swift is missing required dependency edge {dependency}")

    core_paths = swift_sources("Core")
    ui_paths = swift_sources("UI")
    session_paths = swift_sources("Core/Session")
    app_paths = swift_sources("App")
    snapshot_paths = swift_sources("Snapshot")
    for layer, paths in {"Core": core_paths, "UI": ui_paths, "Snapshot": snapshot_paths, "App": app_paths}.items():
        missing = [str(path.relative_to(ROOT)) for path in paths if "DEEPSEEK_HARNESS_PACKAGE" not in path.read_text(encoding="utf-8")]
        if missing:
            raise SystemExit(f"{layer} sources must declare conditional package imports: {', '.join(missing)}")

    core = text(core_paths)
    ui = text(ui_paths)
    session = text(session_paths)
    app = text(app_paths)
    reject("import AppKit" in core or "import SwiftUI" in core, "Core must not import AppKit or SwiftUI")
    reject("NSOpenPanel" in core or "NSApplication" in session or "NSApp" in session,
           "Core reducer/session code must not access AppKit application APIs")
    reject("Process(" in ui or "NSApplication" in ui or "NSApp" in ui or "NSStatusItem" in ui,
           "UI must not start processes or access application lifecycle APIs")
    reject("@main" not in app or sum("@main" in path.read_text(encoding="utf-8") for path in app_paths) != 1,
           "App target must own exactly one @main declaration")
    reject("@main" in core or "@main" in ui or "@main" in text(snapshot_paths),
           "Only App target may declare @main")
    reject((SOURCES / "main.swift").exists(), "legacy monolithic Sources/main.swift must not exist")
    print("Module boundary gate passed: SwiftPM targets and dependency-direction rules are intact.")


if __name__ == "__main__":
    main()
