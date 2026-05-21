# Tie up the slash-command-refactor loose ends

## Context

After commit `d2cba58` ("class-based slash commands + thin services"), three loose ends remain. They sit at the seams the refactor left for follow-up:

1. **`PanelController` is two methods.** `push(panel)` and `dismiss(panel)`. The name is a holdover from when it owned domain panels. Rename it to `ModalSurface`.
2. **The `*Impl`-in-part-of-files pattern is still alive in App.** Every `App._foo()` method that lives in a `part of` file delegates to a top-level `_fooImpl(App app, ...)` helper in the same library. That indirection is structurally unnecessary now — Dart extension methods on `App` (declared in part-of files) can access `App` private members and be torn off as method values. With the conversion, App methods are real methods; no Impl indirection anywhere.
3. **Two of the four ctx callbacks (`forkSession`, `resumeFromMeta`) carry transcript-shape orchestration.** Their bodies do `_blocks.clear`, `_toolUi.clear`, `_streamingText = ''`, `_appendSessionReplayEntries(...)`, etc. — work that belongs on `ConversationView`. Once `ConversationView` grows `resetForReplay()` and `appendReplayEntries()`, the command sites can compose `ctx.session.fork/resume` + `ctx.conversation.resetForReplay()` + `ctx.conversation.appendReplayEntries(...)` directly, and the two callbacks come off the context.

Two callbacks honestly stay:
- `ensureSession` — small (one SessionManager call); kept for clarity at call sites.
- `switchModel` — embodies the Ollama pull-confirm flow which depends on App-mode state (`_mode = AppMode.confirming`, `_activeModal`). Decomposing it is a separate, larger design call. Out of scope for this PR.

## Design

### Workstream 1 — Rename `PanelController` → `ModalSurface`

Mechanical rename. Affected: 11 references across:

- `cli/lib/src/ui/panel_controller.dart` → rename file to `cli/lib/src/ui/modal_surface.dart`; rename class.
- `cli/lib/glue.dart` (re-export).
- `cli/lib/src/app.dart` (field `_panels` of type `PanelController` → `ModalSurface`; the field name stays — `_panels` reads naturally).
- `cli/lib/src/commands/slash_command_context.dart` (field `panels` of type `PanelController` → `ModalSurface`).
- 4 commands that touch the panels field type (slash/help.dart, slash/share.dart implicitly via ctx, etc. — type inference covers most; only files that name the type explicitly need updating).
- `cli/test/commands/builtin_commands_test.dart`, `cli/test/commands/recap_command_test.dart` — fixture has `late final PanelController panels;`.

Class name stays `ModalSurface` going forward. `_panels` field name stays (commands say `ctx.panels.push(...)` which still reads natural). No plan to add generic shape primitives in this PR — the existing two methods are enough until duplication shows up.

### Workstream 2 — Convert `*Impl` helpers to extension methods on App

The `part of` files in `cli/lib/src/app/` declare top-level `_fooImpl(App app, ...)` helpers and the App class declares thin wrappers calling them. Replace each `_fooImpl(App app, ...)` with a private extension method on `App`:

```dart
// session_runtime.dart  (part of app.dart)
extension _SessionRuntime on App {
  void _ensureSessionStore() {
    final config = _config;
    _sessionManager.ensureSessionStore(
      cwd: _cwd,
      modelRef: config?.activeModel.toString() ?? _modelId,
    );
  }

  String _resumeSession(SessionMeta session) { ... }
  void _generateTitle(String userMessage) { ... }
  // ...
}
```

In `app.dart` the matching wrappers (`void _ensureSessionStore() => _ensureSessionStoreImpl(this);`) all delete. App's `_initCommands` continues to tear off `_ensureSessionStore`, `_resumeSession`, `_forkSession`, `_switchToModelRow` exactly as today — extension method tear-offs work fine.

Files involved (all `cli/lib/src/app/*.dart` part-of files):

- `command_helpers.dart` — `_addSystemMessageImpl`, `_statusModelLabel`, `_forkSessionImpl`. After WS3 removes `_forkSessionImpl`, this file has only `_addSystemMessage` and `_statusModelLabel` extension methods left.
- `session_runtime.dart` — `_runPrintModeImpl`, `_resumeSessionImpl`, `_generateTitleImpl`, `_reevaluateTitleImpl`, `_createTitleLlmClientImpl`, `_resolveTitleTargetImpl`, `_ensureSessionStoreImpl`, `_appendSessionReplayEntriesImpl`. After WS3 removes `_resumeSessionImpl` and `_appendSessionReplayEntriesImpl`, the rest become extension methods.
- `agent_orchestration.dart` — multiple `*Impl`s.
- `event_router.dart`, `terminal_event_router.dart`, `render_pipeline.dart`, `shell_runtime.dart`, `subagent_updates.dart`, `ollama_pull_flow.dart`, `spinner_runtime.dart` — same pattern; convert each.

