# Glue CLI Refactor — End Goals, Progress, and Patterns

This is a living document. Updated as each phase lands. Order from top to bottom: **where we're headed**, **what's done**, **what's next**, **what we learned**.

---

## End Goal

Three things, and only these three:

1. **Layered code that says what it is.** Core primitives (panels, docks, autocomplete, tables, themes) know nothing about features. Feature modules (skills, models/catalog, providers, session, share) own their data, their commands, and their UI surfaces. `App`/`AppShell` is only composition + lifecycle.

2. **Narrow, general services between layers.** Features talk to core via a small set of named services — never by reaching into `App`'s private fields. Services hold common primitives; they do not grow feature-specific helpers.

3. **Preserve streaming smoothness.** The TUI already feels good. Any move that adds generic pubsub or per-event re-render churn is a regression even if the code looks cleaner. Streams stay at real async boundaries only: terminal input, agent turn output, shell jobs, subagent updates, auth flows.

Target shape phrase, borrowed from the codex log: **opencode-shaped routing through services, with an obsidian-style registration surface for feature modules** — but without committing to a unified `FeatureModule` abstraction until 3+ modules obviously want it. YAGNI over cleverness.

### Service Roster

The canonical set features compose to do anything useful. Each is narrow. Add methods only when a concrete caller needs them.

| Service | Layer | Purpose |
|---|---|---|
| `panels` | ui | Push/remove modal overlays, route keys, render the stack |
| `docks` | ui | Register/unregister docked panels with lifecycle tokens |
| `confirmations` | ui | Ask the user yes/no with a blocking modal |
| `transcript` | ui | Append a system notice to the rendered block list (UI-only, not LLM-visible) |
| `tools` | agent | Invoke a tool through the normal dispatch pipeline — transcript records ToolCall + ToolResult as if the model emitted the call |
| `config` | domain | Read/update `GlueConfig`; set active model; centralises what is today 3+ separate closures |
| `session` | domain | Current session, list, resume, fork, rename. Facade over `SessionManager`; disk-level `storage/session_store.dart` stays underneath |

Two layers' worth of services. Features pick what they need. Nothing feature-specific lives on any of them.

---

## Research Synthesis (Patterns Worth Stealing)

Survey of four comparable TUIs: **codex** (Rust), **opencode** (Go/Bubble Tea), **gemini-cli** (TS/React Ink), **roocode** (React webview). Focus was layering, naming, and registration.

### Patterns we keep

- **codex's `BottomPaneView` trait + overlay stack** — one trait, one stack of `Box<dyn …>`, parent routes input. We already have this shape in `PanelOverlay` + our new `panels` service; the research confirms the direction.
- **codex's `AppEventSender` one-way bus** — features emit events, a central widget folds them into the transcript. Matches glue's existing `AgentEvent` architecture. Reinforces the user's guidance: **no skill-specific service** — prefer a small general primitive (e.g. "dispatch a tool as if the LLM emitted it").
- **roocode's primitive/feature visual split by casing** — `components/ui/` for kebab-case primitives vs `components/<feature>/` for PascalCase features. Cleanest split of the four. We won't copy kebab-case (non-idiomatic in Dart), but the *structure* — primitive folder vs feature-owned surfaces — is the model.
- **gemini-cli's loader + registry service pattern** — `BuiltinCommandLoader`, `FileCommandLoader`, `McpPromptLoader`, `SkillCommandLoader`, merged by `CommandService`, dispatched by `SlashCommandResolver`. This is the plugin-surface shape glue eventually wants, but it's the *finish line*, not this commit.

### Patterns we reject

- **opencode's `components/dialog/` bag** — flat namespace of all modals regardless of feature. Tempting but re-creates the problem: dialogs that only matter to one feature still live in the primitive tree. We want feature-owned panels.
- **gemini-cli's flat `components/` with ~150 files** — primitives and features mixed. Proves the need for an enforced split; don't replicate.
- **`Impl` suffix everywhere** — none of the reference projects use it. An interface + one `FooImpl` concrete class with no behavior is boilerplate when there's no second implementation. Keep interfaces only when they carry behavior or enable testing against a different implementation.

---

## Naming Conventions

Settled conventions for the target shape:

