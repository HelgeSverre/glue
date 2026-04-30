# /share command spec and implementation plan

> Status: largely shipped. This doc is now a follow-up tracker.
> Re-spec'd 2026-04-30 against the harness/strategies/core split and the actual landed code.

## Goal

Add a `/share` slash command that exports the current session's visible conversation history as:

- HTML
- Markdown
- optional GitHub gist via `gh`

The export is for sharing the readable conversation transcript, not for dumping all session metadata or observability logs. It includes:

- user messages
- assistant messages
- tool calls
- tool results
- subagent activity, including nested subagent structure

It excludes internal-only bookkeeping such as title generation events, observability spans, token/cost internals, and unrelated raw metadata.

## Layer placement (landed)

| Concern | Layer | Package |
|---|---|---|
| Normalized transcript model + builder | harness | `packages/glue_harness/lib/src/share/share_models.dart`, `share_transcript_builder.dart` |
| Markdown renderer | harness | `packages/glue_harness/lib/src/share/renderer/markdown_renderer.dart` |
| HTML renderer + template + CSS | harness | `packages/glue_harness/lib/src/share/renderer/html_renderer.dart`, `html/share_page_template.html`, `html/share_page.css`, `html/share_html_assets_loader.dart` |
| Export coordinator | harness | `packages/glue_harness/lib/src/share/session_share_exporter.dart` |
| Gist publisher | harness | `packages/glue_harness/lib/src/share/gist_publisher.dart` |
| Slash command wiring | CLI surface | `cli/lib/src/commands/builtin_commands.dart` (`share` entry registered with `shareAction`) |
| Barrel exports | harness public API | `packages/glue_harness/lib/glue_harness.dart` |

The share renderers and exporter live in the harness so any surface — CLI today, `glue serve` (ACP) tomorrow — can produce the same output. The slash command itself is in the CLI surface, since slash commands are a CLI concept.

## What has shipped

Verified present in `claude/architect-harness-layers-maSVJ` as of 2026-04-30:

- `share_models.dart` with the share entry types and `ShareEntryKind` enum (kept independent of `glue_core`'s `Message` so renderers don't pull in chat semantics)
- `share_transcript_builder.dart` consuming persisted `SessionEvent`s
- `markdown_renderer.dart` and `html_renderer.dart`, both using the shared `renderer_support.dart`
- HTML template + CSS bundled as static assets, loaded via `share_html_assets_loader.dart`
- `session_share_exporter.dart` orchestrating builder → renderer → file writes
- `gist_publisher.dart` for the `gh` integration
- CLI slash command `/share` wired through `shareAction` in `builtin_commands.dart`

## What still needs doing (open follow-ups)

### 1. Subagent event persistence

The transcript builder still treats subagent activity as opportunistic
fixture data — there is no persisted `SubagentStartEvent` /
`SubagentMessageEvent` / etc. in `glue_core/session_event.dart`.

Concrete plan:

- Add typed subagent events to `glue_core/session_event.dart`:
  - `SubagentStartedEvent { SubagentId id; SubagentId? parentId; String agentRole; ... }`
  - `SubagentMessageEvent { SubagentId id; String text; ... }`
  - `SubagentToolCallEvent { SubagentId id; ToolCallId callId; ... }`
  - `SubagentToolResultEvent { SubagentId id; ToolCallId callId; ToolResult result; }`
  - `SubagentFinishedEvent { SubagentId id; }`
- Have `AgentManager` (`packages/glue_harness/lib/src/agent/agent_manager.dart`) emit these events on the parent session's event sink.
- Update `share_transcript_builder.dart` to map them into `ShareEntryKind.subagentGroup` / `subagentMessage` with `parentId`-driven nesting.
- Add tests in `packages/glue_harness/test/share/share_transcript_builder_test.dart` for nested subagent structures.

### 2. Tool-result content selection

Confirm the builder uses `summary` when present and falls back to `content`.
If not already covered, add a test in
`packages/glue_harness/test/share/share_transcript_builder_test.dart`.

### 3. Raw HTML in assistant markdown

Decide: pre-escape or accept as trusted local content. Today's renderer uses the `markdown` package, which does not sanitize. For local file exports the risk is contained, but document the choice in `html_renderer.dart` and add a test asserting the chosen behavior.

### 4. Long tool output collapse

Add a `<details>` wrapper for tool output over a configurable line threshold in `html_renderer.dart`. Pure renderer change.

### 5. Markdown anchors for parity

Confirm Markdown export emits `<a id="entry-n"></a>` anchors per entry. If not, add and test.

### 6. Gist publishing UX

`gist_publisher.dart` is in place. Gaps:

- error reporting when `gh` is missing or unauthenticated
- selecting which artifact to publish (Markdown only by default)
- tests covering the parsing of `gh gist create` output for the resulting URL

Add `packages/glue_harness/test/share/gist_publisher_test.dart` if not yet present.

### 7. ACP `session/export` surface (future)

Once subagent events persist, add an ACP request in
`packages/glue_server/lib/src/acp/` that returns the rendered Markdown/HTML
(or a `resource_link` to a saved file). No new harness work — the renderers
already produce strings.

## Migration notes from the original plan

- The original plan placed share code in `lib/src/share/` of the CLI package. The actual landed location is `packages/glue_harness/lib/src/share/`. This is the right home: the renderers are surface-agnostic and the harness is the only place all surfaces share.
- Templates live in `packages/glue_harness/lib/src/share/html/` rather than `templates/`. They are loaded via a generated assets approach in `share_html_assets_loader.dart`, sidestepping `Platform.script` heuristics. (The bundled-assets plan generalizes this pattern further.)
- We chose static asset loading instead of `mustache_template`. The remaining string interpolation is small enough that adding a templating dependency is not worth it.

## Test plan (status)

| Test file | Status |
|---|---|
| `packages/glue_harness/test/share/share_transcript_builder_test.dart` | exists; extend for subagent events once those persist |
| `packages/glue_harness/test/share/markdown_renderer_test.dart` | confirm coverage of nested subagent groups, anchors, empty transcripts |
| `packages/glue_harness/test/share/html_renderer_test.dart` | confirm coverage of self-contained HTML, anchor ids, escaping, nested subagents, collapse-long-output if implemented |
| `packages/glue_harness/test/share/session_share_exporter_test.dart` | should cover successful md/html writes, no-active-session error, empty-conversation error |
| `cli/test/commands/builtin_commands_test.dart` | should cover `/share`, `/share html`, `/share md`, invalid args, busy-state error |
| `packages/glue_harness/test/share/gist_publisher_test.dart` | add if missing — missing `gh`, unauthenticated `gh`, URL parse |

## Output naming and defaults (no change)

- `glue-session-<session-id>.html`
- `glue-session-<session-id>.md`
- Default output directory: current working directory
- `/share gist` publishes Markdown by default

## Acceptance criteria for "fully done"

This plan is fully closed when:

1. Subagent events are persisted as typed `SessionEvent` variants in `glue_core` and emitted by `AgentManager`.
2. The transcript builder renders nested subagent groups from real persisted events, not fixtures.
3. Renderer behavior around raw HTML in assistant markdown is documented and tested.
4. Long tool outputs collapse via `<details>` over a configurable threshold (HTML).
5. Markdown export emits per-entry anchors.
6. `gist_publisher.dart` has full error-path test coverage.
7. (Optional) `glue serve` exposes `session/export` with the same renderer output.

Items 1–6 are the realistic next batch. Item 7 lands when the ACP surface needs it.
