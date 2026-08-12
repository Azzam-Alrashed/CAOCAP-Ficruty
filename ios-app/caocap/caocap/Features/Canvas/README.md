# Canvas Feature

The Canvas feature is CAOCAP's spatial workspace. It renders the infinite canvas, nodes, sub-canvases, links, and node detail sheets. Mini-App nodes are placeholders for future workflow graph content.

## Ownership

- `ProjectStore` owns durable canvas state: nodes, viewport offset, viewport scale, and persistence.
- `InfiniteCanvasView` owns transient interaction state: active viewport gestures, selected node, node drag offsets, and whether a node is currently being dragged.
- `ViewportState` owns pan and zoom math. Keep gesture calculations here instead of spreading geometry math through views.
- `NodeView` renders one node. It should stay presentational.
- `NodeDetailView` opens Mini-App nodes into a large-sheet shell with Agent, Settings, and Back to Canvas (via the shared omnibox).
- Providers under `Providers/` define the empty root canvas, XO canvas, and generic
  Mini-App starter nodes (no embedded HTML runtime).

## Data Flow

1. `ContentView` provides an active `ProjectStore` from `AppRouter`.
2. `InfiniteCanvasView` renders `store.nodes`.
3. Tapping a Mini-App opens its large-sheet shell, tapping an action node calls
   `onNodeAction`, and tapping a subcanvas portal opens its linked canvas file.
4. Mini-App tools route through the omnibox. CoCaptain mutates the graph through AppActions (`create_node`, `rename_node`, `connect_nodes`, etc.), not code-section patches.
5. `ProjectStore` debounces saves. There is no live HTML compile/preview pipeline.
6. `ConnectionLayer` draws arrows from `nextNodeId` and `connectedNodeIds`.

Views should call store methods rather than mutating `store.nodes` directly.

## Coordinate Model

- `SpatialNode.position` is a canvas-space offset from the visible center.
- `ViewportState.offset` and `ViewportState.scale` transform the whole node layer.
- `ConnectionLayer` manually converts node positions into screen-space coordinates so links do not clip during pan and zoom.
- The canvas forces left-to-right layout where spatial math depends on predictable coordinates.

When changing gestures or connection rendering, test pan, zoom, drag, and arrow placement together.

## Editing Guidance

- Put reusable node graph construction in `Providers/`, not in `AppRouter` or large views.
- Keep `NodeView` focused on visual rendering. Put editing behavior in sheet views or store methods.
- Keep `NodeDetailView` focused on Mini-App tool routing; put persistent mutations in store methods.
- If adding a node type, update `SpatialNode`, `NodeDetailView`, `ProjectContextBuilder`, and any CoCaptain AppAction / context behavior that should understand it.

## Verification Checklist

- Create/open a project and confirm nodes render at the expected zoom.
- Drag a node, pan the canvas, pinch zoom, then reopen the project and verify persisted state.
- Open a Mini-App node full-screen and confirm FAB tap and sparkles open the omnibox; verify MINI-APP rows route to Agent, Settings, and Back to Canvas (no Code / HTML preview).
- Check connection arrows while dragging nodes and at multiple zoom levels.
- Verify action nodes on the Home screen navigate to correct destinations.
- Share/export offers `.caocap` only.

## Test Targets

Useful test coverage for this feature:

- `ViewportState` pan and zoom math.
- save/load of node positions, links, and viewport state.
- provider output for the empty root canvas.