Each part-of file ends up with a single `extension _<Subsystem> on App { ... }` block holding what was the `*Impl` set. Dart 2.15+ extension method tear-offs cover the existing tear-off use sites.

Naming: drop the `Impl` suffix. The wrapper-on-App was `_foo`; the impl was `_fooImpl`. After conversion, the extension method is named `_foo` (matching what the rest of the codebase already calls). No naming collision because the wrappers are deleted.

### Workstream 3 — Decompose `forkSession` and `resumeFromMeta` via `ConversationView`

`ConversationView` absorbs the transcript-shape state and grows two methods:

- `resetForReplay()` — clears blocks, streaming text/thinking, scroll offset; invokes the new `clearToolUi` / `clearSubagentGroups` callbacks the view takes at construction. Used before replay (resume + fork).
- `appendReplayEntries(List<SessionReplayEntry>)` — body of today's `_appendSessionReplayEntriesImpl` moves here. Subagent group reconstruction logic lives on the view.

`ConversationView` constructor gains:
- `void Function() clearToolUi` — backed by `() => _toolUi.clear()` in App.
- `void Function() clearSubagentGroups` — backed by `() { _subagentGroups.clear(); _outputLineGroups.clear(); }` in App.
- `void Function() resetScrollOffset` already present.
- `void Function() resetStreamingText` already present (clears both streaming text and thinking).

These remain callbacks because the underlying maps/lists are App-private types (`Map<ToolCallId, _ToolCallUiState>`, etc.). Promoting those to public types is bigger scope; the callback shape is adequate.

Editor exposure: `ctx` gains `final TextAreaEditor editor;` so `HistoryCommand` can call `ctx.editor.setText(result.draftText)` after fork. App passes its existing `editor` field at ctx construction. (The `TextAreaEditor` class is already public.)

Title backfill on resume: today `_resumeSessionImpl` calls `app._generateTitle(firstUserMessage)`. After WS2, `_generateTitle` is a real App method (extension). To remove the `resumeFromMeta` callback entirely, add one tiny ctx callback `void backfillTitle(String firstUserMessage)` backed by `_generateTitle`, OR inline the title-backfill condition into `ResumeCommand`. The latter pulls the title-gen LLM construction into the command; messy.

**Decision**: keep one tiny callback `backfillTitle: _generateTitle` on ctx. Net change: drop `forkSession` and `resumeFromMeta`, gain `backfillTitle`. One callback fewer overall, and `backfillTitle` is a single-purpose seam.

#### Migration of the two commands

`HistoryCommand._fork` (currently `ctx.forkSession(idx, text)`):

```dart
final result = ctx.session.forkSession(
  userMessageIndex: idx,
  messageText: text,
  agent: ctx.agent,
);
if (result == null) return;
ctx.conversation
  ..clear() // already exists; clears blocks + screen
  ..notify(result.message)
  ..appendReplayEntries(result.replay.entries);
ctx.editor.setText(result.draftText);
```

Wait — `clear()` resets streaming and scroll too; `resetForReplay()` is the same minus `clearScreen`. Both are appropriate here. Reuse `clear()` if it covers everything, otherwise use `resetForReplay`. (Today's `_forkSessionImpl` does NOT clear streaming/scroll — fork keeps the screen but starts a fresh transcript. Use `resetForReplay()` which won't `terminal.clearScreen` either.)

Actually, looking at `clear()`: it calls `terminal.clearScreen()` plus `layout.apply()`. That's appropriate for `/clear` but maybe heavy for fork. Today's fork doesn't clear the screen. So `resetForReplay()` is the right shape — like `clear()` but no terminal clear / layout apply.

`ResumeCommand._resolveByQuery` and the on-selection branch (currently `ctx.resumeFromMeta(meta)`):

