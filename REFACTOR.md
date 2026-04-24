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
| `confirmations` | ui | Ask the user yes/no with a blocking modal (`Confirmations` interface in `ui/services/confirmations.dart`) |
| `transcript` | ui | Append a system notice to the rendered block list (UI-only, not LLM-visible) |
| `config` | domain | Read/update `GlueConfig`; set active model; also owns the trusted-tools allow-list |
| `session` | domain | Current session, list, resume, fork, rename, title generation. Facade over `SessionManager`; disk-level `storage/session_store.dart` stays underneath |

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
- **Controllers** — `<Feature>Controller` (no prefix). `ModelController`, `ProviderController`, etc. The `Default*` prefix used by the pre-refactor code has been dropped everywhere.
- **Feature panels** — live in their feature module, not in `ui/`. Named after the feature they serve (`SkillsPanel`, `DeviceCodePanel`, `ApiKeyPromptPanel`, `ModelPickerRowBuilder`), not tagged with generic suffixes.
- **Domain values** — pick the noun the domain uses, no architectural suffix. `Turn` (one user message → assistant response → maybe tools, ephemeral per cycle) is the canonical example: industry-standard in OpenAI Codex, pi-mono, Assistants API, and already load-bearing internally as the `agent.turn` observability span name. No `*Runner`, `*Manager`, `*Handler`, `*Coordinator` — the domain word is the name.

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
├── runtime/                      ← App composition helpers + per-feature controllers
│   ├── app_events.dart           (sealed AppEvent hierarchy)
│   ├── app_mode.dart             (AppMode enum)
│   ├── turn.dart                 (per-turn lifecycle + tool-approval flow)
│   ├── input_router.dart         (central terminal-event dispatcher)
│   ├── transcript.dart           (conversation UI state + subagent grouping)
│   ├── renderer.dart             (60fps render scheduler + spinner)
│   ├── permission_gate.dart      (tool-approval policy — was orchestrator/)
│   ├── tool_permissions.dart     (safe-tool lists — was orchestrator/)
│   ├── services/                 (config.dart, session.dart)
│   ├── commands/                 (command_host, command_module, register_builtin_slash_commands)
│   └── controllers/              (one file per controller)
│
├── utils.dart                    ← extension helpers (bytes, durations, timeAgo)
│
└── app.dart + app/*.dart         ← composition root plus 3 remaining part files
                                    (command_host_adapter, event_router, render_pipeline).
                                    app/ no longer holds any runtime logic.
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

### Group C1 — `Turn` extraction (landed)

- **Zone-scoped observability context.** `Observability.runInContext(fn)` installs a fresh `_SpanHolder` in `Zone.current`; `activeSpan` get/set reads/writes it. Legacy mutable-field pattern inside `Agent`'s streaming loop still works (operates on the per-context holder when wrapped). 10 new tests cover nesting, await propagation, concurrent isolation, exception propagation. The original zone-value-as-span approach was rejected because it can't survive `yield` in an `async*` generator.
- **`runtime/turn.dart`** — per-turn value with `run(displayMessage)` / `runPrint(expandedPrompt, jsonMode)` / `cancel()`. Owns span, stream subscription, early-approved IDs. Same class handles interactive and print mode. Subagent turns can use the same class (future).
- **Trusted-tools moved onto `Config`.** `config.trustedTools` (Set<String>) + `config.trustTool(name)` replace the mutable `_autoApprovedTools` field on App. `PermissionGate` reads from the service.
- **`Config` + `Session` services** now live on App (fields), not inside `_AppCommandContext`. `Turn` and command controllers share the same instances. `Session` gained a `logEvent(name, data)` facade.
- **Deleted**: `app/agent_orchestration.dart` (340 lines of free functions). `app/session_runtime.dart` lost its 155-line `_runPrintModeImpl` (title machinery stays).
- **App shrank**: `_startAgent` is now `Turn(…)..run()`. `_cancelAgent` is `_currentTurn?.cancel()`. `_runPrintMode` preps the prompt + session resume, delegates to `Turn.runPrint`, then handles app-level teardown (tool dispose, obs flush/close, session close) in its `finally`. The 10 thin `_*Impl` delegate methods are gone.
- 1515 tests passing (10 new Zone-based observability tests). Analyzer clean (4 pre-existing shell warnings).

### Cleanup pass (post-C + D)

- **`orchestrator/` folder retired.** Two files (`permission_gate.dart`, `tool_permissions.dart`) moved into `runtime/`. No "orchestration" was happening; they're runtime policy used by `Turn`/`Config`.
- **`app/model_display.dart` → `catalog/model_display.dart`.** It was never a part file, just a formatter over `ModelRef`/`ModelCatalog` data. Belongs next to the catalog types.
- **`extensions/units.dart` → `utils.dart`.** Single-file folder retired; file relocated to top level. Added `DateTime.timeAgo` extension, collapsing two duplicate `_timeAgo` copy-pastes. Wired up `N.seconds` / `N.milliseconds` / `N.kilobytes` replacements at ~20 sites across agent/, shell/, web/, providers/, config/.
- **`app/command_helpers.dart` unwound.** `_addSystemMessage` was a one-liner wrapper around `Transcript.postNotice` — 5 callsites switched to `transcript.postNotice` directly; the method is gone. `_statusModelLabel` was a one-call wrapper — inlined at its single site in `render_pipeline.dart`. `_activateSkillFromUi` was real skill-activation logic — moved onto `App` as a method. The part file is deleted.
- **`ConfirmationHost` → `Confirmations`.** Moved from `runtime/controllers/` to `ui/services/` for naming parallelism with `Panels`/`Docks`. The interface stays because the `_AppConfirmations` impl integrates with `App._activeModal`.
- **Tools service closed** as "not building". Single existing caller (skill activation) works fine without a service facade; no dynamic registration need.

### Rename + polish pass

- **`app/command_host_adapter.dart` → `app/controllers.dart`.** Class `_AppCommandContext` → `_AppControllers`. The old name stacked three architecture words to say "where App builds its controllers."
- **`app/render_pipeline.dart` → `app/paint.dart`.** Function `_doRenderImpl` → `_paint`. No pipeline exists; it's one paint function.
- **`app/event_router.dart` deleted.** Folded into `App._handleAppEvent` as a method. 42 lines of 4-case switch didn't need its own file.
- **`Transcript.postNotice` → `Transcript.system`.** Matches `EntryKind.system` exactly.
- **Controllers take `Transcript` directly.** Five controllers (Model/Session/Share/Skills/Provider) dropped `addSystemMessage: void Function(String)` closures in favour of `transcript: Transcript`. ~40 internal call sites swapped to `transcript.system(...)`.
- **SessionController inlined `historyEntries` closure.** Now that it has `Transcript`, it walks `transcript.blocks` itself.
- **Pre-existing shell warning fixed.** `shell_job_manager.dart:155` unnecessary `!` operator removed. Analyzer is now at zero issues.

### Test-suite reorganisation

- 14 root-level `*_test.dart` files moved into module folders (`test/agent/`, `test/ui/rendering/`, `test/input/`, `test/terminal/`, `test/commands/`, `test/bin/`).
- Orphaned `test/orchestrator/` retired; its one file moved to `test/runtime/`.
- Duplicate `slash_autocomplete_test.dart` reconciled (root-level 329-line version kept; 71-line subset in `test/commands/` deleted).
- `test/` now mirrors `lib/src/`. Test count: 1511 (was 1515 before the duplicate deletion).

### Evaluated, not doing

- **Delete `*CommandController` interfaces + `SlashCommandContext`.** Looked like ceremony. Investigation: 470-line `builtin_commands_test.dart` uses `BuiltinCommands.create(...)` closure path to unit-test slash dispatch without dragging in the full runtime. Rewriting to construct real controllers adds ~150 lines net. Interfaces are the "real polymorphism" case the naming rule whitelisted.
- **Adapter self-registration (Option α).** Would replace the 10-line `AdapterRegistry([...])` construction in `service_locator.dart` with per-adapter `register(registry)` calls. After writing it out: same clarity, more surface area. Not a win.
- **Merge adapter + client into one `Provider` class per vendor (Option β).** Would save ~150 LoC by collapsing `AnthropicAdapter` + `AnthropicClient` into `AnthropicProvider`, etc. Yellow-risk: `LlmClient` interface would move from `agent/` to `llm/interface.dart`; Copilot's OAuth complicates the merge. Deferred until we onboard 2+ new providers in a session, which would make the adapter boilerplate painful.

Final `app/*.dart` list: `controllers.dart` (152 lines, 7-controller wiring) and `paint.dart` (210 lines, frame paint). Both tightly coupled to App by nature.

---

## What's Next

Groups A, B, C, and a scoped D1 are **complete**. `App` is no longer a god-class; it's a composition root plus lifecycle + paint. What remains is polish.

### Group C — Runtime decomposition (all landed ✅)

- ~~**C1. Extract `Turn`**~~ ✅ Observability moved to zone-scoped holder; `Turn` owns per-turn span, subscription, and approval flow.
- ~~**C2. Extract `InputRouter`**~~ ✅ `runtime/input_router.dart` is the traffic cop; `app/terminal_event_router.dart` deleted.
- ~~**C3. Extract `BashMode`**~~ ✅ `shell/bash_mode.dart` owns the `!`-prompt lifecycle; `app/shell_runtime.dart` deleted.
- ~~**C4. Session service absorbs title + resume + fork + replay**~~ ✅ `SessionTitleStateController` folded into `Session`'s private flags; `app/session_runtime.dart` deleted.
- ~~**C5. Subagent grouping into Transcript**~~ ✅ `Transcript.handleSubagentUpdate`; `app/subagent_updates.dart` deleted.

### Group D — Removal (all landed ✅)

- ~~**D1 (scoped)**~~ ✅ `AppShell` + `AppLaunchOptions` were thin wrappers and got merged into `App` directly; signal handling moved into `App.run()`. `AppMode` moved to `runtime/app_mode.dart`. `bin/glue.dart` targets `App.create()` directly. Three `app/*.dart` part files remain — they're the composition adapter, event-router, and paint pipeline; each is small and cleanly scoped, and unwinding them would push 20+ private fields through constructor injection for no observable benefit.
- ~~**D2. `Default*` prefix**~~ ✅ Already done in A4.
- ~~**D3. `lib/glue.dart` barrel**~~ ✅ Deleted entirely. Glue is a binary, not a library; the barrel was ceremony. `bin/glue.dart` and tests now import directly from `package:glue/src/...`, making dependencies visible in the import block.

Landed naming simplification alongside the above:

- `AgentCore` → `Agent`. The ReAct loop + conversation state carries the name of what it is. Also absorbs `AgentRunner` as `Agent.runHeadless(msg, {policy, allowedTools, onEvent})`, deleting that class.
- `AgentManager` → `Subagents`. Lowercase-plural service name fits the roster; `spawnSubagent()` → `spawn()` (context makes the noun redundant).

### Deferred (not now)

- **Global event bus for module/plugin hooks.** Once feature modules stabilise, it's worth exploring a typed `AppEvents` bus modelled on codex's `AppEventSender` — features emit events (e.g. `ModelSwitched`, `SessionResumed`, `SkillActivated`, `ToolApproved`) and other modules/future plugins subscribe. Keep it **separate from streams at async boundaries** — the bus is for cross-module notification, not for realtime streaming. Not doing this yet: we don't have enough cross-module coordination to justify it, and premature pubsub is a smoothness risk. Trigger: the first feature that needs to subscribe to a lifecycle event of a thing it doesn't own.
- **Unified `FeatureModule` plugin abstraction.** Defer until 3+ modules all want the same registration hooks. The gemini-cli loader/registry pattern is the destination but not this commit. Trigger: a third registration source (file-system commands, third-party plugins, MCP command registry) that doesn't fit the hardcoded `_AppCommandContext` pattern.
- **Session storage format changes.** Locked until runtime parity is established.

### Not building (investigation closed)

- ~~**`llm` / `agent` service.**~~ Investigation during C1 planning found only 2 callsites outside the main agent loop (title generation via `_createTitleLlmClient`; subagent spawning via `Subagents`). Both already well-factored through `LlmClientFactory`. A service facade would be pure ceremony. Revisit if a third kind of "ask the LLM directly" callsite appears.
- ~~**`TurnRunner` / chat-turn unification.**~~ Obsoleted by C1 — interactive and print mode converged through the single `Turn.run` / `Turn.runPrint` API.
- ~~**`tools` service.**~~ Investigation found (a) tools are never dynamically registered — `service_locator.dart` builds the tool map once at init, no MCP, no plugin surface; subagents copy-filter the existing map; (b) only one current caller (`skills/skill_activation.dart`) invokes a tool and records it as a synthetic ToolCall/ToolResult pair, and it works fine without a service facade. Revisit if a second independent feature needs "invoke a tool and record it as if the model emitted the call".
- ~~**`Panels`/`Docks`/`Confirmations` unification into one `ui` service.**~~ Considered; rejected. The three are semantically distinct (transient stack vs. persistent side panel vs. blocking yes/no) and no controller takes more than two at once. Forcing a facade would lose the distinction without eliminating the different interaction models. `Confirmations` did get renamed from `ConfirmationHost` and moved to `ui/services/` for naming parallelism with `Panels`/`Docks`.

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

- ~~**Observability.activeSpan is mutable shared state.**~~ Addressed in C1: the active span now lives in a zone-scoped `_SpanHolder` via `Observability.runInContext`. Classic save/restore still works (and remains the pattern inside `Agent`'s streaming loop), but each `Turn` gets its own holder — concurrent subagents can't corrupt parent context.
- **Streaming smoothness is a product requirement.** Any architectural move that adds generic pubsub or re-renders per event is a regression even if the code is "cleaner". Stream only at true async boundaries.
- **Session persistence is format-locked** until the runtime reshuffle stabilises. Don't bundle schema changes into structural commits.

---

## Acceptance Criteria (unchanged)

- No lost or reordered streamed output.
- Input responsive during agent streaming, tool execution, background jobs.
- All existing slash commands and key workflows intact.
- Existing config and session data remain readable.
- New runtime shape visible in code structure, not just naming.
