# CAOCAP iOS Performance Audit

**Date:** 2026-08-07  
**Scope:** SwiftUI iOS app (`ios-app/caocap`) — launch, canvas, Mini-App previews, CoCaptain, persistence, Copilot Live.  
**Out of scope:** marketing website (already lean; negligible client JS).

> **Historical audit:** This report measured the pre-orchestration iOS
> implementation. Mini-App nodes, live previews, and node connections are no
> longer active product direction. Keep the measurements as historical evidence;
> do not treat its Mini-App recommendations as the current roadmap. See
> [CAOCAP Product Direction](PRODUCT_DIRECTION.md).

## Executive summary

Top bottlenecks (measured + high-confidence static analysis):

1. **P0 — Artificial launch splash (~2.5s) dominated time-to-interactive (fixed).** OSSignpost `launch` measured **2919 ms** from `didFinishLaunching` to splash dismiss. App Launch lifecycle already reaches Foreground-Active by ~**2.3 s**; the fixed sleep then delayed interaction further. Splash now dismisses on readiness after a ~1.2s brand minimum (2.5s max).
2. **P0 — Per-node live `WKWebView` Mini-App thumbnails** (no culling, no shared process pool, 375×667 scaled to 240). Root canvas has few/no Mini-Apps so launch traces understate this; cost scales with Mini-App count (S3).
3. **P1 — Canvas gesture redraw path** still pays for `ConnectionLayer` SwiftUI `Canvas`, `.ultraThinMaterial` + dual gradients per node, and a 2000×2000 `SpaceSketchBG` during pan/zoom. Grid is already optimized (CA replicator).

**Non-issues on root canvas (measured):** `projectLoad` ~1–3 ms; `livePreviewCompile` ≪1 ms when few Mini-Apps.

## Method

| Item | Detail |
|------|--------|
| Device | iPhone 12 (“Azzam Rar”), iOS 26.5 (23F77) |
| Build | Debug, `com.Ficruty.caocap` |
| Templates | App Launch, Time Profiler, Allocations, Logging |
| Signposts | subsystem `com.caocap.app`, category `Performance` via [`PerformanceSignposts.swift`](../ios-app/caocap/caocap/Services/AppEnvironment/PerformanceSignposts.swift) |
| Metrics file | [`docs/perf-traces/metrics.json`](perf-traces/metrics.json) |

### Signpost catalog

| Name | Where |
|------|--------|
| `launch` | `AppDelegate` begin → `AppSessionCoordinator` splash dismiss |
| `projectLoad` | `ProjectStore.load` |
| `livePreviewCompile` | `LivePreviewOrchestrator.compile` |
| `webViewMake` / `webViewLoad` | `HTMLWebView` |
| `save` | `ProjectSaveController` disk write |
| `canvasGesture` | pan/pinch/node-drag end (event) |
| `agentStream` | CoCaptain stream turn |
| `screenCaptureEncode` | Copilot Live JPEG encode |

### Scenario matrix status

| ID | Scenario | Status |
|----|----------|--------|
| S1 | Cold launch | **Done** (App Launch + Logging + Allocations) |
| S2 | Few-node canvas idle after launch | **Partial** (20s Time Profiler; no gesture drive) |
| S3 | Many Mini-Apps pan/zoom | Runbook — create stress project, record Time Profiler + Allocations |
| S4 | Drag node with links | Runbook — Animation Hitches / Time Profiler |
| S5 | Open/close Mini-App detail | Runbook — Allocations (WebView retain) |
| S6 | CoCaptain short stream | Runbook — Logging (`agentStream`) |
| S7 | Save after edit | Runbook — Logging (`save`) |
| S8 | Copilot Live 30s | Runbook — Energy + `screenCaptureEncode` |
| S9 | Personalization SpriteKit | Runbook — Time Profiler |

### Re-record commands

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEVICE=<udid>   # xcrun xctrace list devices
APP=.../Build/Products/Debug-iphoneos/caocap.app

xcrun xctrace record --template 'App Launch' --device "$DEVICE" \
  --output docs/perf-traces/S1-app-launch-device.trace --time-limit 15s --launch -- "$APP"

xcrun xctrace record --template 'Logging' --device "$DEVICE" \
  --output docs/perf-traces/S1-logging-signposts.trace --time-limit 8s --launch -- "$APP"