```dart
final result = ctx.session.resumeSession(session: meta, agent: ctx.agent);
ctx.conversation.resetForReplay();
ctx.session
  ..titleInitialRequested = meta.title != null
  ..titleReevaluationRequested = meta.titleState == SessionTitleState.stable ||
      meta.titleGenerationCount >= 2
  ..titleManuallyOverridden = meta.titleSource == SessionTitleSource.user;
ctx.conversation.notify(
  'Resuming session ${meta.id} (${meta.modelRef}, ${meta.startTime.timeAgo})',
);
if (!result.hasConversation) {
  return 'Session ${meta.id} has no conversation data.';
}
final usage = result.replay.totalUsage;
if (usage.totalCalls > 0) { /* posts the carry-over summary */ }
ctx.conversation.appendReplayEntries(result.replay.entries);
final firstUserMessage = result.replay.firstUserMessage;
if (!ctx.session.titleInitialRequested &&
    !ctx.session.titleManuallyOverridden &&
    firstUserMessage != null && firstUserMessage.isNotEmpty) {
  ctx.session.titleInitialRequested = true;
  ctx.backfillTitle(firstUserMessage);
}
return result.message;
```

The "switch model based on resumed session's modelRef" is not done today (the model stays whatever the user is on); no change needed.

`_formatTokens` helper in `session_runtime.dart` either moves into `ResumeCommand` or to `extensions/units.dart` (already in glue_harness). Pick the harness home.

#### Wiring changes

`SlashCommandContext`:
- Remove: `forkSession`, `resumeFromMeta`.
- Add: `editor: TextAreaEditor`, `backfillTitle: void Function(String firstUserMessage)`.

App's `_initCommands`:
- Remove `forkSession: _forkSession, resumeFromMeta: _resumeSession`.
- Add `editor: editor, backfillTitle: _generateTitle`.

`ConversationView` constructor:
- Add `clearToolUi: () { _toolUi.clear(); }`, `clearSubagentGroups: () { _subagentGroups.clear(); _outputLineGroups.clear(); }`.

App's `_resumeSession` (still used by startup paths in `app.dart`) becomes much smaller — it can call into the same SessionManager + ConversationView pieces that ResumeCommand uses. Or it can stay as a method that internally drives the same flow. Picking the smallest refactor: the App startup path that bare-`--resume`s opens the picker via `_commands.execute('/resume')` (already the case). The path that resumes a specific session ID directly uses `_resumeSession` — keep it as an internal method that calls the same composed flow.

#### `_addSystemMessage` and `_render` callsites in App-internal code

After WS2, `_addSystemMessage` is a real extension method on App. App-internal code keeps using it — no change to existing callers like `_handleTerminalEvent`, `_handleAppEvent`, etc.

### Workstream 4 — Delete `command_helpers.dart` (consequence of WS2 + WS3)

After WS2 converts the three remaining helpers in `command_helpers.dart` to extension methods, and WS3 deletes `_forkSession` (its body becomes inline in `HistoryCommand`):