- **`AbstractPanel`** — the base panel interface (what `PanelOverlay` is today). Other panel types implement it: `Panel`, `SelectPanel`, `SplitPanel`.
- **`Panel`** — the everyday concrete panel (what `PanelModal` is today). Bordered content box with scroll/selection. This is what most feature flows open.
- **`SelectPanel<T>`** — filterable list panel. Already named correctly; stays.
- **`SplitPanel`** — the two-column variant (was `SplitPanelModal`).
- **`Modal`** — a blocking yes/no confirm (`ConfirmModal`). Kept distinct from `Panel` because the interaction model differs.
- **`DockedPanel`** — a side-docked panel (skills browser, etc.). Stays.
- **Services** — plural lowercase nouns on controllers: `panels`, `docks`, `confirmations`, `config`, `session`, `transcript`, `tools`. No `Impl` suffix — concrete classes get functional names (`Panels`, `Docks`) when there's one production implementation; promote to an interface + multiple impls only when a real second impl appears.
- **Controllers** — keep the `<Feature>Controller` pattern already established (`DefaultModelCommandController`, etc.). Drop the `Default*` prefix over time — it was a placeholder from the early cut. `ModelController`, `ProviderController`, etc.
- **Feature panels** — live in their feature module, not in `ui/`. Named after the feature they serve (`SkillsPanel`, `DeviceCodePanel`, `ApiKeyPromptPanel`, `ModelPickerRowBuilder`), not tagged with generic suffixes.

---

## Folder Structure — Target

```
cli/lib/src/
├── ui/                           ← primitives only, zero feature imports
│   ├── services/
│   │   ├── panels.dart           (Panels)
│   │   └── docks.dart            (Docks)
│   ├── components/               ← grouped by concept, not one-class-per-file
│   │   ├── panel.dart            (AbstractPanel, Panel, SelectPanel, SplitPanel, PanelSize family)
│   │   ├── dock.dart             (DockedPanel, DockManager, DockEdge/Mode, layout rects)
│   │   ├── tables.dart           (ResponsiveTable, TableFormatter, TableColumn, TableAlign)
│   │   ├── overlays.dart         (AutocompleteOverlay, AcceptResult)
│   │   ├── modal.dart            (ConfirmModal, ModalChoice — distinct from Panel; blocking)
│   │   ├── box.dart              (Box — border glyphs, reusable independently)
│   │   └── theme.dart            (theme tokens + recipes, merged)
│   └── rendering/                ← formerly top-level rendering/, all UI-layer
│       ├── ansi_utils.dart
│       ├── block_renderer.dart
│       └── markdown_renderer.dart
│
├── skills/                       ← feature module: data + controller + panels
├── catalog/                      ← models
├── providers/                    ← auth + device_code_panel + api_key_prompt_panel
├── session/                      ← session service + title/turn machinery
├── share/                        ← share module (whole export pipeline + controller + /share)
├── storage/                      ← disk-level session_store + config_store; session/ wraps it
├── commands/                     ← slash_autocomplete + command registry
├── shell/                        ← shell_autocomplete + executors
├── input/                        ← at_file_hint + editors
│
├── runtime/                      ← AppShell + controllers + command module glue
│   ├── app_shell.dart
│   ├── app_launch_options.dart
│   ├── commands/                 (command_host, command_module, register_builtin_slash_commands)
│   └── controllers/              (one file per controller, eventually)
│
└── app.dart + app/*.dart         ← transitional; shrinks as controllers absorb behavior
```

Note on `rendering/`: moves wholesale into `ui/rendering/`. All three files (`ansi_utils.dart`, `block_renderer.dart`, `markdown_renderer.dart`) are UI-layer — `ansi_utils` has 16 consumers but every one is ui/, terminal/, input/, or runtime/controllers/. Zero agent/llm/storage callers. Move is mechanical but touches many imports, so do it in the same commit as the ui/ restructure, not as a separate cosmetic pass.

**Rule enforced in CI:** `cli/lib/src/ui/**` must not import from `catalog/`, `providers/`, `skills/`, `session/`, `commands/`, `shell/`, `agent/`, `llm/`, `storage/`, or `config/`. Added as a `just ui-check` target.

---

## What's Done

### Already landed before this refactor

- `AppShell` and `AppLaunchOptions` in `runtime/` — startup goes through the shell, not `App.create` directly.
- Controller-per-feature pattern established in `runtime/controllers/command_controllers.dart`:
  `DefaultSystemCommandController`, `DefaultChatCommandController`, `DefaultModelCommandController`,
  `DefaultSessionCommandController`, `DefaultShareCommandController`, `DefaultSkillsCommandController`,
  `DefaultProviderCommandController`.
- `ConfirmationHost` (`runtime/controllers/confirmation_host.dart`) — template for narrow host interfaces.
- Command module pattern in `runtime/commands/` — each builtin slash command registers through a `SlashCommandModule`.
- `SessionTitleStateController` replaced the three boolean flags that used to live on `App`.
- Provider adapter / LLM factory cleanup (`providers/llm_client_factory.dart`), title generator moved to `session/`.

### Group A — mechanical cleanup (all landed)

