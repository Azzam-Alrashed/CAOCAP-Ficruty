# App Session

Owns root-level session orchestration for the running app: workspace routing hooks, global sheet flags, Command Line binding, and `AppActionDispatcher` registration.

## Ownership

- `AppSessionCoordinator` is the single session owner created by `ContentView`.
- `AppRouter` (in `Navigation/`) still owns workspace navigation and `ProjectStore` instances.
- `AppActionDispatcher` (in `Services/AppActions/`) still owns action definitions; the coordinator registers handlers that mutate session/UI state.
- `App/Shell/` contains SwiftUI modifiers and helpers that bind to the coordinator without adding business rules.

## Editing Guidance

- Add new global sheets or presentation flags to `AppSessionCoordinator`, then wire them in `App/Shell/AppSheetsModifier.swift`.
- Add new app-level actions by registering handlers in `AppSessionCoordinator.configureActions()` and exposing them through the dispatcher.
- Keep feature-specific UI in `Features/*`; keep cross-cutting session wiring here.
- When onboarding or CoCaptain presentation rules grow, prefer extracting focused helpers over expanding the coordinator indefinitely.
- First-run handoffs: `finishIntroFlow()` opens Personalization;
  `finishPersonalizationFlow()` opens the empty root canvas while the production
  tutorial catalog remains dormant.

## Related Tests

- `caocapTests/AppSession/AppSessionCoordinatorTests.swift`
