# Session Title Reevaluation Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-20

## Goal

Improve Glue session titles so they can evolve with the conversation instead of
locking onto the first user message forever.

The desired behavior is:

- generate a fast initial title early
- treat that title as provisional while context is still thin
- re-evaluate once the session has more evidence
- stabilize the title after the second pass
- allow an explicit `/rename` command to set the session title manually
- never overwrite a user-set title
- once a session has been manually renamed, disable any future auto-title generation or reevaluation for that session
- avoid title churn from repeated background rewrites

This plan focuses on a pragmatic two-pass design, not a fully dynamic
continuously-renaming system.

## Why this is needed

Current Glue behavior generates a title exactly once, from the first user
message, and never revisits it.

That works for well-scoped prompts but fails for real conversations where the
opening message is vague and the actual task becomes clear only after the first
assistant response, tool usage, or a second user turn.

Examples of bad current outcomes:

- "Inspect this issue" becomes the permanent title for a session that ends up
  implementing session-title regeneration.
- "help me debug this" becomes the permanent title even after the session
  becomes specifically about Docker test flakiness.
- resumed sessions without titles only backfill from the first historical user
  message, which has the same weakness.

## Current code context

Relevant files:

- `cli/lib/src/app/event_router.dart`
- `cli/lib/src/app/session_runtime.dart`
- `cli/lib/src/session/session_manager.dart`
- `cli/lib/src/storage/session_store.dart`
- `cli/lib/src/llm/title_generator.dart`
- `cli/test/session/session_manager_test.dart`
- `cli/test/llm/title_generator_test.dart`
- `docs/reference/session-storage.md`
- `website/sessions.md`

Current behavior:

- on first non-slash user submit, `event_router.dart` logs `user_message`
- if `_titleGenerated == false`, Glue flips it to `true` and calls
  `_generateTitle(expanded)`
- `_generateTitleImpl()` creates a title LLM client and calls
  `SessionManager.generateTitle(...)` fire-and-forget
- `TitleGenerator.generate()` only sees the first user message
- `SessionManager.generateTitle()` persists `meta.title` and logs
  `title_generated`
- resumed sessions backfill a missing title from the first historical user
  message only

Important limitation:

- `_titleGenerated` currently means both:
  - "we attempted to generate a title"
  - "the title should never be reconsidered"

That coupling is the design problem.

## External reference: OpenCode

OpenCode has a stronger title policy than Glue, but still does not appear to do
periodic retitling.

Relevant files reviewed:

- `packages/opencode/src/session/session.ts`
- `packages/opencode/src/session/prompt.ts`

Useful OpenCode ideas:

- sessions start with a recognizable default title
- auto-title generation only runs when the current title still looks like a
  default title
- user-set / non-default titles are not silently replaced
- title generation uses richer conversation context than a raw first-message
  substring
- title generation is tied to session state, not just a one-shot boolean

What Glue should borrow:

- explicit distinction between default / auto / user-owned titles
- title eligibility rules based on title origin and state
- context-based second-pass generation

What Glue does not need right now:

- full default-title parity with OpenCode before anything else ships
- an always-running title daemon
- repeated retitling on every turn

## Recommended approach

Adopt a **two-pass title lifecycle** with explicit metadata:

1. **Initial pass**
   - generate a quick title from the first real user message
   - mark it as `auto` + `provisional`

2. **Reevaluation pass**
   - after the session has more context, generate a better title from a compact
     conversation summary
   - replace the current title only if it is still auto-generated and the new
     title is materially better
   - mark the resulting title as `stable`

3. **No further automatic title changes**
   - unless a future policy explicitly reopens the title
   - user-set titles are never touched
   - an explicit `/rename` makes the title user-owned and permanently opts the session out of future auto-titling

This keeps the implementation small, predictable, and testable while fixing the
main UX problem.

## Design principles

- event-driven reevaluation, not wall-clock timers
- user-set titles are authoritative
- `/rename` is the manual override and transfers title ownership to the user
- one provisional auto-title is allowed to improve once
- titles should not churn after they become stable
- cheap models are fine for titling; use compact context rather than full
  transcript replay
