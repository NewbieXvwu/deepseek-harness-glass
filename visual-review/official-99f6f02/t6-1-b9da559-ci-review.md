# T6.1 NativeSessionStore CI visual review

| Evidence | Value |
|---|---|
| Commit | `b9da5592508ebe61d95c0ff1e124ec08094b08c3` |
| GitHub Actions run | [`32236473372`](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32236473372) |
| Result | Success; macOS-26 / Xcode 26, complete native gate, test, app assembly, snapshot and visual-comparison chain |
| Official reference | `deepseek-ai/deepseek-harness@99f6f02fecdb7dff40c3fbc9470f5907c29f74ca` |
| Reviewed images | `official-webui/welcome-no-workspace-light.png`, `native-shell/welcome-light.png`, `native-shell/tooling-inspector-dark.
png`,
and welcome comparison/diff report |

The welcome comparison remains within the pre-existing, explicitly bounded `report-only` native-system-rendering review posture.
Manual inspection confirms that the sidebar's navigation hierarchy,
empty-workspace prompt, centered composer, official copy order, disabled state,
and component anchors remain unchanged by the Core state update.


No new visible difference is attributed to T6.1.

The native tooling-inspector scene preserves its existing conversation order, user message, tool-call rows, assistant reply,
composer position, and inspector-aware three-column composition.


The T6.
1 changes expose Host-authoritative queue and jobs snapshots and preserve a resident session window in Core;
they do not change renderer hierarchy or visual tokens.
macOS CI independently ran `NativeSessionStoreTests`,
including queue/jobs whole-snapshot replacement, session rejection, subscription-generation clearing, projection truncation,
and resident-window recovery.