**A1. Share module consolidation.**
- `share/share_controller.dart` — `ShareController` (was `DefaultShareCommandController`, owns its own `ShareExporter` + `GistPublisher`).
- `share/share_module.dart` — `ShareCommandModule` (was private `_ShareCommandModule` inside `register_builtin_slash_commands.dart`). Publicly exposed.
- `share/share_exporter.dart` — renamed from `session_share_exporter.dart`; class `SessionShareExporter` → `ShareExporter`; `SessionGistPublisher` → `GistPublisher`.
- `App` no longer imports `share/*`; drops `_shareExporter`/`_gistPublisher` fields.

**A2. `ui/` restructure + rename.**
- Split `ui/` into `services/`, `components/`, `rendering/` (see folder diagram above).
- Components grouped by concept: `panel.dart` merges `panel_modal.dart` + `select_panel.dart` + `split_panel_modal.dart`. `dock.dart` merges `docked_panel.dart` + `dock_manager.dart`. `tables.dart` merges `responsive_table.dart` + `table_formatter.dart`. `theme.dart` merges tokens + recipes.
- Renames applied globally: `PanelOverlay` → `AbstractPanel`, `PanelModal` → `Panel`, `SplitPanelModal` → `SplitPanel`. `PanelsImpl` / `DocksImpl` flattened to just `Panels` / `Docks` (concrete, no abstract).
- Top-level `rendering/` folder moved wholesale into `ui/rendering/`.

**A3. Feature surfaces out of `ui/` + CI guard.**
- Moved: `skills_docked_panel` → `skills/`, `device_code_panel` + `api_key_prompt_panel` → `providers/`, `model_panel_formatter` → `catalog/`, `slash_autocomplete` → `commands/`, `shell_autocomplete` → `shell/`, `at_file_hint` → `input/`. Corresponding test files moved too.
- `cli/lib/src/ui/` now contains only `services/`, `components/`, `rendering/`. No root files, no feature imports.
- `just ui-check` added — fails if `ui/**` imports from any feature module. Wired into `just check`.

