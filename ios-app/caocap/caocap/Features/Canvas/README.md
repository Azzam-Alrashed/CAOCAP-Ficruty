# Canvas Feature

The canvas is currently a blank spatial workspace retained for the upcoming AI orchestration workflow editor.

## Ownership

- `ProjectStore` persists viewport state, checkpoints, and dormant legacy node data.
- `InfiniteCanvasView` renders the dotted background and owns pan/zoom gestures.
- `ViewportState` owns coordinate and zoom math.
- Legacy nodes are intentionally not rendered, searched, opened, or mutated.

## Verification

- Pan and pinch zoom remain responsive and persist after reopening.
- Center Canvas restores offset `(0,0)` and 100% zoom.
- A saved project containing legacy nodes still displays a blank canvas.
- CoCaptain and the Command Line expose no legacy node commands.
