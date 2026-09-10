# Visual replication validation

Glass aims to reproduce DeepSeek Harness product UI with native SwiftUI/AppKit. Visual validation exists to find observable differences in the product, not to certify a process or a metadata chain.

## Comparison contract

An official and native image are comparable only when they represent the same product state, viewport, locale and appearance. The official side is captured from a real DeepSeek Harness WebUI composition. The native side is captured from the built macOS app under WindowServer.

The `native-ui` workflow should retain the images and machine-readable comparison report needed to inspect the pair. A green build or successful artifact upload does not make a visual mismatch acceptable.

A scene is complete when a reviewer cannot identify a product-relevant difference that should be fixed. Text, layout, state, control order, borders, spacing, clipping, selection, focus and content colors are product differences. Low-level rasterization caused by different native/browser text rendering may remain only when the geometry and semantic styling are already aligned.

## Machine comparison

`glass/ci/compare_visual_pair.py` measures image differences and writes the report used during review. Thresholds are useful for locating regressions and preventing obviously divergent scenes from being called complete; they are not an alternate source of UI truth.

`visual-validation-policy.json` may distinguish exploratory/reporting scenes from enforced scenes while work is incomplete. A report-only scene is explicitly unfinished. Policy state must never be used to explain away a visible defect.

## Scene ownership

Keep one authoritative catalog for the native/official scene matrix. Additional files should exist only when they contain data that cannot be derived from that catalog, such as an upstream interaction driver or an accessibility fixture consumed by code.

When a scene is added, capture the smallest state that demonstrates the behavior. Do not create extra screenshots merely to satisfy a checklist. When multiple scenes expose the same shared shell defect, fix the shared owner first and then rerun the affected matrix.

## Native-system surfaces

System materials, menus, sheets and other macOS controls should use the native API that owns their behavior. Visual review still checks their placement, hierarchy, readable text and state. The existence of a system material is not a blanket exemption for unrelated geometry or styling differences.

## Evidence lifetime

Current workflow artifacts are evidence for the current implementation. Historical screenshots, old-baseline review notes and per-commit visual diaries belong in Git/Actions history unless a current test directly consumes them. The repository should not accumulate old screenshot trees as a second visual truth source.
