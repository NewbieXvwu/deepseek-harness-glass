#!/usr/bin/env python3
"""Guard the CI feedback topology without relying on runner-specific tooling."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NATIVE = (ROOT / ".github/workflows/native-ui.yml").read_text(encoding="utf-8")
PORTABLE = (ROOT / ".github/workflows/portable-checks.yml").read_text(encoding="utf-8")
DOCS = (ROOT / ".github/workflows/documentation-integrity.yml").read_text(encoding="utf-8")
BASELINE = (ROOT / ".github/workflows/prepare-official-baseline.yml").read_text(encoding="utf-8")
PACKAGE = (ROOT / "glass/Package.swift").read_text(encoding="utf-8")


def assert_contains(text: str, snippet: str, source: str) -> None:
    if snippet not in text:
        raise AssertionError(f"{source} must contain: {snippet}")


def assert_not_contains(text: str, snippet: str, source: str) -> None:
    if snippet in text:
        raise AssertionError(f"{source} must not contain: {snippet}")


def main() -> None:
    for path in ("README.md", "README.zh.md", "CONTRIBUTING.md", "TODO.md", "notes/**", "visual-review/**"):
        assert_contains(NATIVE, f'- "{path}"', "native-ui.yml paths-ignore")
        assert_contains(DOCS, f'- "{path}"', "documentation-integrity.yml paths")
    assert_contains(NATIVE, "concurrency:", "native-ui.yml")
    assert_contains(NATIVE, "cancel-in-progress: true", "native-ui.yml")
    assert_contains(NATIVE, "Restore prepared official WebUI baseline", "native-ui.yml")
    assert_contains(NATIVE, "Build and capture official WebUI baseline on cache miss", "native-ui.yml")
    assert_contains(BASELINE, "Build and capture locked official WebUI baseline", "prepare-official-baseline.yml")
    assert_contains(BASELINE, "tools/reference-capture/**", "prepare-official-baseline.yml")
    assert_contains(BASELINE, ".github/workflows/native-ui.yml", "prepare-official-baseline.yml")
    assert_contains(PORTABLE, "runs-on: ubuntu-latest", "portable-checks.yml")
    assert_contains(PORTABLE, "glass/ci/portable-core-check.swift", "portable-checks.yml")
    assert_contains(PORTABLE, "Sources/PortableCore/HostPathDisplay.swift", "portable-checks.yml")
    assert_contains(PACKAGE, 'name: "GlassPortableCore"', "Package.swift")
    assert_contains(PACKAGE, 'name: "GlassPortableCoreTests"', "Package.swift")
    assert_not_contains(PACKAGE, 'name: "GlassPortableCore",\n            dependencies:', "Package.swift")
    print("CI workflow topology test passed.")


if __name__ == "__main__":
    main()
