# Plan: Glue Web UI POC with Datastar

## Context

Glue today has two existing UI directions: (a) static HTML mockups in
`_archived/agents/prototypes/` (vanilla + Alpine), and (b) a planned ACP-based
web UI in `docs/plans/2026-02-27-acp-webui.md` that would let editors and a
browser share one protocol implementation.

The user wants to explore a **third option**: a web UI POC built with
[Datastar](https://data-star.dev/) — a hypermedia framework that pushes HTML
fragments and signal patches over SSE and routes browser actions through plain
HTTP requests. The motivation is to see what this would look like in practice
with Datastar specifically, regardless of whether we keep it long-term.

The user's specific direction (after clarification):
- **Ignore ACP for now** — just want to see how it would look with Datastar.
- **Single session, single browser** for v1.
- **HTML asset as a separate file** in `cli/web/`, served from disk.
- Get the data model done first, then a small Dart shim, then the frontend.

---

## Architecture

```
Browser (Datastar)                       Dart shim                Glue
─────────────────────────                ─────────────            ──────────
data-on:submit="@post('/prompt')" ──── POST /prompt ──┐
                                                       │
GET /stream  (long-lived SSE)  ◄── datastar-patch-* ──┤
                                                       ▼
data-on:click="@post('/approve/:id?outcome=allow')"  AgentRunner
                                                       │
                                                       │ Stream<AgentEvent>
                                                       ▼
                                            WireEvent (Glue-native)
                                                       │
                                                       ▼
                                            DatastarRenderer:
                                              - HTML fragment per event
                                              - patch-elements over SSE
                                              - patch-signals for state
```

Two layers worth distinguishing:

1. **`WireEvent` (Glue-native)** — a minimal Dart sealed class mirroring the
   shape of `AgentEvent`. Lives entirely inside the `cli/lib/src/web/` module.
   No ACP coupling, no public JSON contract — it's an internal stepping stone
   between `AgentEvent` and the Datastar projection.
2. **Datastar projection** — translates each `WireEvent` into the appropriate
   `datastar-patch-elements` (HTML morph) or `datastar-patch-signals` (state
   merge) SSE event. Pure presentation; could be replaced later if Datastar
   doesn't pan out.

If we end up keeping Datastar, `WireEvent` stays an internal detail. If we
later add an ACP transport, the same `AgentEvent → wire` translation pattern
applies, but with ACP types instead — no migration needed.

---

## Data Model: `WireEvent`

Sealed class with minimal Glue-native variants. Each carries only what the
Datastar projection needs to render. Fields named for clarity, not for any
external spec.

| `WireEvent` variant     | From `AgentEvent`             | Carries                                       |
| ----------------------- | ----------------------------- | --------------------------------------------- |
| `TextDelta`             | `AgentTextDelta`              | `turnId`, `text`                              |
| `ToolStarted`           | `AgentToolCallPending`        | `callId`, `toolName`                          |
| `ToolReady`             | `AgentToolCall`               | `callId`, `toolName`, `args` (Map)            |
| `ToolFinished`          | `AgentToolResult`             | `callId`, `success`, `summary`, `content`     |
| `PermissionRequested`   | (synthesized at gate)         | `callId`, `toolName`, `args`, `reason`        |
| `TurnFinished`          | `AgentDone`                   | `turnId`                                      |
| `TurnFailed`            | `AgentError`                  | `turnId`, `message`                           |

Single factory: `WireEvent.fromAgentEvent(AgentEvent, {required turnId})`.
Permission events are synthesized in the shim's session adapter when
`PermissionGate.resolve()` returns `ask` — not coming from `AgentEvent` itself.

**Inbound (browser → server) actions** — small set, single-session so no
`sessionId` parameter:

| Endpoint               | Body                          | Effect                                    |
| ---------------------- | ----------------------------- | ----------------------------------------- |
| `POST /prompt`         | `text` (form-encoded)         | Start a turn                              |
| `POST /cancel`         | (none)                        | Cancel the active turn                    |
| `POST /approve/:callId`| `outcome=allow\|deny`         | Calls `agent.completeToolCall(...)`       |

**Existing files referenced (read-only — for reuse, not modification):**

- `cli/lib/src/agent/agent.dart:95-130` — `AgentEvent` definitions
- `cli/lib/src/agent/agent.dart:223` — `Stream<AgentEvent> Agent.run(String)`
- `cli/lib/src/agent/agent.dart:470` (approx.) — `agent.completeToolCall()`
- `cli/lib/src/agent/tools.dart:52-112` — `ToolCall`, `ToolResult` shapes
- `cli/lib/src/runtime/permission_gate.dart` — gate logic to drive
  `PermissionRequested` synthesis
- `cli/lib/src/boot/wire.dart` — composition root for the agent + tools

---

## Datastar Projection

Two Datastar SSE event types do all the work.

### `datastar-patch-elements` for streaming content

Token deltas append to a streaming block; tool calls morph cards into the
transcript.

Append a text delta:

```
event: datastar-patch-elements
data: selector #stream-{turnId}
data: mode append
data: elements <span>{escapedText}</span>
```

Insert a new tool card:

```
event: datastar-patch-elements
data: selector #transcript
data: mode append
data: elements <article id="tool-{callId}" class="tool pending"
data: elements   data-tool-name="{name}">
data: elements   <header>{name}</header>
data: elements   <pre class="args"></pre>
data: elements   <pre class="result"></pre>
data: elements </article>
```

Update an existing tool card by ID (outer morph):

```
event: datastar-patch-elements
data: selector #tool-{callId}
data: mode outer
data: elements <article id="tool-{callId}" class="tool completed">…</article>
```

### `datastar-patch-signals` for global state

A small global signal tree drives UI affordances (busy spinner, pending
permission). Datastar's signal patch is RFC 7396 merge-patch — fine for these
scalars/objects:

```
event: datastar-patch-signals
data: signals {busy: true}
```

```
event: datastar-patch-signals
data: signals {pendingPermission: {callId: "x", toolName: "bash", args: {...}}}
```

```
event: datastar-patch-signals
data: signals {pendingPermission: null}
```

Modal approve/deny buttons wired with
`data-on:click="@post('/approve/x?outcome=allow')"`.

**Why this split:** Datastar's signals don't support incremental array
mutations cleanly (RFC 7396 merge patch over an object), but they're great
for scalar UI state. Element patches handle the streaming list naturally.

---

## Dart Shim Server

New module under `cli/lib/src/web/` (mirrors existing `cli/lib/src/share/`
pattern).

| File                                      | Responsibility                                                                 |
| ----------------------------------------- | ------------------------------------------------------------------------------ |
| `cli/lib/src/web/wire_event.dart`         | `WireEvent` sealed class + `fromAgentEvent` factory                            |
| `cli/lib/src/web/datastar_renderer.dart`  | `WireEvent → List<SseFrame>` (escaping, fragment templates) — pure function   |
| `cli/lib/src/web/web_session.dart`        | Single active session: `AgentRunner` + broadcast `Stream<WireEvent>` + permission synthesis |
| `cli/lib/src/web/web_server.dart`         | `package:shelf` HTTP server: routes, SSE controller, action handlers, static asset serving |
| `cli/web/app.html`                        | Single static HTML file served from disk at `GET /`                            |
| `cli/lib/src/cli/web_command.dart`        | `glue web` subcommand definition                                               |
| `cli/lib/src/cli/runner.dart` (modified)  | Register `WebCommand`                                                          |
| `cli/pubspec.yaml` (modified)             | Add `shelf`, `shelf_router`                                                    |

**Asset path resolution** for `cli/web/app.html`: resolve relative to the
package root using `Platform.script` + `package:path`. For `dart run` from
`cli/`, it sits at `cli/web/app.html`. For an AOT-compiled binary, accept a
`--asset-dir` flag with a sensible default and document the constraint that
the asset must ship alongside the binary. (We can revisit bundling later if
this gets annoying.)

**Reused, not duplicated:**

- `Agent.run(String)` — the streaming source (no changes)
- `PermissionGate.resolve()` and `agent.completeToolCall()` — for the approval
  lifecycle (gate consulted in `web_session.dart`, decision relayed back via
  `completeToolCall`)
- `wireApp` in `boot/wire.dart` — composition root for the agent + tools

**Why a `glue web` subcommand:** matches the `glue <noun> <verb>` convention
in `CLAUDE.md` (cf. `glue config init`, `glue doctor`).

---

## Frontend (single HTML file at `cli/web/app.html`)

Self-contained, Datastar from CDN, no build step. Skeleton:

```html
<body data-signals="{busy:false, pendingPermission:null}"
      data-on-load="@get('/stream')">

  <header>
    <h1>Glue</h1>
    <button data-on:click="@post('/cancel')" data-show="$busy">Cancel</button>
  </header>

  <main id="transcript">
    <!-- Server-rendered chat blocks land here as Datastar element patches -->
  </main>

  <form data-on:submit="@post('/prompt')" data-show="!$busy">
    <textarea name="text" placeholder="Ask Glue…"></textarea>
    <button type="submit">Send</button>
  </form>

  <dialog data-show="$pendingPermission">
    <p>Tool <code data-text="$pendingPermission.toolName"></code> needs approval.</p>
    <pre data-text="JSON.stringify($pendingPermission.args, null, 2)"></pre>
    <button data-on:click="@post('/approve/' + $pendingPermission.callId + '?outcome=allow')">
      Allow
    </button>
    <button data-on:click="@post('/approve/' + $pendingPermission.callId + '?outcome=deny')">
      Deny
    </button>
  </dialog>

  <script type="module"
    src="https://cdn.jsdelivr.net/gh/starfederation/datastar/bundles/datastar.js">
  </script>
</body>
```

The HTML stays small because Datastar moves rendering responsibility to the
server — the page is mostly skeleton + slots.

---

## Implementation Steps

### Step 1 — `WireEvent` data model (no UI yet)

1. Define `WireEvent` sealed class in `cli/lib/src/web/wire_event.dart` with
   variants from the table above.
2. Add `WireEvent.fromAgentEvent(AgentEvent, {required String turnId})`.
3. Unit tests in `cli/test/web/wire_event_test.dart`: each `AgentEvent`
   variant maps cleanly; `turnId` propagates; tool call / pending ordering
   preserved.

**Done when:** Given a recorded `Stream<AgentEvent>` from a fixture turn,
mapping each event through `WireEvent.fromAgentEvent` yields the expected
ordered sequence.

### Step 2 — Datastar renderer (still no UI binding)

1. `DatastarRenderer.render(WireEvent) → List<SseFrame>` in
   `cli/lib/src/web/datastar_renderer.dart`. Pure function, no I/O.
2. HTML fragment templates as Dart string builders with explicit HTML
   escaping (small enough surface to hand-roll; use `package:html`'s escape
   helpers if available, otherwise a tiny inline escape).
3. Snapshot tests in `cli/test/web/datastar_renderer_test.dart` for each
   variant. Verify the multi-line `data: elements` framing, signal merge-patch
   shape, and that all dynamic strings are escaped.

**Done when:** Each `WireEvent` variant has a deterministic SSE byte-snapshot
test the Datastar client will accept.

### Step 3 — Shim server

1. Add `shelf` and `shelf_router` to `cli/pubspec.yaml`.
2. `cli/lib/src/web/web_session.dart`: holds the single active session
   (one `Agent`, one in-flight turn at a time). Owns a broadcast
   `StreamController<WireEvent>`. On a `POST /prompt`, runs `agent.run(text)`,
   maps each `AgentEvent → WireEvent` (synthesizing `PermissionRequested`
   when `PermissionGate.resolve` returns `ask`), pushes onto the controller.
3. `cli/lib/src/web/web_server.dart`: routes `GET /` (serve `cli/web/app.html`
   from disk), `GET /stream` (SSE; pipes session events through
   `DatastarRenderer`), `POST /prompt`, `POST /cancel`, `POST /approve/:callId`.
4. `cli/lib/src/cli/web_command.dart`: `glue web` with `--port` (default 8787),
   `--host` (default 127.0.0.1), `--model` (passes through to `wireApp`),
   `--asset-dir` (default: package-relative `web/`).
5. Register the command in `cli/lib/src/cli/runner.dart`.

**Done when:** `dart run bin/glue.dart web --port 8787 --model …` boots;
`curl -N localhost:8787/stream` shows live SSE events; `curl -d 'text=hi'
localhost:8787/prompt` triggers a turn whose Datastar SSE events appear on
the open `/stream` connection.

### Step 4 — Minimal frontend

1. Author `cli/web/app.html` with the skeleton above.
2. Wire form submit → `POST /prompt`, cancel button → `POST /cancel`,
   modal buttons → `POST /approve/:callId?outcome=…`.
3. Open in a browser; iterate on CSS lightly (just enough to read the
   transcript).

**Done when:** End-to-end demo works: open `http://localhost:8787` in a
browser, type a prompt, see streaming text + tool calls + an approval modal
for a destructive tool.

### Step 5 — Polish (post-demo, optional)

1. Diff rendering for `edit_file`/`write_file` results.
2. Markdown rendering for assistant text.
3. Reconnect-on-drop for the SSE stream.
4. (Multi-session and multi-browser are explicitly out of v1.)

---

## What's out of scope for this POC

- Authentication (single-user localhost only)
- Multi-session UI (sidebar of concurrent sessions)
- Multi-browser support (multiple tabs attached to the same session)
- Session resume from disk replay
- ACP / editor integration (separate plan exists)
- Multimodal `ContentPart` rendering beyond plain text
- HTTPS / production deployment
- Bundling `app.html` into the AOT binary (kept as a separate file by user
  preference for fast iteration)

---

## Verification

After Step 4:

1. `cd cli && dart test test/web/` — unit + snapshot tests pass.
2. `cd cli && dart run bin/glue.dart web --port 8787 --model …` starts the
   server.
3. Open `http://localhost:8787` in a browser.
4. Send a benign prompt (e.g. "list files in cwd"); confirm streaming text
   appears live and a `list_directory` tool card completes without an
   approval modal (read-only tool).
5. Send a destructive prompt (e.g. "create hello.txt with content 'hi'");
   confirm the approval modal appears, `Allow` lets the tool run, `Deny`
   aborts the turn cleanly.
6. Click cancel mid-stream; confirm the SSE stream emits a `TurnFailed` (or
   ends cleanly) and the UI returns to idle.
7. Use Chrome DevTools → Network → EventStream tab to confirm the SSE wire
   bytes match the renderer snapshots.
8. `cd cli && just check` passes (format + analyze + tests).

## Critical Files Touched

- **New:**
  - `cli/lib/src/web/wire_event.dart`
  - `cli/lib/src/web/datastar_renderer.dart`
  - `cli/lib/src/web/web_session.dart`
  - `cli/lib/src/web/web_server.dart`
  - `cli/lib/src/cli/web_command.dart`
  - `cli/web/app.html`
  - `cli/test/web/wire_event_test.dart`
  - `cli/test/web/datastar_renderer_test.dart`
- **Modified:**
  - `cli/pubspec.yaml` — add `shelf`, `shelf_router`
  - `cli/lib/src/cli/runner.dart` — register `WebCommand`
- **Reused unchanged:**
  - `cli/lib/src/agent/agent.dart`
  - `cli/lib/src/runtime/permission_gate.dart`
  - `cli/lib/src/boot/wire.dart`
