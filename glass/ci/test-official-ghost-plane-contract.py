#!/usr/bin/env python3
"""Self-tests for the Ghost Plane upstream-contract drift gate."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "glass/ci/check-official-ghost-plane-contract.py"
CONTRACT = ROOT / "glass/Sources/Core/Resources/official-ghost-plane-contract.json"


def invoke(official_root: Path, contract: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECK), "--official-root", str(official_root), "--contract", str(contract)],
        text=True, capture_output=True, check=False,
    )


def main() -> None:
    official_root = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(".reference/deepseek-harness")
    if not official_root.is_dir():
        raise SystemExit("pass the locked official source root or run in native-ui CI after checkout")
    passing = invoke(official_root, CONTRACT)
    if passing.returncode != 0:
        raise SystemExit("baseline Ghost Plane contract unexpectedly failed:\n" + passing.stdout + passing.stderr)

    with tempfile.TemporaryDirectory(prefix="dsh-ghost-plane-contract-test-") as temporary:
        temp = Path(temporary)
        tampered = temp / "tampered.json"
        fixture = json.loads(CONTRACT.read_text(encoding="utf-8"))
        fixture["selectors"].remove("[data-streaming]")
        tampered.write_text(json.dumps(fixture), encoding="utf-8")
        result = invoke(official_root, tampered)
        if result.returncode == 0 or "lacks required rc.1 DOM selectors" not in result.stderr:
            raise SystemExit("tampered contract selector unexpectedly passed")

        copied_root = temp / "official"
        required = [
            "packages/client/ui-conversation/src/client/contract/slots.ts",
            "packages/client/ui-chat/src/client/contract/slots.ts",
            "packages/client/ui-conversation/src/client/skeleton/ConversationRoot.tsx",
            "packages/client/ui-chat/src/client/chat/ChatView.tsx",
            "packages/client/ui-chat/src/client/chat/ChatNodeSeat.tsx",
            "packages/client/ui-chat/src/client/chat/AssistantMarkdown.tsx",
            "packages/client/modules/src/client/manifest.ts",
            "packages/client/modules/src/index.ts",
        ]
        for relative in required:
            source = official_root / relative
            destination = copied_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        slots = copied_root / "packages/client/ui-chat/src/client/contract/slots.ts"
        text = slots.read_text(encoding="utf-8")
        slots.write_text(text.replace("'conversation.chat.turnTail'", "'conversation.chat.turnTailRemoved'", 1), encoding="utf-8")
        result = invoke(copied_root, CONTRACT)
        if result.returncode == 0 or "lacks required Ghost Plane seats" not in result.stderr:
            raise SystemExit("upstream SlotMap drift unexpectedly passed")

    print("Official Ghost Plane contract gate self-test passed.")


if __name__ == "__main__":
    main()