- persistence should record title origin and state so resume behavior is
  correct

## Proposed session metadata changes

Extend `SessionMeta` in `session_store.dart` with title state.

### New fields

- `titleSource`: `user | auto`
- `titleState`: `provisional | stable`
- `titleGenerationCount`: integer
- `titleGeneratedAt`: ISO timestamp
- `titleLastEvaluatedAt`: ISO timestamp
- `titleRenamedAt`: ISO timestamp

Optional if you want better debugging later:

- `titleBasis`: `first_message | reevaluated_context | manual`

### Example `meta.json`

```json
{
  "id": "1760000000000-abcd",
  "cwd": "/repo/glue",
  "model": "anthropic/claude-sonnet-4-5",
  "start_time": "2026-04-20T08:00:00.000Z",
  "title": "Session title reevaluation",
  "title_source": "auto",
  "title_state": "stable",
  "title_generation_count": 2,
  "title_generated_at": "2026-04-20T08:00:03.000Z",
  "title_last_evaluated_at": "2026-04-20T08:01:10.000Z",
  "title_renamed_at": null
}
```

## Lifecycle changes

### Initial generation

Current behavior is close enough to keep.

On the first real user message:

- if no title exists
- and title generation is enabled
- and no user title is already present

then:

- generate initial title from first user message
- persist title
- set:
  - `titleSource = auto`
  - `titleState = provisional`
  - `titleGenerationCount = 1`

### Reevaluation trigger

Do **not** use a timer.

Trigger reevaluation on conversation milestones instead.

Recommended trigger:

- after the first completed assistant turn
- and only if at least one of these is true:
  - there are at least 2 user messages
  - there has been at least 1 tool call
  - the assistant response is complete and non-trivial

This gives the title system enough evidence without requiring a scheduler.

### Reevaluation eligibility

A session is eligible for second-pass titling only if all are true:

- `titleSource == auto`
- `titleState == provisional`
- `titleGenerationCount < 2`
- there is enough conversation context to justify reevaluation

Not eligible if:

- title was set by user
- title was manually changed via `/rename`
- title is already stable
- second pass already happened

### Stabilization

After a successful second pass:

- update title if replacement rules allow it
- mark `titleState = stable`
- increment `titleGenerationCount`

If second-pass generation fails:

- keep existing title
- optionally leave state provisional for resume-time retry, or mark stable to
  avoid retry loops

Recommendation:

- if the reevaluation attempt ran and produced no better title, mark stable
- do not keep retrying forever

## Replacement policy

Only replace the current title when all are true:

- current title is auto-generated
- current title is provisional
- proposed title is non-empty after sanitization
- proposed title is meaningfully different from current title
- proposed title is more specific than the current one

### Minimal heuristics

Start simple.

1. Normalize both strings:
   - lowercase
   - collapse whitespace
   - strip punctuation at edges

2. Reject replacement if normalized titles are equal.

3. Reject replacement if proposed title is shorter and less specific.

4. Prefer replacement if the current title looks generic and the proposal adds
   concrete nouns.

Examples of weak/generic titles:

- Investigate issue
- Help debug this
- Fix problem
- Check code
- Session question

Examples of stronger titles:

- Docker test flakiness in session resume
- Session title reevaluation metadata
- Provider adapter config mismatch
- Fix JSONL replay for tool results

This should stay heuristic-based for now; no confidence scoring or structured
judge step is needed in v1.

## Manual rename command

Add a top-level `/rename` command for the current session.

### Behavior

- `/rename <new title>` sets the current session title explicitly
- trimming and title sanitization rules should still apply
- empty titles are rejected with a usage/error message
- after `/rename`, persist:
  - `title = <new title>`
  - `titleSource = user`
  - `titleState = stable`
  - `titleRenamedAt = now`
- after `/rename`, the session is permanently opted out of future automatic
  title generation and reevaluation unless a future explicit command re-enables
  it

### Command shape

Use a top-level verb, not `/session rename`.

Reason:

- renaming is a frequent direct action
- Glue already uses top-level verbs for common session actions
- this matches the broader command-direction discussed elsewhere in the plans
- it is faster to type and easier to discover

