# CoCaptain Feature

CoCaptain is the agentic assistant for CAOCAP. It reads the current spatial project graph, streams model responses, executes safe app actions, and stages mutating graph actions for human review.

> **Current implementation:** This guide documents the existing iOS CoCaptain
> stack, including transitional project-graph and review infrastructure. The
> target product uses CoCaptain or CoStar as the conversational CoPilot for
> multi-agent workflows; see
> [`docs/PRODUCT_DIRECTION.md`](../../../../../docs/PRODUCT_DIRECTION.md).

## Ownership

- `Chat/` owns the adaptive CoCaptain sheet/inspector, shared chat visual language, grouped project conversation browser, lazy timeline, bubbles and on-demand message actions, typed progress/errors, context-aware input composer (Agent/Ask/Plan mode, optional `@` pin, route disclosure, and `cocaptain.chatMode` persistence), streaming task lifetime, direct command handling, and rendering Review Lifecycle effects.
- `AgentContract/` owns the machine-readable agent contract: coordinator, parser, output adapters, validator, typed review drafts, and shared agent/review/timeline models.
- `Review/` owns `CoCaptainReviewLifecycle` plus Review Bundle and pending action card rendering for human approval. The lifecycle owns staging, identity, decisions, conflicts, checkpoints, and node-session persistence.
- `Analysis/` owns structural parser warnings and project recommendations from the analyzer.
- `NodeAgent/` owns the embedded node-scoped chat interface.

Supporting services live outside this feature:

- `ProjectContextBuilder` serializes the canvas graph (titles, types, ids, links, positions) for the model.
- `CoCaptainConversationStore` persists project-scoped timelines, active conversation selection, and reading position in a versioned local sidecar keyed by canvas file name.
- `LLMService` routes and streams from Firebase AI Logic or local LiteRT-LM; `LocalGemmaModelManager` owns the downloaded model and local sessions. On-device Gemma is available on the iPhone 15 Pro family and newer iPhones, plus M-series iPads; unsupported devices use Gemini cloud.
- `AppActionDispatcher` performs available non-node app actions.

## Agent Flow

1. The user picks Agent, Ask, or Plan in the composer (persisted as `cocaptain.chatMode`, default Agent) and sends a message through `CoCaptainViewModel`.
2. Direct commands are resolved locally with `CommandIntentResolver` when possible. In Ask/Plan modes, mutating shortcuts are skipped so those messages go to the model as chat.
3. Otherwise, `CoCaptainAgentCoordinator` builds project context from the active `ProjectStore` using the turn plan’s detail level (implementation for Agent, product for Ask/Plan). In project scope, an optional `@` pin focuses the prompt on one node via `buildNodePromptContext` without switching to a node-scoped session. Context is graph metadata only — no Mini-App source dumps.
4. `CoCaptainTurnPlan` merges turn purpose with the selected `CoCaptainChatMode` to choose the effective execution policy. There is no keyword intent classifier.
5. `LLMService` streams text back into the current assistant bubble. Offline turns automatically use a ready local Gemma model without changing the saved online preference.
6. `CoCaptainAgentOutputAdapter` hides machine output while streaming and turns the final response into a directive. The ViewModel updates the assistant bubble from `onVisibleText` so prose streams live; XML/tool payloads stay hidden.
7. For structured turns, `CoCaptainAgentValidator` checks action IDs and action safety. Executable work is not forced for standard Agent chat; pure prose is allowed.
8. Safe actions execute immediately when autonomous; validated pending actions leave the coordinator as a typed review draft.
9. `CoCaptainReviewLifecycle` stages that draft into a canonically identified Review Bundle without mutating the canvas or performing pending actions.
10. An explicit approval performs the pending app action through `AppActionDispatcher`. Undo and checkpoints remain available after Apply.

The core contract is human-in-the-loop graph mutation via AppActions. Do not auto-apply mutating actions without explicit user approval.
Free-usage and subscription prompts are product CTA timeline items, not review bundles.

## Conversation Continuity

Project-scoped CoCaptain keeps a local conversation archive outside
`ProjectSnapshot`, so conversation attachments and long timelines do not slow
ordinary canvas saves or require a project schema migration. Each canvas has an
independent active conversation, and builders can create, search, switch,
rename, and delete chats without affecting nodes, checkpoints, or snapshots.

Switching or restoring a conversation resets the underlying model session, then
replays a bounded recent transcript on the next turn. Review Bundles remain
attached to the conversation where they were proposed and are restored into
the Review Lifecycle before a decision can be made. Node-scoped messages continue
to use `NodeAgentState`.

Explicit **Stop** cancels a turn. Dismissing CoCaptain does not: the shared view
model keeps streaming, persists the completed result, and shows it when the
surface reopens.

### Clarification Flow (Never Reject, Always Guide)

