# RC8 official capture review — expanded model selector menu

> **Evidence class:** official-side baseline only. This artifact is **not** a paired native visual acceptance and does not expand the closed-trigger policy.

| Field | Value |
|---|---|
| Upstream commit | `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534` |
| Official source | `packages/client/ui-model-selection/src/client/ModelSelect.tsx:219-283`; `locales.ts:41-45` |
| Capture state | Fresh official Web scaffold; real workspace connection; enabled composer; real click on the model trigger |
| Viewport and display | 1280×840 CSS px; DPR 1; `en-US`; light scheme |
| Artifacts | `model-selector-menu-light-official.png`; `model-selector-menu-light-official.json` |
| Capture health | No console warnings; no page errors |

## Visible and accessibility facts

The real RC8 trigger **Select model, current DeepSeek-V4-Flash** is expanded. It opens a compact, right-aligned root pane above the composer control. That pane displays the sole root row **Model** with the selected **DeepSeek-V4-Flash** value and a right-facing drill-in affordance. The recorded body accessibility tree contains `menu "Model and reasoning effort"` and `menuitem "Model DeepSeek-V4-Flash"`.

## Review boundary

The native client renders the official seat with a real SwiftUI/AppKit `Menu`. The existing off-screen native snapshot driver can render the closed trigger, but it cannot fabricate an open system Menu without replacing the production interaction. The corresponding native evidence must therefore be obtained on macOS by actual AX/click interaction, followed by a WindowServer screenshot, menu AX extraction, image comparison, and human review. Until then this committed source baseline remains an **official-only reference**, and neither T6.6 nor `model-selector-light` may be marked visually paired on its basis.
