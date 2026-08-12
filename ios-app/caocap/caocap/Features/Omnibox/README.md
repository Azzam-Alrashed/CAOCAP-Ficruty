# Command Line Feature

The Command Line is CAOCAP's terminal-like intent surface. It presents one input with no options or autocomplete list.

## Command Flow

1. The user enters text and presses Return.
2. `CommandIntentResolver` checks the text against conservative aliases for registered app actions.
3. A recognized command, such as `open settings`, executes locally through `AppActionDispatcher`.
4. Unmatched text is sent to the selected CoPilot as a request.

The view never mutates app state directly. `CommandPaletteViewModel` emits an action ID or CoPilot request, and the app session performs it.

## Safety

`AppActionDispatcher` remains the execution boundary. Agent-triggered actions must satisfy the action's mutation and autonomous-execution rules. User-entered commands execute with the `.user` source.

## Editing Guidance

- Add app commands to `AppActionID`, `AppActionDispatcher.availableActions`, and the session's dispatcher registrations.
- Add aliases in `CommandIntentResolver` only when they are unlikely to be ordinary conversation.
- Keep option lists and autocomplete out of this surface.
- Keep side effects out of `CommandPaletteViewModel`.

## Verification

- Open the Command Line and confirm only the input is shown.
- Enter `open settings` and confirm Settings opens.
- Enter an unmatched request and confirm it opens the selected CoPilot with that request.
- Tap outside and confirm the Command Line dismisses and clears its input.
- Confirm dictation still fills the input.
