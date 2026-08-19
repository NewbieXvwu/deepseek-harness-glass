# T6.3 ProjectionStore CI visual review

| Evidence | Value |
|---|---|
| Commit | `0853a1f381736aac88b9b0916859b97b9eb99590` |
| GitHub Actions run | [`32235326314`](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32235326314) |
| Result | Success; macOS-26 / Xcode 26 build, all native gates and screenshots completed |
| Official reference | `deepseek-ai/deepseek-harness@99f6f02fecdb7dff40c3fbc9470f5907c29f74ca` |
| Compared scene | `welcome-no-workspace-light` |
| Screenshot inputs | `artifacts/official-webui/welcome-no-workspace-light.png`; `artifacts/native-shell/welcome-light.png` |
| Diff output | `artifacts/visual-diff/welcome-no-workspace-light-comparison.png` and JSON report uploaded by the run |

The native welcome scene remains structurally aligned with the locked official baseline: the sidebar navigation column, no-sessions workspace state, centered **Into the Unknown** empty-workspace prompt, workspace/mode controls, and wide disabled composer all retain their established geometry and hierarchy. The comparison composite shows the known platform-rendering differences reported under the project visual policy, but no new T6.3-visible layout or styling regression.

The implementation change is Core-only: `SessionProjectionStore` accepts only higher-sequence Host values, is seeded from history-tail projections, drops stale missing keys at the baseline cutoff, truncates nondurable rows after reconnect, and is isolated by session ID. macOS CI executed `SessionProjectionStoreTests` in addition to the complete native build, snapshot, and official screenshot-comparison chain.
