# App Decomposition — Inventory, Roadmap, End Shape, Naming Cleanup

## Context

Phase 1 (panels/docks services) is complete. `PanelController` deleted, controllers absorbed feature flows, 1505 tests green. But the cleanup so far only excavated one corner of `App`. The `App` class itself remains a ball of mud — 597-line orchestrator plus 12 `part` files totalling ~1800 more lines of behavior woven through its private fields. `command_host_adapter.dart` is a **compatibility shim**, not the destination — it wires controllers to `App`'s internals via closures so the controllers can exist without `App` being properly decomposed yet.

This plan answers four questions from the user:

1. What's still a ball of mud and needs scrutiny?
2. What's the roadmap for cleaning `app.dart`?
3. What does the end shape look like?
4. Where else can we flatten "architecture suffix" names?

This is a design/roadmap document. It feeds the existing living plan at repo-root `REFACTOR.md`. No implementation changes yet — the user wants alignment on direction first.

### Guiding principle (reinforced from prior user feedback)

**Don't create a class for behavior that's just a side-effect of another owner's state.** If feature X's "controller" only exists because X has a slash command, but X is really just session/config/transcript state with a side-effect, fold it in. We already over-abstracted `SessionTitleStateController` (three booleans + reeval logic that's really session-state behavior). Apply the same lens to every new runtime object and service this plan proposes.

Concrete consequences for this plan:

- **Title generation + title state → `session` service.** The three booleans and the generator are session state + session behavior; `/rename` just calls `session.rename(title)`. Delete `SessionTitleStateController` as its own class.
- **`ToolApprovals` as a separate object → folded into `TurnRunner`.** Approvals happen *during a turn*; the state (auto-approved tools, early-approved IDs) and the approve/deny/confirm-modal flow belong to the turn.
- **`SubagentCoordinator` → folded into `Transcript`.** It's transcript grouping behavior triggered by subagent events, not its own identity.

The runtime-object set shrinks from 7 to 4: `Transcript`, `Renderer`, `InputRouter`, `TurnRunner`. Plus `BashMode` (has its own independent process/span lifecycle — keeps its identity).

---

## 1. Ball-of-Mud Inventory

### The App class and its part files

| File | Lines | What it owns |
|---|---|---|
| `app.dart` | 597 | ~45 fields + 30 thin delegate methods. The actual data hub. |
| `app/agent_orchestration.dart` | 336 | Turn lifecycle, tool approval flow, cancel, span tracing |
| `app/session_runtime.dart` | 318 | Print mode runner, session resume, title generation, replay append |
| `app/terminal_event_router.dart` | 243 | Keyboard/mouse dispatch (editor/overlays/modals/bash/panels) |
| `app/render_pipeline.dart` | 221 | Render loop, 60fps coalescing, token formatter |
| `app/command_host_adapter.dart` | 153 | **Compat shim** wiring controllers to App's private fields |
| `app/models.dart` | 147 | `_ConversationEntry`, `_ToolCallUiState`, `_SubagentGroup`, `_TitleTarget` |
| `app/shell_runtime.dart` | 124 | Bash mode: submit, cancel, blocking/background jobs |
| `app/command_helpers.dart` | 62 | `addSystemMessage`, `forkSession`, time ago |
| `app/subagent_updates.dart` | 54 | Subagent event grouping into transcript |
| `app/model_display.dart` | 47 | Pure model-label formatter (this one's fine) |
| `app/event_router.dart` | 44 | App event dispatch |
| `app/events.dart` | 23 | AppEvent types |
| `app/spinner_runtime.dart` | 15 | Spinner timer ticker |

Total: ~2400 lines of App runtime. ~600 scaffolding, ~1800 real behavior.

### What App's `_` fields actually represent (semantic grouping)

**Transcript state** (UI-facing conversation log):
`_blocks`, `_toolUi`, `_scrollOffset`, `_streamingText`, `_subagentGroups`, `_outputLineGroups`.
→ This is the conversation UI state. Today it's a bag; it should be a `Transcript` object that features mutate through the `transcript` service.

**Render state** (scheduling + spinner):
`_lastRender`, `_renderScheduled`, `_minRenderInterval`, `_spinnerFrame`, `_spinnerTimer`, `_renderedPanelLastFrame`.
→ Belongs on a `Renderer` owner, not on App.

**Turn/agent state** (one turn of model interaction):
`_turnSpan`, `_agentSub`, `_mode`, `_activeModal`, `_bashMode`, `_earlyApprovedIds`.
→ TurnRunner territory.

**Bash mode state**:
`_bashMode`, `_bashRunProcess`, `_bashSpan`, `_lastCtrlC`.
→ `BashMode` controller.

**Permission state**:
`_approvalMode`, `_autoApprovedTools`, `_earlyApprovedIds`.
→ `ToolApprovals` (thin coordinator over existing `PermissionGate`).

**Startup options** (invariant after construction):
`_startupContinue`, `_startupPrompt`, `_printMode`, `_jsonMode`, `_resumeSessionId`.
→ Already have `AppLaunchOptions` in `runtime/`. These fields should collapse into it.

**Wiring / composition** (dependencies App didn't create):
`terminal`, `layout`, `editor`, `agent`, `_manager`, `_llmFactory`, `_config`, `_systemPrompt`, `_environment`, `_cwd`, `_executor`, `_jobManager`, `_sessionManager`, `_shareExporter`, `_gistPublisher`, `_skillRuntime`, `_obs`, `_debugController`.
→ `AppShell`'s composition responsibility. These stay wired, just from `AppShell` not `App`.

**UI services + overlays**:
`_panelStack`, `_panels`, `_dockManager`, `_docks`, `_autocomplete`, `_atHint`, `_shellComplete`, `_commands`, `_commandContext`.
→ `AppShell` constructs these and hands them to what needs them.

**Done** (already extracted):
`_titleState` (→ `SessionTitleStateController`), the feature panels (→ controllers).

### What's actually leaking across boundaries today

Hot spots where behavior reaches deep into App:

- **`agent_orchestration.dart` reads 12 App fields per turn**: `_streamingText`, `_blocks`, `_toolUi`, `_approvalMode`, `_autoApprovedTools`, `_earlyApprovedIds`, `_turnSpan`, `_obs`, `_agentSub`, `_activeModal`, `_mode`, `_cwd`. This is the densest coupling in the codebase and the highest-leverage extraction.
- **`terminal_event_router.dart` is the central traffic cop** — routes terminal events to 7 different destinations (editor, panels, modals, autocomplete, bash mode, agent-cancel, shell job cancel). Can't cleanly extract until the destinations are separately owned.
- **`render_pipeline.dart` reads all the view state directly** — blocks, tool UI, panels, docks, scroll, spinner, streaming text. Needs a coherent `ViewState` to consume instead of reaching into App.
- **`session_runtime.dart` owns print mode AND title generation AND resume** — three unrelated concerns crammed together. Split them.

---

## 2. End Shape — Target Architecture

`App` does not exist. Replaced by `AppShell` (already exists, underused) plus 6–7 focused runtime objects and the 7 services we've already named.

```
AppShell  (composition root + lifecycle; lives in runtime/app_shell.dart)
├── Wires (from ServiceLocator):
│   Terminal, Layout, Editor, AgentCore, SubagentPool,
│   LlmClientFactory, GlueConfig, Environment, Executor, ShellJobs,
│   SessionManager (disk), Observability, SkillRuntime, …
│
├── Constructs runtime objects (just four):
│   Transcript       — _blocks/_toolUi/_scrollOffset/_streamingText
│                      + subagent event grouping (folded in)
│   Renderer         — render loop, spinner, 60fps coalescing
│   InputRouter      — terminal-event traffic cop
│   TurnRunner       — interactive + print mode converge here
│                      + tool approval flow (folded in)
│   BashMode         — independent process lifecycle; keeps identity
│
├── Constructs services (what controllers see):
│   panels, docks, confirmations, transcript, tools, config, session
│   (session service owns title-generation state internally)
│
└── Constructs controllers (one per slash-command family):
    ModelController, ProviderController, SessionController,
    SkillController, ShareController, SystemController, ChatController

Entry: AppShell.run(AppLaunchOptions options) → interactive loop or print mode
```

### End-state responsibilities

- **`AppShell`**: sets up terminal (raw mode, alt screen, mouse), subscribes event streams, chooses interactive vs print mode, runs exit completer, tears down. Nothing else. No state except subscription handles.
- **`Transcript`**: the mutable conversation UI state. Features call `transcript.postNotice(text)` or (through the agent layer) `tools.invoke(...)` and see the transcript update. Owns block list, tool-call UI states, scroll offset, streaming buffer. **Also absorbs subagent event grouping** (`_subagentGroups`/`_outputLineGroups`) — it's transcript behavior, not a separate coordinator.
- **`Renderer`**: owns render scheduling (`_lastRender`, `_renderScheduled`), the spinner ticker, the 60fps coalescing. Consumes `Transcript`, panel stack, dock layout. Doesn't know about agents or commands.
- **`InputRouter`**: given a `TerminalEvent`, decides who handles it. Routes by mode (panel open? confirm modal? bash? autocomplete? agent streaming? idle). No business logic, just dispatch.
- **`TurnRunner`**: starts an agent turn, drains the agent event stream into `Transcript` updates + tool approvals + observability spans. One code path for interactive and print mode. Replaces the 336-line `agent_orchestration.dart`. **Absorbs tool-approval flow** (`_autoApprovedTools`, `_earlyApprovedIds`, approve/deny/confirm-modal) — approvals only happen during turns, so they belong here.
- **`BashMode`**: contains the four bash fields + `submit`/`cancel`/`runBlocking`/`startBackground`. Keeps its own identity because the process lifecycle (`Process`, `ObservabilitySpan`) is independent of agent turns.
- **`session` service** absorbs title state + generation: the `session` service owns the three title booleans (initial/reeval/manual-override) internally, generates titles as a side-effect of conversation activity, and exposes `session.rename(title)` for `/rename`. No dedicated `SessionTitleStateController` class.

The 7 services and the controllers sit on top of these runtime objects and never reach into their private fields. `command_host_adapter.dart` disappears because controllers take services/runtime-objects directly from `AppShell`.

---

## 3. Roadmap — How We Get There

Four phase groups. Each group has internal phases that can land independently with tests green.

### Group A — Mechanical cleanup (low risk, safe wins)

**A1. Share module consolidation.**
Pull `DefaultShareCommandController` out of `command_controllers.dart` into `share/share_controller.dart`. Co-locate `_ShareCommandModule` in `share/share_module.dart`. Rename `SessionShareExporter` → `ShareExporter`, `SessionGistPublisher` → `GistPublisher` (context already in folder). App stops importing `share/*` directly — only the share module does.

**A2. `ui/` restructure.**
Split `ui/` into `ui/services/`, `ui/components/`, `ui/rendering/`. Consolidate per user's direction: `panel.dart` (AbstractPanel + Panel + SelectPanel + SplitPanel + PanelSize family), `dock.dart`, `tables.dart`, `overlays.dart`, `modal.dart`, `box.dart`, `theme.dart`. Move `rendering/*` into `ui/rendering/`.

**A3. Feature surfaces out of `ui/`.**
Move `skills_docked_panel.dart` → `skills/`, `device_code_panel.dart` + `api_key_prompt_panel.dart` → `providers/`, `model_panel_formatter.dart` → `catalog/`, `slash_autocomplete.dart` → `commands/`, `shell_autocomplete.dart` → `shell/`, `at_file_hint.dart` → `input/`. Add `just ui-check` that fails if `ui/**` imports a feature module.

**A4. Split `command_controllers.dart` (1640 lines).**
One file per controller under `runtime/controllers/`. Drop the `Default*` prefix as part of the split: `model_controller.dart` holds `ModelController`, etc.

### Group B — State extraction (medium risk, highest leverage)

**B1. Extract `Transcript`.**
Create `runtime/transcript.dart` owning `_blocks`, `_toolUi`, `_scrollOffset`, `_streamingText`. All existing callers (render_pipeline, agent_orchestration, command_helpers, session_runtime, subagent_updates) go through it. `transcript` service (`transcript.postNotice`) becomes a thin method on this object. `addSystemMessage` disappears.

**B2. Extract `Renderer`.**
`runtime/renderer.dart` owns render loop + spinner + 60fps coalescing. Reads Transcript + panels + docks. `_render` on App becomes a method call into Renderer. App's render-related fields all move.

**B3. `config` + `session` services.**
Consolidate the 5–8 closures each controller takes for config/session state into two service objects. `session` is a facade over existing `SessionManager` (keep SessionManager as the disk-facing implementation). `config` wraps `GlueConfig` read/write.

### Group C — Runtime decomposition (higher risk, bigger wins)

**C1. Extract `TurnRunner`** (absorbs tool approvals).
`runtime/turn_runner.dart`. Replaces `agent_orchestration.dart` + the print-mode runner in `session_runtime.dart`. One path for interactive and non-interactive turns. Owns the turn's tool-approval state (`_autoApprovedTools`, `_earlyApprovedIds`) and the approve/deny/confirm-modal flow — no separate `ToolApprovals` class.

**C2. Extract `InputRouter`.**
`runtime/input_router.dart`. Replaces `terminal_event_router.dart`. Takes references to Transcript, Renderer, panels, docks, editor, BashMode, TurnRunner — dispatches terminal events.

**C3. Extract `BashMode`.**
`shell/bash_mode.dart` (not `runtime/` — it's shell-feature territory). Owns the four bash fields and their handlers. Keeps identity because process lifecycle is independent of agent turns.

**C4. Collapse `session_runtime.dart` + `SessionTitleStateController` into the session service.**
- Print mode runner → absorbed into `TurnRunner`.
- Title state (three booleans) + title generation + `/rename` → internal to the `session` service, which keeps `SessionManager` as its disk-facing implementation. `SessionTitleStateController` class is deleted.
- Resume/replay → methods on the session service, backed by `SessionManager`.

**C5. Fold subagent grouping into `Transcript`.**
Move `_subagentGroups`/`_outputLineGroups` logic from `subagent_updates.dart` into `Transcript` as a method (e.g. `transcript.handleSubagentUpdate(update)`). No standalone coordinator class.

### Group D — Removal

**D1. Delete `App` + `app/*` part files.**
`AppShell` becomes the only composition root. `bin/glue.dart` targets it directly.

**D2. Drop `Default*` prefix on controllers** (if not already done in A4).

**D3. Narrow `lib/glue.dart` public surface.**
Remove exports that were only there for part-file coupling. Re-audit every export.

---

## 4. Naming Simplification — Cross-Cutting

Architecture suffixes to rethink across the codebase:

| Current | Proposed | Notes |
|---|---|---|
| `Default<X>CommandController` | `<X>Controller` | Planned; mechanical rename. No second impl. |
| `SessionManager` | keep as impl, expose via `session` service | "Manager" stays on the implementation; service is lowercase. |
| `SkillRuntime` | keep as impl, expose via `skills` service | Same pattern. |
| `AgentManager` | `SubagentPool` | "Manager" is vague; it's specifically the subagent pool. |
| `ShellJobManager` | keep for now | `ShellJobs` is cleaner but higher-blast-radius; defer. |
| `SessionShareExporter` | `ShareExporter` | Context implied by folder `share/`. |
| `SessionGistPublisher` | `GistPublisher` | Same. |
| `SessionTitleStateController` | **delete** | Fold state + generation into `session` service. No class at all. |
| `ConfirmationHost` | `Confirmations` service | Fits naming pattern; already in service roster. |
| `CommandExecutor`/`HostExecutor`/`DockerExecutor`/`ExecutorFactory` | keep | Shorter versions collide with too-generic names. |
| `AgentCore` / `AgentRunner` | keep | Domain terms, not architecture noise. |
| `PermissionGate` | keep | Concept name. |
| `*Runtime` part files (`shell_runtime.dart`, `session_runtime.dart`, `spinner_runtime.dart`) | delete | All go away during Group B/C. |

Folder-level:

| Current | Proposed | Why |
|---|---|---|
| `lib/src/app/` (part files) | **delete** | Evaporates through Groups B+C. |
| `lib/src/core/` | keep, but move `service_locator.dart` → `runtime/` | It's a composition helper. |
| `lib/src/runtime/controllers/command_controllers.dart` (1640 lines) | one file per controller | Done in A4. |
| `lib/src/runtime/commands/command_host.dart` | split per controller interface, or keep flat | 7 interfaces in one file is fine for now; re-evaluate after A4. |

Naming patterns to enforce consistently:

- **Service classes**: lowercase plural (`panels`, `docks`, `transcript`). Concrete class matches the interface name; drop `Impl` suffix everywhere. Only introduce an abstract interface when a second implementation exists or a fake is needed in tests that can't construct the real one.
- **Controllers**: `<Feature>Controller` (no `Default` prefix, no `Command` infix once interfaces simplify).
- **Runtime objects**: singular nouns (`Transcript`, `Renderer`, `InputRouter`, `TurnRunner`, `BashMode`). No `*Manager`/`*Handler`/`*Service` suffix — they're concrete actors with names.
- **Disk/storage layer**: `*Store` is an acceptable suffix (`SessionStore`, `ConfigStore`, `CredentialStore`) — it's specifically "persistence under the hood". The service facade in front of it doesn't carry the suffix.
- **Files match classes**: one class's name drives the filename; consolidated modules (like the proposed `panel.dart`) use a concept-noun filename for the whole group.

---

## Critical files

Read before touching anything in each group:

**Group A**:
- `cli/lib/src/runtime/controllers/command_controllers.dart` — god-file to split
- `cli/lib/src/share/*` + `share/html/` + `share/renderer/` — share consolidation target
- `cli/lib/src/ui/*` — restructure target

**Group B**:
- `cli/lib/src/app.dart` — field inventory
- `cli/lib/src/app/render_pipeline.dart` — Renderer extraction target
- `cli/lib/src/app/models.dart` — Transcript types already partially here
- `cli/lib/src/app/subagent_updates.dart`, `command_helpers.dart` — transcript callers

**Group C**:
- `cli/lib/src/app/agent_orchestration.dart` — TurnRunner target
- `cli/lib/src/app/terminal_event_router.dart` — InputRouter target
- `cli/lib/src/app/shell_runtime.dart` — BashMode target
- `cli/lib/src/app/session_runtime.dart` — split into three

---

## Verification per group

Each group ends with:

1. `cd cli && dart format --set-exit-if-changed .`
2. `cd cli && dart analyze --fatal-infos` (the 4 pre-existing warnings unchanged; zero new issues)
3. `cd cli && dart test` (all 1505+ tests pass)
4. Interactive smoke test via `dart run bin/glue.dart`:
   - `/model`, `/provider add copilot`, `/skills`, `/resume`, `/share html` — all functional.
   - Streaming output smooth during agent turns.
   - Bash mode (`!` prefix) works.
   - Ctrl+C cancels generation but doesn't exit mid-turn.
5. Group-specific checks:
   - **After A3**: `grep -rE "package:glue/src/(catalog|providers|skills|session|commands|shell|agent|llm|storage|config)/" cli/lib/src/ui/` returns nothing.
   - **After B1**: `grep -rn "app\._blocks\|app\._toolUi\|app\._streamingText\|app\._scrollOffset" cli/lib/src/` returns nothing outside `runtime/transcript.dart`.
   - **After Group C**: `cli/lib/src/app/` folder is empty or deleted.
   - **After Group D**: `cli/lib/src/app.dart` does not exist.

---

## What this plan is not

- **Not an implementation commit.** This is the roadmap that feeds `REFACTOR.md`. User asked for inventory + direction, not code changes.
- **Not a big-bang PR.** Every phase (A1, A2, A3, A4, B1, …) lands separately, green at each step.
- **Not a naming bikeshed.** Names in §4 are proposals — the user can redirect any of them. The *pattern* (lowercase-plural services, singular-noun runtime objects, no `Impl`/`Default*`) matters more than individual names.

## Next step

User reviews this plan. Once approved, the content folds into `REFACTOR.md` (replacing the current "What's Next" section with this four-group roadmap), and implementation begins with **A1 (share consolidation)** — small, self-contained, low-risk.

---

# C1 Execution Plan — TurnRunner (starting point for a fresh session)

## Status as of this plan

All of Group A and Group B are **landed** (1505 tests green, ui-check guard passing, analyzer clean except 4 pre-existing warnings in `shell_runtime.dart` / `shell_job_manager.dart`):

- ✅ A1 share module, A2 ui/ restructure, A3 feature surfaces out, A4 controllers split
- ✅ B1 `Transcript` (`runtime/transcript.dart`), B2 `Renderer` (`runtime/renderer.dart`), B3 `Config`/`Session` services (`runtime/services/config.dart`, `runtime/services/session.dart`)
- Controllers are one-file-per-feature under `runtime/controllers/`, named `<Feature>Controller` (no `Default*`)
- `command_host_adapter.dart` is still a compat shim but now constructs `Config` + `Session` once and reuses them

## C1 — what to build

Extract the turn lifecycle out of `App` / `app/agent_orchestration.dart` / the print-mode half of `app/session_runtime.dart` into `runtime/turn_runner.dart`. Folds the tool-approval flow in (the plan rejected a separate `ToolApprovals` class because approvals only happen during a turn).

**Goal**: after C1, `agent_orchestration.dart` is deleted and the print-mode body is gone from `session_runtime.dart`. All turn-related state and logic live in one `TurnRunner` class. `App` keeps a `final TurnRunner _turns` and calls into it.

## Scope — exactly what moves

### State that moves into TurnRunner
- `_turnSpan` (ObservabilitySpan?)
- `_agentSub` (StreamSubscription<AgentEvent>?)
- `_earlyApprovedIds` (Set<String>)

### State that stays on App (but TurnRunner writes to via callbacks)
- `_mode` (AppMode) — read by `render_pipeline.dart` status bar and by `ShareController.canShare`, written by bash mode too. TurnRunner receives `void Function(AppMode) setMode`.
- `_activeModal` (ConfirmModal?) — also written by `_AppConfirmationHost` (generic ollama-pull confirm). TurnRunner receives `void Function(ConfirmModal?) setActiveModal` + `ConfirmModal? Function() getActiveModal`.
- `_autoApprovedTools` (Set<String>) — trust preferences persisted across turns via `ConfigStore`. Cross-turn; read/write via callbacks.

### Methods that move into TurnRunner (from `app/agent_orchestration.dart`)
All 12 `_*Impl` free functions → `TurnRunner` instance methods:
- `_startAgentImpl` → `startInteractive(String display, {String? expanded})`
- `_endTurnSpanImpl` → private `_endTurnSpan({extra})`
- `_handleAgentEventImpl` → private `_handleAgentEvent(AgentEvent)`
- `_executeAndCompleteToolImpl` → private `_executeAndCompleteTool(ToolCall)`
- `_cancelAgentImpl` → `cancel()`
- `_persistTrustedToolImpl` → private `_persistTrustedTool(String)`
- `_approveToolImpl` → private `_approveTool(ToolCall)`
- `_denyToolImpl` → private `_denyTool(ToolCall)`
- `_showToolConfirmModalImpl` → private `_showToolConfirmModal(ToolCall)`
- `_traceToolApprovalImpl` → private `_traceToolApproval(ToolCall, String)`

Plus the print-mode body from `session_runtime.dart:3-155` → `runPrint({required String prompt, bool jsonMode, String? stdinContent, String? resumeSessionId})`.

### Things that stay on App (reevaluated in later C phases)
- `_resumeSessionImpl`, `_generateTitleImpl`, `_reevaluateTitleImpl`, `_createTitleLlmClientImpl`, `_resolveTitleTargetImpl`, `_ensureSessionStoreImpl`, `_appendSessionReplayEntriesImpl` — session/title machinery, collapses into `session` service in **C4**.
- Bash machinery (`_handleBashSubmit`, etc.) — moves in **C3**.
- Subagent grouping (`_handleSubagentUpdateImpl`) — folds into `Transcript` in **C5**.

## TurnRunner shape

```dart
// runtime/turn_runner.dart
class TurnRunner {
  TurnRunner({
    required this.agent,
    required this.transcript,
    required this.renderer,
    required this.session,
    required this.config,
    required this.environment,
    required this.trustedTools,        // Set<String> — mutable, owned by App
    required this.obs,                  // Observability?
    required this.permissionGateFactory, // PermissionGate Function()
    required this.modelIdProvider,      // String Function() — for span attrs
    required this.setMode,              // void Function(AppMode)
    required this.setActiveModal,       // void Function(ConfirmModal?)
    required this.getActiveModal,       // ConfirmModal? Function()
    required this.onTurnComplete,       // void Function() — triggers title reeval
  });

  // Dependencies
  final AgentCore agent;
  final Transcript transcript;
  final Renderer renderer;
  final Session session;
  final Config config;
  final Environment environment;
  final Set<String> trustedTools;
  final Observability? obs;
  final PermissionGate Function() permissionGateFactory;
  final String Function() modelIdProvider;
  final void Function(AppMode) setMode;
  final void Function(ConfirmModal?) setActiveModal;
  final ConfirmModal? Function() getActiveModal;
  final void Function() onTurnComplete;

  // Turn state
  ObservabilitySpan? _turnSpan;
  StreamSubscription<AgentEvent>? _agentSub;
  final Set<String> _earlyApprovedIds = {};

  // Public API
  void startInteractive(String displayMessage, {String? expandedMessage});
  Future<void> runPrint({
    required String expandedPrompt,
    required bool jsonMode,
    String? resumeSessionId,  // print-mode resume semantics (lines 5-18 of session_runtime)
  });
  void cancel();
}
```

## Step-by-step execution

Each step verified with `dart analyze --fatal-infos` + `dart test` before moving on.

1. **Create `runtime/turn_runner.dart`** with the `TurnRunner` class. Translate the free functions from `agent_orchestration.dart` into instance methods. Translate the print-mode body from `session_runtime.dart:3-155` into `runPrint(...)`. All `app._X` accesses become either `this.X` (for fields TurnRunner owns), `this.callback()` (for state-on-App), or direct field access (for injected deps like `transcript`, `renderer`).

2. **Wire `TurnRunner` into `App`**:
   - Add `late final TurnRunner _turns;` field.
   - Construct in `App` body (similar to how `_panels`, `_docks`, etc. are wired). The trick: `TurnRunner` needs `Config`/`Session` which are built in `_AppCommandContext`. Two options:
     (a) Move `Config`/`Session` construction into `App` itself (they're runtime services, not command-adapter things anyway), then both `_AppCommandContext` and `TurnRunner` reuse them.
     (b) Have `_AppCommandContext` hand the `Config`/`Session` instances back.
     **Prefer (a)**: move `Config`/`Session` instantiation into `App` (near `_transcript`/`_renderer` construction). Update `_AppCommandContext` to take them from `app._config_service` / `app._sessions_service` or similar. This is clean.
   - Thin delegates on App for backward compat with part-file callers:
     - `void _startAgent(msg, {expanded}) => _turns.startInteractive(msg, expandedMessage: expanded)`
     - `void _cancelAgent() => _turns.cancel()`
     - `Future<void> _runPrintMode() => _turns.runPrint(...)` — App still builds `expandedPrompt` from startupPrompt+stdin (keeps stdin handling out of TurnRunner's concerns).

3. **Delete `app/agent_orchestration.dart`**:
   - Remove the `part 'app/agent_orchestration.dart';` declaration in `app.dart`.
   - Remove the 12 thin delegate methods on `App` that forwarded to `_*Impl` functions: `_endTurnSpan`, `_startAgent` (now delegates to `_turns`), `_handleAgentEvent`, `_executeAndCompleteTool`, `_cancelAgent`, `_persistTrustedTool`, `_approveTool`, `_denyTool`, `_showToolConfirmModal`, `_traceToolApproval`. Only keep `_startAgent` and `_cancelAgent` as the compat entry points (their callers live in part files that haven't moved yet).

4. **Reduce `app/session_runtime.dart`** — delete `_runPrintModeImpl` (lines 3-155). Keep the session-title machinery (resume/generateTitle/reevaluateTitle/etc.) intact; those move in C4.

5. **Update `app.dart.run()`** — the print-mode path at top of `run()` currently calls `_runPrintMode()`. Keep that, but have `_runPrintMode` build `expandedPrompt` (combining `_startupPrompt` + stdin) and call `_turns.runPrint(...)`.

6. **Test**: `dart analyze --fatal-infos`, `dart test`, `dart format`, `just ui-check`. Interactive smoke: `dart run bin/glue.dart` → send a message that triggers a tool call → approve → see it work. Print mode: `echo "hi" | dart run bin/glue.dart -p "summarize"` → output on stdout.

## Critical files

Before touching anything:
- `cli/lib/src/app.dart` — field declarations + delegate methods at lines ~117-210, 500-560
- `cli/lib/src/app/agent_orchestration.dart` (336 lines) — the main source
- `cli/lib/src/app/session_runtime.dart:1-155` — print mode body to extract
- `cli/lib/src/runtime/transcript.dart` — the target for transcript mutations
- `cli/lib/src/runtime/renderer.dart` — spinner start/stop
- `cli/lib/src/runtime/services/session.dart` — may need `logEvent(name, data)` added as a facade method (currently TurnRunner would need `session.manager.logEvent(...)` which pierces the facade; cleaner to add `logEvent` to `Session`)
- `cli/lib/src/orchestrator/permission_gate.dart` — factory, already consumed via `app._permissionGate` getter
- `cli/lib/src/agent/agent_core.dart` — the agent event types (`AgentTextDelta`, `AgentToolCall`, etc.)
- `cli/lib/src/observability/observability.dart` + `redaction.dart` — span APIs
- `cli/lib/src/storage/config_store.dart` — used by `_persistTrustedToolImpl` to persist trusted tool
- `cli/lib/src/ui/components/modal.dart` — `ConfirmModal`, `ModalChoice`

## Coupling gotchas

1. **`_activeModal` is shared** with `_AppConfirmationHost` (generic confirm flow used by model controller's Ollama-pull confirm). Don't try to make TurnRunner the sole owner — both need to set/clear it. Pass setter+getter callbacks.

2. **`_permissionGate` is a getter that builds a fresh instance each call** (`app._permissionGate`). TurnRunner takes a factory callback `PermissionGate Function()` and calls it per-use.

3. **`_trustedTools` (`_autoApprovedTools`) is mutable trust preferences** persisted to disk. Keep ownership on App; TurnRunner mutates the set (for "Always" clicks) and calls a callback to persist. Or just pass the set reference directly — mutations land in the same set object that App exposes via `autoApprovedTools()` closure to SessionController.

4. **`_reevaluateTitleImpl(app)` is called after every turn** from `AgentDone`. Keep the same hook: TurnRunner takes `void Function() onTurnComplete` callback, App wires it to `_reevaluateTitleImpl(this)`.

5. **`session.logEvent` does not exist yet** on the `Session` facade. Add it as a small method: `void logEvent(String name, Map<String, dynamic> data) => manager.logEvent(name, data)`. Also add `void ensureStore({String? cwd, String? modelRef})` — or keep the existing `ensureStore()` that uses the callback. The turn code calls `app._ensureSessionStore()` which reads cwd + modelRef from App state. Simplest: keep `Session.ensureStore()` as-is (no params), which uses the already-passed-in `ensureStore` callback that reads app's cwd/modelRef.

6. **Print mode resume semantics** (`session_runtime.dart:5-18`) are slightly different from interactive resume — it requires a non-empty session id and writes to stderr on error. Include this in `runPrint(resumeSessionId:)`.

7. **Print mode `onDone` cleanup** (tool disposal, obs flush/close, session close) is currently in the `finally` block of `_runPrintModeImpl`. This is App-level teardown, not turn-level. Keep it in App's print-mode wrapper method, NOT in TurnRunner.runPrint. TurnRunner.runPrint just runs the turn; App wraps with teardown.

## Verification

Per the roadmap verification checklist:

1. `cd cli && dart format --set-exit-if-changed .`
2. `cd cli && dart analyze --fatal-infos` — only the 4 pre-existing `shell_runtime.dart` / `shell_job_manager.dart` warnings.
3. `cd cli && dart test` — all 1505 tests pass.
4. `just ui-check` — still clean.
5. Interactive smoke via `dart run bin/glue.dart`:
   - `/model` still works, ollama-pull confirmation still works (validates `_activeModal` sharing).
   - Send a message that needs a tool → approval modal appears, "Yes"/"No"/"Always" all work.
   - Ctrl+C during streaming cancels.
   - Resume a session (`/resume`) + continue conversation.
   - Title generation still happens after turn completes.
6. Print mode smoke via `echo "2+2" | dart run bin/glue.dart -p "what is this"` — output lands on stdout, session is saved, obs closes cleanly.
7. Confirm `cli/lib/src/app/agent_orchestration.dart` no longer exists.
8. Confirm `_runPrintModeImpl` no longer exists in `cli/lib/src/app/session_runtime.dart`.

## What C1 does NOT do

- Does not touch `_handleSubagentUpdate` (C5 folds it into Transcript).
- Does not touch bash mode (C3).
- Does not touch session/title machinery beyond what's directly referenced (C4).
- Does not remove `_modelId` field from App (it's still used for span attrs + display label; can be collapsed when `_modelId` redundancy with `_config.activeModel.modelId` is addressed).
- Does not delete `app/models.dart` (still holds `_TitleTarget` until C4 absorbs titles).

## One design decision to resolve before executing

**Should `Config` + `Session` be App fields or stay `_AppCommandContext` locals?**

Currently (post-B3): `_AppCommandContext` constructs `Config` + `Session` in its initializer list and holds them as private fields. Only controllers see them.

TurnRunner also needs `Config` + `Session`. Options:
- (a) **Move `Config` + `Session` construction to `App`** — they become sibling fields to `_transcript`/`_renderer`, constructed in App's body. `_AppCommandContext` reads them from App. TurnRunner reads them from App. Clean, services live where they logically belong.
- (b) **Keep in `_AppCommandContext`, pass to TurnRunner via constructor closures** — ugly, treats `_AppCommandContext` as the service owner when it's really just a consumer.

**Recommendation: (a).** Move `Config` + `Session` to `App`. Touch `command_host_adapter.dart` to read them from `app._configService` + `app._sessionService` instead of constructing locally. This is a small refactor within C1 scope.