```

Interactive S3–S9: Profile scheme → Instruments → attach after launch → perform scenario → stop. Filter Points of Interest to `com.caocap.app` / `Performance`.

## Findings

### F1 — Fixed 2.5s splash gates interactivity (P0) — fixed

**Evidence (S1 Logging):** `launch` interval **2919.856 ms**.  
**Evidence (S1 App Launch lifecycle):**

| Period | Duration |
|--------|----------|
| Process creation | 396 ms |
| System interface init | 723 ms |
| `didFinishLaunchingWithOptions` | 163 ms |
| Initial frame rendering | 582 ms |
| Foreground — Active (start) | ~2.30 s |

**Code (before):** [`AppSessionCoordinator.bootstrap`](../ios-app/caocap/caocap/Services/AppSession/AppSessionCoordinator.swift) slept 2.5s then set `isLaunching = false`.  
**Fix:** dismiss on readiness after a ~1.2s brand minimum (matches launch entrance animation), hard-capped at 2.5s — not a fixed cosmetic sleep.  
**Confidence:** High (measured).  
**Scenarios:** S1.

### F2 — Per Mini-App `WKWebView` thumbnails (P0)

**Evidence:** Static — the former Mini-App node implementation embedded `HTMLWebView` at 375×667 scaled to 240. No shared `WKProcessPool`, viewport culling, or snapshot fallback was present. Root launch showed **no** `webViewMake` signposts, so S1 understated production project cost.
**Confidence:** High for architecture; Medium for numeric CPU until S3.  
**Scenarios:** S3, S5.

### F3 — Canvas gesture composition cost (P1)

**Evidence:** Static + S2 idle profile mentions SwiftUI / Material. During pan/zoom:

- The former `ConnectionLayer` rebuilt curved arrows every frame.
- Nodes use `.ultraThinMaterial` + dual gradients (shadow already removed as probe)
- 2000×2000 `SpaceSketchBG` under the scaled layer
- Mitigations already present: `@GestureState` pan, `CanvasNodeLayer.equatable()`, CA `DottedBackground`

**Confidence:** High for mechanism; Medium for ranking vs F2 until S3/S4.  
**Scenarios:** S2–S4.

### F4 — Synchronous cold-path work in launch (P1)

**Evidence:** Lifecycle `didFinishLaunching` 38–163 ms; AppConfiguration configures Firebase synchronously and kicks Gemma preload + auth Tasks ([`AppConfiguration.swift`](../ios-app/caocap/caocap/App/AppConfiguration.swift)). `AppRouter` sync-inits `ProjectStore` on cold boot. Signposts show root load/compile cheap; Firebase/dyld still dominate early process time (process creation + system init ~1.1 s on cold S1).  
**Confidence:** High.  
**Scenarios:** S1.

### F5 — Full-canvas live preview recompile (P2)

**Evidence:** `LivePreviewOrchestrator` walks **all** Mini-App nodes on every compile call; dirty check avoids rewriting identical HTML but still compiles each node. Measured **0.3 ms** on root; will grow with Mini-App count / HTML size. Also invoked from save debounce completion.  
**Confidence:** Medium (algorithm clear; cost scales).  
**Scenarios:** S3, S7.

### F6 — Second UIWindow FAB chrome (P2)

**Evidence:** Static — `GlobalFloatingChromeController` installs an alert-level `UIWindow` hosting SwiftUI chrome ([`GlobalFloatingChromeOverlay.swift`](../ios-app/caocap/caocap/App/Shell/GlobalFloatingChromeOverlay.swift)). Extra window/hosting cost at launch and hit-testing overhead. Logging captured hosting controller type during launch.  
**Confidence:** Medium.  
**Scenarios:** S1, S2.

### F7 — Copilot Live ReplayKit → JPEG @ 1 fps (P2)

**Evidence:** Static — main-actor encode path with CIContext + JPEG 0.7, max 768px ([`ScreenCaptureController.swift`](../ios-app/caocap/caocap/Services/CoCaptain/ScreenCaptureController.swift)). Instrumented as `screenCaptureEncode`. Not exercised in this pass.  
**Confidence:** Medium.  
**Scenarios:** S8.

### F8 — Debounced saves are healthy (P3 / non-issue so far)

**Evidence:** 500 ms debounce + background write; chat sidecar already kept out of canvas snapshots. No `save` signposts in 8s idle launch (expected).  
**Confidence:** Medium until S7.

## Non-issues (this pass)

- Root `projectLoad` / `livePreviewCompile` latency (milliseconds).
- Dotted grid (already CA-replicator optimized).
- Potential hangs table empty on 20s idle Time Profiler (S2).
- Marketing website performance.

## Historical recommendations (superseded)

These recommendations applied to the Mini-App implementation measured in this
audit. They are retained for provenance and are not the current product roadmap.

| Priority | Fix | Impact | Effort |
|----------|-----|--------|--------|
| 1 | ~~Replace fixed 2.5s splash with readiness-based dismiss~~ **Done** (1.2s brand min, 2.5s max) | High | Low |
| 2 | Mini-App thumbnails: viewport culling + snapshot/`UIImage` when zoomed out or offscreen; live `WKWebView` only for visible/focused nodes | High | Medium |
| 3 | Share `WKProcessPool` across `HTMLWebView`s; consider lower content process priority for thumbnails | Medium–High | Low |
| 4 | During canvas gestures: downgrade node chrome (solid fill instead of material/gradients); optionally freeze connection redraw to end of gesture | Medium | Medium |
| 5 | Dirty-only live preview compile (track changed node IDs) | Medium | Low–Medium |
| 6 | Defer Gemma preload until after interactive; keep Firebase configure but move non-critical work off first frame | Medium | Low |
| 7 | Revisit FAB second window vs overlay-in-hierarchy once sheets allow | Low–Medium | Medium |

## Historical next implementation slice (superseded)

**Mini-App thumbnail strategy (fixes 2–3):** viewport culling / snapshots + shared `WKProcessPool`, validated with an S3 stress project (8–20 Mini-Apps).

Re-measure `launch` signpost on device after the splash fix; expect roughly brand-minimum (~1.2s) from `didFinishLaunching` to dismiss when store load is already complete.

## Appendix — instrumentation added

- [`PerformanceSignposts.swift`](../ios-app/caocap/caocap/Services/AppEnvironment/PerformanceSignposts.swift)
- Wired in: `caocapApp`, `AppSessionCoordinator`, `ProjectStore`, `LivePreviewOrchestrator`, `ProjectSaveController`, `HTMLWebView`, `InfiniteCanvasView`, `CoCaptainAgentCoordinator`, `ScreenCaptureController`
- Tests: [`PerformanceSignpostsTests.swift`](../ios-app/caocap/caocapTests/AppEnvironment/PerformanceSignpostsTests.swift)
