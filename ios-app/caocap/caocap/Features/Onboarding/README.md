# Onboarding

First-run onboarding currently has two active phases:

1. **Intro** (`Intro/`) — the full-bleed motivational story screens.
2. **Personalization** (`Personalization/`) — co-pilot and experience selection.

After personalization, the app opens an empty root canvas.

`Tutorial/` retains the reusable, content-driven tutorial coordinator, popover,
anchor positioning, analytics hooks, and graduation UI. Its production catalog is
intentionally empty until the pivot defines new lessons. An empty catalog must stay
dormant and produce no UI, analytics, persistence, or celebration side effects.

Settings can replay Personalization or restart the complete Intro + Personalization
flow. Tutorial replay controls remain hidden while the production catalog is empty.
