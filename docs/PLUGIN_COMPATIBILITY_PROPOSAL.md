# Ghost Plane plugin compatibility

DeepSeek Harness Glass keeps first-party product UI native. Third-party plugin client code may need the browser contracts exposed by DeepSeek Harness, so that code runs only inside the dedicated `GlassPluginPlane` target. Core conversation, workspace, settings, model, credential and tool UI do not move into WebKit.

This document describes the current architectural boundary. Git history carries earlier design proposals and migration experiments.

## Ownership

The native app owns all first-party visible state and layout. Host Remote APIs remain the business authority. The Ghost Plane owns only the browser environment needed by third-party client modules.

`GlassCore` contains platform-independent admission and synchronization logic. `GlassPluginPlane` is the only target that imports WebKit and applies admitted data to a `WKWebView`. `GlassUI` and the app shell do not execute plugin JavaScript.

A plugin does not gain capabilities because of a repository owner, Git commit, package provenance label or a predeclared "official" identity. Runtime admission is based on the actual Host-provided module graph, loopback resource URLs and the explicit bridge boundary.

## Document and resource boundary

The Ghost Plane uses one non-persistent WebKit document with an empty structural skeleton. The skeleton exposes stable seats and anchors required by compatible client modules, while native conversation text, credentials and other first-party content remain outside the document.

`GhostPlaneLoopbackPolicy` admits only the expected loopback origin and registered plugin resource routes. External network locations, local files, credential-bearing URLs and path reinterpretation are rejected before plugin resources are loaded.

`GhostPlaneModuleManifest` decodes the Host-provided module graph and validates facts that affect execution: plugin identity, resource URL, revision, dependency ordering and combo-bundle membership. These checks operate on external runtime input; they do not compare the graph with repository-authored hashes or build labels.

`GhostPlaneModuleActivationGate` records observed bundle arrival and issues one-shot activation permits only after the graph dependencies required by that entry have arrived. The permit is an execution boundary between admitted runtime data and WebKit module materialization; it is not a second provenance system.

## Native/Web bridge

Cross-boundary messages use typed data. The bridge does not accept arbitrary JavaScript source, HTML fragments, selectors, callback source or native object references from plugin data.

Scroll synchronization transfers a finite scalar plus document/sequence identity. Event bridging transfers typed keyboard, selection, drag and attachment identities with generation fences. Attachment bytes and file paths stay behind native attachment admission. `tapIndex` compatibility is limited to the small mutation vocabulary implemented by `GhostPlaneTapIndexReplay`; arbitrary HTML or script rewriting is outside the contract.

External navigation and temporary-file handling stay in `GlassPluginPlane` adapters so the Web document cannot silently widen the app's network or file-system authority.

## Permissions

Capabilities that need native mediation are decided at the actual call boundary. `GhostPlanePermissionBroker` records the user's decision for a plugin/capability pair and supports revocation. A manifest field, package name, source repository or previously observed Git revision cannot grant a native capability.

## Validation

Useful validation targets observable boundaries:

- malformed or unsafe Host module graphs are rejected;
- disallowed resource/navigation URLs never reach WebKit;
- stale document generations and event echoes cannot overwrite current native state;
- plugin code cannot inject first-party content or bypass native attachment/navigation admission;
- WebKit remains isolated to `GlassPluginPlane` in the built target graph and runtime view hierarchy;
- real third-party modules are exercised through the same Host and browser contracts they use in DeepSeek Harness.

Repository-authored metadata agreeing with other repository-authored metadata is not acceptance evidence. Reference source revisions may be recorded for developer research, but they do not control runtime compatibility or permissions.

## Scope

The codebase may contain incomplete adapters while plugin compatibility work is in progress. Completion state belongs in `TODO.md`; this architecture document intentionally does not keep per-commit progress logs, CI run numbers, historical build matrices or future implementation checklists.