Intent-level ambiguity ("make it pop") is handled by the model with a
`clarifying_question` / `ask_clarifying_question` contract element, rendered as
a tappable option card. Picking an option sends it as the user's next message.
Validation failures also append a locally-built recovery question so every
failure path has a tappable next step.

## Turn Execution Modes

`CoCaptainTurnPlan` merges `CoCaptainTurnPurpose` with `CoCaptainChatMode` into a `CoCaptainTurnExecutionPolicy` in `CoCaptainAgentModels.swift`. The coordinator reads `turnPlan.effectivePolicy` instead of hardcoding exceptions. Standard turns follow the composer’s Agent/Ask/Plan selection (`chatMode`, default Agent, persisted under `cocaptain.chatMode`). Project-scoped and node-scoped CoCaptain share that same stored mode.

| Policy | When | Structured tools | Enforce work | Agentic retry | Execute / stage | Context |
|------|------|------------------|--------------|---------------|-----------------|---------|
| Agent | Standard turn + `.agent` mode | Yes | No — pure chat OK | Yes — invalid structured output only | Yes when the model emits work | Implementation |
| Ask | Standard turn + `.ask` mode | No | No | No | No — prose only | Product |
| Plan | Standard turn + `.plan` mode | No | No | No | No — outline prose only | Product |

Do not reintroduce keyword intent classification. Agent mode must stage reviewable AppActions from structured fixtures even when the user message lacks verbs like “make” or “build,” and must finish pure prose turns without “must include an edit” failures.

Ask, Plan, and conversational turns still receive canvas context and mode/purpose prompt instructions, but the agent contract block is omitted from the LLM prompt and action catalogs / in-turn tool executors are not passed. Plan prompts steer toward numbered step outlines without implementing changes. If the model disobeys and emits `cocaptain_actions`, the coordinator ignores the payload and surfaces visible prose only. Connection-fallback “edits unavailable” notices apply only when the turn expected canvas work (`requiresDegradedConnectionNotice`), not Ask/Plan.

When adding a new turn purpose, declare its execution policy in the same enum switch as its prompt instructions. When changing mode → policy mapping, update the turn-plan / coordinator policy tests.

## Structured Payload Contract

There are two wire formats for app actions and clarifying questions; both converge on the same `CoCaptainAgentPayload`, so the validator, review builder, and conflict guard are format-independent.

### Native tools (preferred)

The model is instructed to use Gemini function calling:

- `request_app_action(actionId, executionMode, …args)` — navigation and graph mutations. Mutating actions use `executionMode=pending`.
- `ask_clarifying_question(prompt, options[])` — one short question with 2–4 outcome-phrased options.

Legacy node-edit calls are unavailable while the orchestration workflow editor is rebuilt.

### XML block (fallback, and the first-release format for local LiteRT-LM)

The model may include one trailing XML block:

```xml
<cocaptain_actions>
  <assistant_message>Visible fallback text.</assistant_message>
  <clarifying_question prompt="One short question when the request is too vague to act on">
    <option>First concrete outcome</option>
    <option>Second concrete outcome</option>
  </clarifying_question>
  <safe_actions>
    <action id="go_root" />
  </safe_actions>
  <pending_actions>
  </pending_actions>
</cocaptain_actions>
```

Rules:

- The parser uses the last `cocaptain_actions` tag in the response.
- Malformed XML falls back to visible text with no payload.
- `safeActions` may only contain available, non-mutating, autonomous actions.
- `pendingActions` are shown for review before execution and are required for mutating or non-autonomous app actions.
- `clarifying_question` needs a non-empty `prompt` and 2–4 non-empty options; malformed questions degrade to prose. A question-only payload counts as valid agentic work, and a question always takes precedence over pending actions in the same turn (the actions are dropped). The same precedence applies to `ask_clarifying_question` vs `request_app_action` function calls.
- Prompt rules keep the mentor tone: never refuse, use plain non-technical language, and ask exactly one clarifying question with outcome-phrased options when unsure.

Invalid structured payloads are not partially executed. The coordinator retries once with parse or validation feedback. If the retry is still invalid, the user sees a recovery question rather than a silent no-op or unsafe action.

Firebase function calling is the preferred path for app actions through `request_app_action` and clarifying questions through `ask_clarifying_question`. The XML block remains the compatibility format until tool usage dominates the output-source telemetry.

If this payload changes, update parser/coordinator tests and the prompt contract in `LLMService`.

## Review Safety

Pending AppActions stage without side effects. On every approval, the lifecycle re-checks that the action is still available in the current dispatcher context before performing it. Failed or unavailable actions become terminal conflicted review items instead of silently no-oping.

Preserve this conflict guard when refactoring review state.

## Node-Scoped Review Persistence

Unresolved Review Bundles on node-scoped CoCaptain sessions are JSON-encoded by
`CoCaptainReviewLifecycle` into `NodeAgentState.pendingReviewBundlesData` and
restored when the node CoCaptain panel reopens. Project-scoped Review Bundles are stored
inside their `CoCaptainConversationStore` timeline sidecar and restored when
that conversation becomes active. Auto-triggered agent pipeline runs stage
through the same lifecycle, and canvas `awaitingReview` state is derived from
persisted unresolved records.

