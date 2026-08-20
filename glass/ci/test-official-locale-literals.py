#!/usr/bin/env python3
"""Executable proof that direct unregistered SwiftUI product copy is rejected."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "ci/check-official-locale-literals.py"
UI_ROOT = ROOT / "Sources/UI"


def run(source_root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), "--source-root", str(source_root)],
        text=True,
        capture_output=True,
        check=False,
    )


def main() -> None:
    current = run(UI_ROOT)
    if current.returncode != 0:
        raise SystemExit(f"existing UI literal lint unexpectedly failed:\n{current.stdout}\n{current.stderr}")
    with tempfile.TemporaryDirectory(prefix="dsh-locale-lint-") as temporary:
        root = Path(temporary)
        (root / "Sample.swift").write_text('import SwiftUI\nlet sample = Text("Invented product text")\n', encoding="utf-8")
        injected = run(root)
        output = injected.stdout + injected.stderr
        if injected.returncode == 0 or "Fail-closed check failed" not in output or "Invented product text" not in output:
            raise SystemExit(f"unregistered product copy unexpectedly passed:\n{injected.stdout}\n{injected.stderr}")
    print("Official locale literal lint self-test passed.")


if __name__ == "__main__":
    main()