### Interaction with auto-titles

`/rename` is the hard handoff from machine-owned title state to user-owned title
state.

After `/rename`:

- no initial auto-title generation should run if it has not run yet
- no reevaluation should run if the title is still provisional
- resume should not backfill or re-evaluate the session title

## Title generation API changes

### Keep current API

Keep the current first-pass path:

- `TitleGenerator.generate(String userMessage)`

### Add second-pass API

Add a compact-context method, for example:

```dart
Future<String?> generateFromContext(TitleContext context)
```

Where `TitleContext` might include:

- `firstUserMessage`
- `latestUserMessage`
- `firstAssistantMessage`
- `latestAssistantMessage`
- `toolNames`
- `cwdBasename`

Do not pass the entire transcript unless it is already trivially available.
This should stay cheap.

### Suggested prompt shape

System prompt stays concise but should clarify that the title should reflect the
actual work of the session, not just the opening sentence.

For example:

- generate a short title for this coding session
- prefer the concrete task that emerged from the conversation
- avoid generic words like issue, request, question, help
- use sentence case
- max 7 words
- respond with title only

## State model changes in App

Current app state uses a single boolean:

```dart
bool _titleGenerated = false;
```

That should be replaced or narrowed in meaning.

### Recommended in-memory state

Use separate flags for orchestration only:

- `_titleInitialRequested`
- `_titleReevaluationRequested`
- `_titleManuallyOverridden`

Persistent authority should live in session metadata, not just app memory.

Reason:

- resume logic must know whether the title is still provisional
- title ownership survives app restart
- future UI can display whether a title was manual or automatic

## Implementation plan

### Phase 1 — Metadata foundation

1. Extend `SessionMeta` in `cli/lib/src/storage/session_store.dart` with:
   - `titleSource`
   - `titleState`
   - `titleGenerationCount`
   - `titleGeneratedAt`
   - `titleLastEvaluatedAt`
2. Teach `toJson` / `fromJson` to persist them.
3. Keep backward compatibility for older sessions with only `title`.
4. Decide default interpretation for old sessions:
   - if `title` exists and no metadata exists, treat as `auto + stable` for
     safety
   - do not retroactively reevaluate old titled sessions

### Phase 2 — First-pass generation becomes provisional

1. Update `SessionManager.generateTitle()` to write title metadata, not just the
   title string.
2. Rename or replace `_titleGenerated` semantics in app/session runtime.
3. First-pass generation should persist:
   - `titleSource = auto`
   - `titleState = provisional`
   - `titleGenerationCount = 1`
4. Keep current fire-and-forget behavior.
5. Ensure first-pass generation is skipped if the title is already user-owned.

### Phase 3 — Manual rename command

1. Add a top-level `/rename` command for the current session.
2. Implement `SessionManager.renameTitle(...)` or equivalent session-store
   helper.
3. Persist manual rename metadata:
   - `titleSource = user`
   - `titleState = stable`
   - `titleRenamedAt = now`
4. Ensure `/rename` permanently disables future auto-title generation and
   reevaluation for that session.
5. Add validation and usage messaging for missing/empty titles.

### Phase 4 — Context-based reevaluation

1. Add `TitleContext` model.
2. Add `TitleGenerator.generateFromContext(...)`.
3. Add a `SessionManager.reevaluateTitle(...)` method.
4. Hook reevaluation into the turn-complete path, not user-submit path.
5. Trigger reevaluation once, using the eligibility rules above.
6. Apply replacement heuristics before persisting a new title.
7. Mark title stable after the reevaluation attempt.
8. Ensure reevaluation is skipped entirely for manually renamed sessions.

### Phase 5 — Resume behavior

1. On resume, if title is missing:
   - generate initial provisional title as today, but with metadata
2. On resume, if title exists and is `auto + provisional` and reevaluation has
   not happened:
   - allow one reevaluation when the next meaningful turn completes
3. Do not reevaluate `stable` or `user` titles on resume
4. Do not backfill or reevaluate titles for sessions previously renamed via
   `/rename`

### Phase 6 — Docs and event visibility