Clearing node chat history also clears persisted pending review bundles.

Review cards with a target node include **View on Canvas**, which flies the workspace viewport to that node while CoCaptain stays open.

## Editing Guidance

- Keep sheet UI rendering in `Chat/CoCaptainView`; keep timeline and async state in `Chat/CoCaptainViewModel`.
- Keep Review Bundle staging, decisions, conflicts, checkpoints, and node persistence behind the `CoCaptainReviewLifecycle` interface.
- Assistant chat bubbles may render Markdown for readable explanations, but raw structured payloads must stay hidden.
- Keep model orchestration in `AgentContract/CoCaptainAgentCoordinator`.
- Keep payload parsing deterministic and tolerant of malformed model output.
- Prefer adding new app capabilities through `AppActionDispatcher` and `AppActionID`.
- Add tests when changing parser fences, action classification, review item states, or retry behavior.
- Do not leak raw structured payload text into the visible chat timeline.
- Be careful with cancellation: only explicit Stop cancels streaming; dismissing and reopening the chat must preserve the active turn.
- Keep project conversation persistence in `CoCaptainConversationStore`; do not add large chat timelines or attachments to `ProjectSnapshot`.
- Keep validation near the coordinator boundary. SwiftUI views should render review state, not decide whether model output is safe.
- Keep raw model wire formats behind output adapters. The coordinator should consume directives, not Firebase/Gemini-specific response parts.
- Do not reintroduce legacy node mutation actions; the next workflow system will define a new contract.
- Keep free-tier quota enforcement in `LLMService`/`TokenUsageLimiter`; CoCaptain UI should only surface quota state when a hard limit blocks a request, then route upgrades through a product CTA. Review bundles are reserved for workspace changes and assistant-proposed app actions.

## Verification Checklist

- Send a normal chat message and confirm streaming text appears.
- Dismiss CoCaptain during streaming, reopen it, and confirm the same turn continues.
- Create, rename, search, switch, and delete project conversations; confirm each canvas restores its own active chat.
- Confirm assistant Markdown renders cleanly and message text can be selected, copied, shared, retried, and rated.
- Confirm user messages can be copied, restored into the composer for editing, and resent.
- Stop a response and confirm its partial prose remains with a recoverable Continue card.
- Simulate model/network/attachment/quota failures and confirm each has distinct recovery copy.
- Open the input plus menu and confirm quick prompts send once.
- Switch Agent ↔ Ask from the composer chip; confirm the placeholder updates and the choice survives relaunch (default Agent).
- Pin a node with `@` in project CoCaptain; confirm the next turn’s context focuses that node; clear the pin and confirm full-canvas context returns.
- In Agent mode, ask to rename or connect nodes and confirm a review bundle can stage Apply.
- Switch to Ask and send the same mutation prompt; confirm prose-only reply with no review staging.
- Open node-scoped CoCaptain and confirm it uses the same Agent/Ask/Plan selection.
- Send a direct navigation command and confirm safe actions execute or review appears as expected.
- Ask for a graph change and confirm review items are created rather than auto-applied.
- Apply a pending rename/delete/connect action and confirm the canvas updates.
- Confirm resolved Review Bundles collapse and applied mutating actions expose Undo while the undo manager can reverse them.
- Scroll up during streaming and confirm the timeline does not pull away; use Jump to Latest and confirm the reading position restores after switching chats.
- On regular-width iPad, confirm CoCaptain stays beside the canvas as an inspector; on compact width, confirm the detented sheet remains.
- Switch projects while streaming and confirm the old task cancels while each project’s archived history remains isolated.

## Test Targets

Useful test coverage for this feature:

- parser success, malformed XML fallback, and trailing fence behavior.
- coordinator safe action execution and review bundle generation for pending AppActions.
- validator rejection for unknown actions, unsafe safe actions, unavailable pending actions, and duplicate/overlapping actions.
- function-call adapter mapping for safe actions, pending actions, malformed arguments, and clarifying questions.
- legacy `propose_node_edit` drop diagnostics.
- Review Lifecycle staging and transitions, including unavailable actions, bulk decisions, and node-only persistence.
- direct command handling for autonomous vs review-required actions; Ask skips mutating short-circuits.
- retry behavior when the structured payload is present but invalid (Agent).
- Agent pure-prose turns finish without forced action retries; Agent stages reviews from structured fixtures without keyword verbs.
- Ask never stages a review bundle from model output; Ask uses product context and omits degraded edit notices.
- turn-plan policy mapping for Agent, Ask, and Plan.
- conversation archive encoding, per-project isolation, unsupported schema handling, and deletion.
- ProjectContextBuilder graph metadata (no code-section dumps).