**A4. Split `command_controllers.dart` into one file per controller, drop `Default*` prefix.**
- 1469-line mega-file split into 6 per-controller files: `system_controller.dart`, `chat_controller.dart`, `model_controller.dart`, `session_controller.dart`, `skills_controller.dart`, `provider_controller.dart`.
- Concrete class names: `SystemController`, `ChatController`, `ModelController`, `SessionController`, `SkillsController`, `ProviderController`. Interfaces in `command_host.dart` stay as `*CommandController` — removing them is a later pass.
- `HistoryPanelEntry` moved into `session_controller.dart` (where it's used). `ProviderAction` + `providerActionsFor` moved into `provider_controller.dart`. `buildHelpLines` moved into `system_controller.dart`.

### Phase 1 (earlier) — `panels` and `docks` services, `PanelController` decomposed

- `cli/lib/src/ui/panels_service.dart` — `Panels` + `PanelsImpl` (push/remove/render).
- `cli/lib/src/ui/docks_service.dart` — `Docks` + `DocksImpl` (thin facade over `DockManager`).
- `cli/lib/src/ui/panel_controller.dart` **deleted**. 779-line god object gone.
- Controllers absorbed their own panel flows: model picker, provider auth (ApiKey + DeviceCode), provider list + action submenu, session resume/history/fork, help panel. Each controller now takes `Panels` directly.
- Skills controller takes `Docks` instead of `DockManager`.
- `App._commandContext` stored so the startup resume-picker path (`_openResumePanel()`) routes through the session controller.
- `lib/glue.dart` barrel export swapped `PanelController` → `Panels`/`Docks`; `HistoryPanelEntry`, `ProviderAction`, `providerActionsFor` re-exported from runtime.
- Full test suite green (1505 passed, 5 skipped). Analyzer clean (4 warnings pre-existing, unrelated).

---

## What's Next

Group A is **complete** (see "What's Done" above). The remaining work continues with Group B (state extraction), Group C (runtime decomposition), and Group D (App removal).

### Group B — State extraction (medium risk, highest leverage)

- **B1. Extract `Transcript`.** `runtime/transcript.dart` owns `_blocks`, `_toolUi`, `_scrollOffset`, `_streamingText`. Absorbs subagent event grouping (`_subagentGroups`, `_outputLineGroups`) — that's transcript behavior, not a separate coordinator. All callers route through it. `transcript.postNotice(text)` replaces `_addSystemMessage`.
- **B2. Extract `Renderer`.** `runtime/renderer.dart` owns render loop + spinner + 60fps coalescing. Consumes `Transcript` + panels + docks.
- **B3. `config` + `session` services.** Consolidate the 5–8 closures each controller takes for config/session state into two service objects. `session` is a facade over existing `SessionManager`; disk-level `storage/session_store.dart` stays underneath.

### Group C — Runtime decomposition (higher risk, bigger wins)

- **C1. Extract `TurnRunner`** (absorbs tool approvals). Replaces `agent_orchestration.dart` + the print-mode runner in `session_runtime.dart`. One path for interactive and non-interactive turns. Owns `_autoApprovedTools`, `_earlyApprovedIds`, and the approve/deny/confirm-modal flow — no separate `ToolApprovals` class.
- **C2. Extract `InputRouter`.** `runtime/input_router.dart`. Replaces `terminal_event_router.dart`. Central dispatcher with no business logic.
- **C3. Extract `BashMode`.** `shell/bash_mode.dart`. Owns the four bash fields + `submit`/`cancel`/`runBlocking`/`startBackground`. Keeps its identity because the process lifecycle is independent of agent turns.
- **C4. Collapse `session_runtime.dart` + `SessionTitleStateController` into the `session` service.** Print mode runner → `TurnRunner`. Title state (three booleans) + generation + `/rename` → internal behavior of the `session` service. `SessionTitleStateController` class is deleted.
- **C5. Fold subagent grouping into `Transcript`.** Move `_subagentGroups`/`_outputLineGroups` from `subagent_updates.dart` into `Transcript` as a method. No standalone coordinator class.

### Group D — Removal

- **D1. Delete `App` + `app/*` part files.** `AppShell` becomes the only composition root. `bin/glue.dart` targets it directly.
- **D2. Drop `Default*` prefix on controllers** (if not already done in A4).
- **D3. Narrow `lib/glue.dart` public surface.** Remove exports that were only there for part-file coupling. Re-audit every export.

### Deferred (not now)

- **`llm` / `agent` service.** Candidates for the service roster (features wanting to ask the LLM something directly, or start a turn programmatically), but the right shape depends on how the `AgentCore` loop is restructured and whether `TurnRunner` lands first. Revisit after agent-loop cleanup; until then, the rare code that needs the LLM passes `AgentCore` directly.
- **Global event bus for module/plugin hooks.** Once feature modules stabilise, it's worth exploring a typed `AppEvents` bus modelled on codex's `AppEventSender` — features emit events (e.g. `ModelSwitched`, `SessionResumed`, `SkillActivated`, `ToolApproved`) and other modules/future plugins subscribe. Keep it **separate from streams at async boundaries** — the bus is for cross-module notification, not for realtime streaming. Not doing this yet: we don't have enough cross-module coordination to justify it, and premature pubsub is a smoothness risk.
- **Unified `FeatureModule` plugin abstraction.** Defer until 3+ modules all want the same registration hooks. The gemini-cli loader/registry pattern is the destination but not this commit.
- **TurnRunner / chat-turn unification.** Separate cut.
- **Observability `activeSpan` mutable state.** Still a known risk; address when it starts biting.
- **Session storage format changes.** Locked until runtime parity is established.

---

## Emerging Patterns (Commitments, Not Guidelines)

Things we've decided to stick with. Anyone touching the codebase should recognise these:

1. **Controller per feature.** Each feature gets one controller class in `runtime/controllers/` (eventually one file each). Dependencies via constructor injection. No reaching into `App._privateField`.
2. **Service names are lowercase plural nouns.** `panels`, `docks`, `confirmations`, `chat`. Short. No `Service` suffix in the name — the folder or field context is sufficient.
3. **Narrow services; grow by need.** A service starts with 2–3 methods and grows only when a concrete caller needs a method. No speculative API.
4. **Features own their UI surfaces.** If a panel imports a feature's data types, the panel lives in that feature's module. Not in `ui/`.
5. **`ui/` is primitives only.** CI guard enforces this after Phase 4.
6. **No `Impl` suffix.** Interfaces only when they carry real polymorphism. One-impl interfaces are ceremony; delete them.
7. **Streams at real async boundaries only.** Don't wrap synchronous state in a `StreamController<T>` just because "events feel cleaner".
8. **Small general primitives over feature-specific helpers.** When tempted to add `someService.injectSkillCall()`, ask: is there a general primitive (`invokeTool`) that also covers this? If yes, use that.

---

## Known Risks

- **Observability.activeSpan is mutable shared state.** Concurrency + module separation make this increasingly unsafe. Move to zone-local context or explicit parent propagation before we add more concurrent paths.
- **Streaming smoothness is a product requirement.** Any architectural move that adds generic pubsub or re-renders per event is a regression even if the code is "cleaner". Stream only at true async boundaries.
- **Session persistence is format-locked** until the runtime reshuffle stabilises. Don't bundle schema changes into structural commits.

---

## Acceptance Criteria (unchanged)

- No lost or reordered streamed output.
- Input responsive during agent streaming, tool execution, background jobs.
- All existing slash commands and key workflows intact.
- Existing config and session data remain readable.
- New runtime shape visible in code structure, not just naming.
