# /share command spec and implementation plan

> Status: shipped, with two small gaps. This doc is now a follow-up tracker.
> Re-spec'd 2026-04-30 against the harness/strategies/core split and verified against the actual landed code.

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
- subagent activity, including nested subagent structure (renderer-side; persistence path is the open gap below)

It excludes internal-only bookkeeping such as title generation events, observability spans, token/cost internals, and unrelated raw metadata.

## Layer placement (landed)

| Concern | Layer | Package |
|---|---|---|
| Normalized transcript model + builder | harness | `packages/glue_harness/lib/src/share/share_models.dart`, `share_transcript_builder.dart` |
| Session event normalizer (prefers `summary` over `content` for tool results) | harness | `packages/glue_harness/lib/src/session/session_event_normalizer.dart` |
| Markdown renderer | harness | `packages/glue_harness/lib/src/share/renderer/markdown_renderer.dart` |
| HTML renderer + template + CSS | harness | `packages/glue_harness/lib/src/share/renderer/html_renderer.dart`, `html/share_page_template.html`, `html/share_page.css`, `html/share_html_assets_loader.dart` |
| Export coordinator | harness | `packages/glue_harness/lib/src/share/session_share_exporter.dart` |
| Gist publisher | harness | `packages/glue_harness/lib/src/share/gist_publisher.dart` |
| Slash command wiring | CLI surface | `cli/lib/src/commands/builtin_commands.dart` (`share` entry, line 90, registered with `shareAction`) |
| Barrel exports | harness public API | `packages/glue_harness/lib/glue_harness.dart` |
| Subagent event types | core | `packages/glue_core/lib/src/session_event.dart` (`SubagentSpawnedEvent`, `SubagentEventForwardedEvent`, `SubagentCompletedEvent`) |
| ACP mapping for subagent events | server | `packages/glue_server/lib/src/acp/event_mapping.dart` |

## Verified shipped

Confirmed against `claude/architect-harness-layers-maSVJ` as of 2026-04-30:

- ✅ `share_models.dart` with `ShareEntry` / `ShareEntryKind` (kept independent of `glue_core`'s `Message` so renderers don't pull in chat semantics).
- ✅ `share_transcript_builder.dart` consuming persisted `SessionEvent`s via `normalizeSessionEvents`.
- ✅ Tool-result content selection: the normalizer (`session_event_normalizer.dart`) prefers a non-empty trimmed `summary` over `content` (`_visibleToolResultText`).
- ✅ `markdown_renderer.dart` emits per-entry anchors: `<a id="entry-N"></a>`.
- ✅ `html_renderer.dart` emits per-entry section ids and anchor links: `<section ... id="entry-N">…<a href="#entry-N">#N</a>`.
- ✅ HTML renderer already has CSS classes for `share-entry-subagent-group` and `share-entry-subagent-message`, and renders `share-children` for nested entries — the renderer is ready to display subagent nesting once the data flows in.
- ✅ HTML template + CSS bundled as static assets, loaded via `share_html_assets_loader.dart`.
- ✅ `session_share_exporter.dart` orchestrating builder → renderer → file writes.
- ✅ `gist_publisher.dart` for the `gh` integration; `cli/test/share/gist_publisher_test.dart` already covers 4 cases.
- ✅ CLI slash command `/share` wired through `shareAction` in `builtin_commands.dart:90`.
- ✅ Subagent event types defined in `glue_core` (`SubagentSpawnedEvent`, `SubagentEventForwardedEvent`, `SubagentCompletedEvent`).
- ✅ ACP server already maps subagent events: `SubagentEventForwardedEvent` unwraps to its inner event (`packages/glue_server/lib/src/acp/event_mapping.dart:50-52`).
- ✅ Test coverage in `cli/test/share/` totalling 681 lines across 7 files: `gist_publisher_test.dart`, `html_share_renderer_test.dart`, `markdown_share_renderer_test.dart`, `session_share_exporter_test.dart`, `session_share_spec_test.dart`, `share_html_assets_loader_test.dart`, `share_transcript_builder_test.dart`.
- ✅ Builder test explicitly asserts the current contract: `ignores raw subagent-like events until a persisted schema exists` (confirms the open gap below is intentional, not an oversight).
- ✅ Builder test exercises the subagent-fixture path through `fromEntries(...)` for nested groups.

