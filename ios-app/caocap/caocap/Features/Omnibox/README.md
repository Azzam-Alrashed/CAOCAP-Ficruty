# Omnibox Feature

The Omnibox is CAOCAP's command palette. It gives users a fast way to search available app actions and gives CoCaptain a shared local command vocabulary.

## Ownership

- `CommandPaletteView` renders the modal command surface, search field, result list, and row selection states.
- `CommandPaletteViewModel` owns query state, filtered actions, selected index, presentation state, action emission, and unmatched-query prompt emission.
- `AppActionDispatcher` is the central registry and execution boundary for actions.
- `CommandIntentResolver` maps short natural-language commands to `AppActionID` values without calling the LLM.

The Omnibox should not directly mutate app state. It emits `AppActionID` values; the app shell or dispatcher performs the actual work.

## Command Flow

1. The app shell configures `AppActionDispatcher` with concrete handlers.
2. The command palette receives `AppActionDefinition` values from the dispatcher.
3. `CommandPaletteViewModel` filters actions by localized title and canonical title, searches canvas nodes via `NodeSearchIndex`, and surfaces creatable node types via `NodeCreationCatalog`.
4. The user selects an action by tapping, submitting, or keyboard navigation.
5. If the query matches a listed command, the view model emits the selected `AppActionID` through `onExecute`.
6. If the query has no listed command matches, the view model emits the trimmed query through `onSubmitPrompt`, and the app shell opens CoCaptain with that prompt.
7. `AppActionDispatcher.perform(_:source:)` validates source safety and runs configured app actions.

## Intent Matching

`CommandIntentResolver` supports local phrase matching for commands such as "open settings" or Arabic equivalents. It normalizes case, punctuation, and diacritics, then checks conservative aliases.

Important rules:

- only registered actions can resolve;
- matching **Go Back** and **Go to Root** actions are pinned ahead of canvas-node
  and creation results so navigation remains the default queried result;
- explicit negations such as "do not create a project" return `nil`;
- single-word aliases require exact matches;
- multi-word aliases may match inside longer requests;
- aliases should stay conservative to avoid turning casual chat into app actions.

## Safety Boundary

`AppActionDefinition` has two safety flags:

- `isMutating`: the action changes user data, project structure, or other durable state.
- `allowsAutonomousExecution`: CoCaptain or another trusted non-user source can run the action without a review item.

Automatic agent calls are blocked when an action is mutating or not marked autonomous. User-triggered commands and reviewed agent actions may continue through the same dispatcher.

Preserve this boundary when adding commands.

## Options Visibility

In search (capsule) mode, the results card defaults to listing available options as soon as the omnibox opens. Users can turn this off in **Settings → Look & Feel → Show Options Immediately**, so options only appear after typing starts. Mini-App preview tools always remain visible when present. Persistence key: `omnibox.showOptionsWhenEmpty` (`@AppStorage`, default `true`).

## Editing Guidance

- Add new actions to `AppActionID`, `availableActions`, `configure(...)`, and the dispatcher `switch`.
- Add aliases in `CommandIntentResolver` only when the phrase is unlikely to be ordinary chat.
- Keep `CommandPaletteView` presentational; search and selection state belong in the view model.
- Keep side effects out of `CommandPaletteViewModel`; emit IDs or prompts and let the dispatcher/app shell execute.
- Update CoCaptain tests when changing command aliases, negation behavior, or action safety flags.
- Replace production `print(...)` diagnostics with `Logger` when touching execution paths.

## Verification Checklist

- Open the palette and confirm options appear immediately by default (empty query).
- In Settings → Look & Feel, turn off **Show Options Immediately** and confirm options only appear after typing.
- Open the palette and confirm the search field focuses automatically.
- Type partial localized and canonical action names and confirm filtering works.
- Move selection up/down and confirm it wraps correctly.
- Press Return and confirm the selected action executes once.
- Type an unlisted command, press Return, and confirm CoCaptain opens with that prompt.
- Tap outside the palette and confirm query/selection reset on close.
- Try direct commands through CoCaptain, including negated phrases, and confirm safe vs reviewed behavior.

## Test Targets

Useful test coverage for this feature:

- filtering by localized and canonical titles;
- selection movement and wraparound;
- confirm selection with empty and non-empty results;
- unmatched non-empty queries emit trimmed CoCaptain prompts;
- `CommandIntentResolver` English and Arabic aliases;
- negation handling;
- dispatcher blocking of automatic mutating actions;