- `_addSystemMessage` — keep as an extension method on App. Move into `app/extensions.dart` (new tiny part-of file) or merge into one of the existing part-of files. Probably best to merge with `models.dart` (already a small part-of file holding App's tool/spinner state types).
- `_statusModelLabel` — only callsite is `render_pipeline.dart`. Move next to `formatStatusModelLabel` etc. as a non-part-of helper, OR inline at the call site. Simplest: inline at the call site (single use).
- `_forkSession` — deleted by WS3.

Result: `command_helpers.dart` is empty and deleted. `part 'app/command_helpers.dart';` removed from `app.dart`.

## Files affected

**Renamed/moved:**
- `cli/lib/src/ui/panel_controller.dart` → `cli/lib/src/ui/modal_surface.dart` (class `PanelController` → `ModalSurface`).
- `cli/lib/src/app/command_helpers.dart` → deleted.

**Modified:**
- `cli/lib/glue.dart` — re-export `ModalSurface`.
- `cli/lib/src/app.dart` — drop `part 'app/command_helpers.dart';`, drop the `*Impl` wrappers (whose bodies move to extensions), drop `forkSession` / `resumeFromMeta` ctx args, add `editor` / `backfillTitle` ctx args, add `clearToolUi` / `clearSubagentGroups` ConversationView args. `_panels` field re-typed to `ModalSurface`.
- `cli/lib/src/commands/slash_command_context.dart` — `panels: PanelController` → `panels: ModalSurface`. Drop `forkSession` and `resumeFromMeta`. Add `editor` and `backfillTitle`.
- `cli/lib/src/services/conversation_view.dart` — add `clearToolUi` + `clearSubagentGroups` constructor args; add `resetForReplay()`, `appendReplayEntries(List<SessionReplayEntry>)` methods.
- `cli/lib/src/commands/slash/history.dart` — `_activate` body inlines fork-and-replay using `ctx.session.forkSession + ctx.conversation.resetForReplay + ctx.conversation.appendReplayEntries + ctx.editor.setText`.
- `cli/lib/src/commands/slash/resume.dart` — `_openPicker` and `_resolveByQuery` inline the resume orchestration using ConversationView + SessionManager + `ctx.backfillTitle`.
- `cli/lib/src/app/command_helpers.dart` — deleted (its three methods migrate to extensions in models.dart or app.dart proper).
- `cli/lib/src/app/session_runtime.dart` — convert all `*Impl` helpers to extension methods on App. Drop `_resumeSessionImpl` and `_appendSessionReplayEntriesImpl` (logic moves to ResumeCommand and ConversationView respectively). `_formatTokens` moves to `glue_harness/lib/src/extensions/units.dart`.
- `cli/lib/src/app/agent_orchestration.dart`, `event_router.dart`, `terminal_event_router.dart`, `render_pipeline.dart`, `shell_runtime.dart`, `subagent_updates.dart`, `ollama_pull_flow.dart`, `spinner_runtime.dart` — convert all `*Impl` helpers to extension methods on App.
- `cli/test/commands/builtin_commands_test.dart`, `cli/test/commands/recap_command_test.dart` — fixture's `panels` field re-typed; ctx construction drops `forkSession`/`resumeFromMeta`, adds `editor`/`backfillTitle` (with no-op stubs).

## Reusable pieces (do not re-implement)

- `SessionManager.forkSession(...)`, `SessionManager.resumeSession(...)` — already exist; commands call directly.
- `SessionManager.titleInitialRequested` / `titleReevaluationRequested` / `titleManuallyOverridden` — public fields; resume command sets directly.
- `TimeAgoX extension on DateTime` — used in resume's "Resuming session …" message.
- Existing `ConversationView.clear()` and `notify()` — used as building blocks for `resetForReplay()`.

## Verification

1. `dart format --set-exit-if-changed .`
2. `dart analyze --fatal-infos` — clean across cli + glue_harness + glue_strategies + glue_core.
3. `dart test` — all 1556 tests pass; new tests pass.
4. Manual smoke (`cli/`, `dart run bin/glue.dart`):
   - `/resume` → opens picker; selecting a session resumes it; "Resuming session …" message appears; replayed transcript shows; if the session had no title, title backfill kicks in.
   - `/resume <id>` → same path via direct query.
   - `/history` (with prior user messages) → forks at the selected entry; transcript is replayed up to fork; editor seeded with the selected message text.
   - `/history 2` → direct fork.
   - All other commands behave identically (no changes to their flows).
   - Sanity: `/help`, `/model`, `/provider list` still open their panels via `ctx.panels.push`.
5. `just check` clean (format + analyze + tests + gen-check + layer check).
6. Inspect `git diff cli/lib/src/app/`: every file should be cleaner. `command_helpers.dart` is deleted; the rest have one extension block each, no top-level `_*Impl` helpers.

## Implementation order

The three workstreams are independent enough to land in this order; each step keeps CI green:

1. **WS1: Rename PanelController → ModalSurface.** Pure mechanical sed + file rename. CI green.
2. **WS2: Convert all `*Impl` helpers to extensions.** One part-of file at a time. CI green after each conversion. Skip `_resumeSessionImpl` and `_appendSessionReplayEntriesImpl` for now (handled in WS3) and `_forkSessionImpl` (also WS3).
3. **WS3: ConversationView decomposition.**
   - Add `resetForReplay()` and `appendReplayEntries()` to ConversationView (move `_appendSessionReplayEntriesImpl` body in).
   - Add `editor` and `backfillTitle` to ctx; remove `forkSession` and `resumeFromMeta`.
   - Migrate `HistoryCommand._fork` to compose pieces directly.
   - Migrate `ResumeCommand` to compose pieces directly.
   - Delete `_forkSessionImpl` and `_resumeSessionImpl`.
4. **WS4: Delete `command_helpers.dart`.** Migrate `_addSystemMessage` to a sibling part-of (probably `models.dart`); inline `_statusModelLabel` at its single call site; remove the `part 'app/command_helpers.dart';` line.
5. `just check`.
