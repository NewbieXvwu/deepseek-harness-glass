#!/usr/bin/env python3
"""Reject custom structural material in native sidebar and inspector columns."""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPLIT = ROOT / "Sources/UI/Shell/NativeSplitContainer.swift"
SIDEBAR_HOST = ROOT / "Sources/UI/Sidebar/OfficialSidebarHostController.swift"
SIDEBAR = ROOT / "Sources/UI/Sidebar/SidebarView.swift"
DETAILS = ROOT / "Sources/UI/Conversation/NativeConversationViews.swift"
STRUCTURAL_ROOTS = [ROOT / "Sources/UI/Shell", ROOT / "Sources/UI/Sidebar", ROOT / "Sources/UI/Conversation"]

failures: list[str] = []

split = SPLIT.read_text()
for required in (
    "NSSplitViewItem(sidebarWithViewController: sidebarHost)",
    "NSSplitViewItem(inspectorWithViewController: detailsHost)",
):
    if required not in split:
        failures.append(f"NativeSplitContainer.swift must contain {required!r}")

host = SIDEBAR_HOST.read_text()
for required in ("container.layer?.isOpaque = false", "container.layer?.backgroundColor = NSColor.clear.cgColor"):
    if required not in host:
        failures.append(f"OfficialSidebarHostController.swift must contain {required!r}")
if "OfficialSidebarCanvasView" in host:
    failures.append("OfficialSidebarHostController.swift must not draw a fixed sidebar canvas")

sidebar = SIDEBAR.read_text()
if ".background(OfficialUISpec.Token.sidebar)" in sidebar:
    failures.append("SidebarView.swift must not paint a structural sidebar token background")

details = DETAILS.read_text()
if "struct NativeDetailsView" not in details:
    failures.append("NativeConversationViews.swift must retain NativeDetailsView")
else:
    details_tail = details.split("struct NativeDetailsView", 1)[1]
    if ".background(OfficialUISpec.Token.base)" in details_tail:
        failures.append("NativeDetailsView must not paint a fixed inspector background")

for source_root in STRUCTURAL_ROOTS:
    for path in source_root.rglob("*.swift"):
        if "NSVisualEffectView" in path.read_text():
            failures.append(f"{path.relative_to(ROOT)} must not introduce NSVisualEffectView for structural material")

if failures:
    print("Native structural material policy failed:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print("Native structural material policy: system sidebar/inspector material only")