1. Update session storage docs to document new title metadata fields.
2. Add or update event docs if title events become richer.
3. Optionally log title lifecycle events with explicit structure:
   - `title_generated`
   - `title_reevaluated`
   - `title_stabilized`

Recommendation:

- keep `title_generated`
- add `title_reevaluated` only if it helps tooling or debugging
- avoid event-schema churn unless it adds real value

## Hook point recommendation

The reevaluation pass should happen after a completed assistant turn has been
persisted.

Why:

- the title system can use actual session evidence
- assistant/tool work often disambiguates the task
- this avoids reevaluating too early during user input dispatch

Avoid putting the reevaluation trigger in `event_router.dart` next to initial
submit-time generation. That file is the right place for the first-pass trigger,
but not the second-pass checkpoint.

## Testing plan

Add tests covering:

### Metadata and compatibility

- old `meta.json` without title metadata still loads
- new metadata round-trips correctly
- sessions with manual titles are preserved
- `titleRenamedAt` round-trips correctly when present

### Initial generation

- first-pass generation writes title and provisional metadata
- title generation disabled still skips everything cleanly
- first-pass failure does not crash the app
- first-pass generation does not run when the session is already user-owned

### Manual rename behavior

- `/rename <title>` updates the current session title
- `/rename` with no value returns a clear usage/error message
- `/rename` sets `titleSource = user`
- `/rename` sets `titleState = stable`
- `/rename` sets `titleRenamedAt`
- `/rename` prevents any later auto-title reevaluation

### Reevaluation behavior

- provisional auto title becomes stable after successful reevaluation
- reevaluation does not run for user titles
- reevaluation does not run for manually renamed sessions
- reevaluation does not run for already-stable titles
- reevaluation runs only once
- reevaluation can improve a weak initial title
- reevaluation rejects identical or weaker proposals

### Resume behavior

- resumed untitled session gets provisional first-pass title
- resumed provisional title can still be reevaluated once
- resumed stable title is not touched
- resumed manually renamed title is never backfilled or reevaluated

### Event/logging behavior

- `title_generated` still logs correctly
- optional reevaluation event logs correctly if implemented

## Acceptance criteria

- Glue can generate an initial session title quickly from the first user turn.
- That initial title is marked provisional and machine-owned.
- Glue provides a `/rename <title>` command for manually naming the current
  session.
- `/rename` transfers title ownership to the user and disables future
  auto-title generation and reevaluation for that session.
- Glue can reevaluate the title once the conversation has enough context.
- The second-pass title uses broader session evidence than the first user
  message alone.
- User-set titles are never replaced automatically.
- Automatic title changes stop after stabilization.
- Existing sessions without the new metadata continue to load safely.
- Resume behavior respects title ownership and state.

## Non-goals

- continuously regenerating titles on every turn
- timer-based background title checks
- confidence-scored title judges or structured-output ranking passes
- full OpenCode-style default-title migration before this improvement ships
- changing unrelated session naming or branch naming behavior
- adding a command to re-enable auto-titling after `/rename` in this iteration

## Open questions

1. Should old titled sessions without title metadata be treated as `auto` or
   `user` by default?
   - Recommendation: `auto + stable` for safety and minimal surprise.

2. Should a failed reevaluation leave the title provisional?
   - Recommendation: no. Mark stable after the one reevaluation attempt to avoid
     repeated hidden retries.

3. Should second-pass titling use the configured small model or the active
   model?
   - Recommendation: same policy as current title generation: prefer the cheap
     title/small model path.

4. Should title reevaluation be logged as a dedicated event?
   - Recommendation: optional. Add only if it materially improves debugging or
     replay tooling.

## Summary

The recommended implementation is a small, robust improvement:

- keep fast first-pass titling
- persist title ownership and lifecycle metadata
- add `/rename` as an explicit manual override
- reevaluate once after the conversation has real context
- stabilize after that pass
- never touch user titles
- permanently disable auto-titling for sessions manually renamed with `/rename`

This solves the current "bad early title becomes permanent" problem without
introducing a scheduler, repeated churn, or a large title-management subsystem.
