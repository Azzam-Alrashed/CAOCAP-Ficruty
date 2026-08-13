# Contributing to CAOCAP

Thank you for helping build CAOCAP.

## Product Direction

CAOCAP is becoming an end-to-end command center for AI agents and computers.
Read [CAOCAP Product Direction](docs/PRODUCT_DIRECTION.md) before proposing
product or architecture changes.

The repository is transitional. Feature README files describe current code;
they are not product doctrine. New work should move toward conversational
multi-agent orchestration without preserving obsolete Mini-App behavior unless
compatibility is explicitly required.

## Technical Standards

### Modern SwiftUI

- Use Observation (`@Observable`) for shared view state.
- Keep views small and move business rules out of view bodies.
- Use structured concurrency and keep heavy work off the main actor.

### Project Structure

- `Models/` contains domain data.
- `Services/` contains business logic and infrastructure.
- `Features/` contains feature-specific UI and behavior.
- `Navigation/` contains workspace routing.

### Typed Boundaries

- Prefer typed identifiers and enums over string-based routing or actions.
- Keep side effects behind service or dispatcher boundaries.
- Preserve human review and safety checks for consequential agent actions.

## Pull Requests

- Explain what changed and why.
- Include screenshots or recordings for visible UI changes.
- Update the relevant documentation when behavior or architecture changes.
- Build the affected targets and run proportionate tests before submitting.

If a proposal changes the product model, discuss it in an issue before investing
in a large implementation.