## Open gaps

### 1. Subagent persistence — ✅ shipped

Tracked separately in `2026-04-30-subagent-event-persistence.md` and
implemented in `feat(harness): persist subagent activity to
conversation.jsonl`. `AgentManager` now emits
`subagent_spawned` / `subagent_event` / `subagent_completed` JSON rows
through an `onPersistEvent` sink wired by the CLI to
`_sessionManager.logEvent`. The transcript builder consumes them via the
session-event normalizer and produces nested
`ShareEntryKind.subagentGroup` entries. The CLI session resume path
reconstructs `_SubagentGroup` blocks from the same JSONL on resume.

Note: this used the simpler "Option A" (untyped JSON rows) rather than
typed `SubagentSpawnedEvent` / `SubagentEventForwardedEvent` /
`SubagentCompletedEvent`. The typed `SessionEvent` classes in
`glue_core` remain a forward-looking ACP boundary contract; migrating
`SessionStore.logEvent` to consume typed events is a separate larger
refactor and does not block share output.

### 2. Long tool output collapse — ✅ shipped

`ShareHtmlRenderer` now accepts `collapseToolOutputAfterLines` (default
30) and wraps tool result blocks above that threshold in
`<details class="share-collapsible"><summary>Show output (N
lines)</summary>…</details>`. The summary control is dimmed and clickable
via CSS rules in `share_page.css`. Setting the threshold to 0 disables
the collapse entirely. Tests cover short passthrough, long collapse,
and the disable knob.

## Test location migration (housekeeping)

Tests for share live in `cli/test/share/` because they predate the harness
extraction. The harness package currently has no `test/` directory at all
(`packages/glue_harness/test` is empty / nonexistent). Two options:

- **Now:** migrate `cli/test/share/*.dart` to
  `packages/glue_harness/test/share/*.dart`, since the code under test is in
  the harness package. This also creates the harness's `test/` tree, which
  other plans (thinking-tokens, prompt-caching, ask-user, context-inspector)
  expect to exist.
- **Later:** leave them where they are; risk is that future contributors
  won't find them when modifying harness share code, and `dart test` runs
  per-package will not exercise the share suite as part of the harness gate.

Recommendation: migrate. This is a one-PR mechanical move; imports may need
adjusting from `package:glue/...` to `package:glue_harness/...` and
`package:glue_core/...` where appropriate.

## Migration notes from the original plan

- Original plan placed share code under `cli/lib/src/share/`. Actual landed location is `packages/glue_harness/lib/src/share/`. Right home — the renderers are surface-agnostic.
- Templates live in `packages/glue_harness/lib/src/share/html/` rather than a top-level `templates/`. Loaded via static assets through `share_html_assets_loader.dart`, sidestepping `Platform.script` heuristics. The bundled-assets plan generalizes this pattern further.
- We chose static asset loading instead of `mustache_template`. The remaining string interpolation is small enough that adding a templating dependency is not worth it.

## Acceptance criteria for "fully done"

1. ✅ `AgentManager` emits subagent spawn/event/completion onto the parent session log; the transcript builder produces nested subagent groups from real persisted sessions. Shipped via `2026-04-30-subagent-event-persistence.md`.
2. ✅ Long tool outputs collapse via `<details>` over a configurable threshold (HTML).
3. **Pending:** Share tests live in `packages/glue_harness/test/share/` (currently in `cli/test/share/`). Pure housekeeping move.

A future ACP `session/export` request, returning rendered Markdown/HTML or
a `resource_link` to a saved file, lands when an ACP client needs it. No
new harness work — the renderers already produce strings.
