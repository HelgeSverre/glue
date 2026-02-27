# Plan: Glue Web UI via Agent Client Protocol (ACP)

## Overview

Build a web-based UI for Glue that communicates with the Glue CLI agent over the
[Agent Client Protocol](https://agentclientprotocol.com/). The web UI acts as an
**ACP Client** while Glue runs as an **ACP Agent** (server), the same role it
would play when embedded in editors like Zed or JetBrains.

This gives us one protocol implementation in Glue that serves both editor
integrations and our own web UI.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Browser                                                │
│  ┌───────────────────────────────────────────────────┐  │
│  │  app.html — Alpine.js                             │  │
│  │  ┌─────────────┐  ┌───────────────────────────┐   │  │
│  │  │ AcpClient   │  │ Alpine reactive store     │   │  │
│  │  │ (vanilla JS)│─▸│ sessions[], blocks[],     │   │  │
│  │  │             │  │ permissions, connection   │   │  │
│  │  └──────┬──────┘  └───────────────────────────┘   │  │
│  └─────────┼─────────────────────────────────────────┘  │
│            │ WebSocket (ws://localhost:3000)             │
└────────────┼────────────────────────────────────────────┘
             │
┌────────────┼────────────────────────────────────────────┐
│  Bridge    │                                            │
│  ┌─────────▼─────────┐                                  │
│  │  stdio-to-ws      │  npx stdio-to-ws                 │
│  │  WebSocket ↔ stdio│  "dart run bin/glue.dart --acp"  │
│  └─────────┬─────────┘                                  │
│            │ stdin/stdout (newline-delimited JSON-RPC)   │
│  ┌─────────▼─────────┐                                  │
│  │  glue --acp       │  Glue ACP Agent process          │
│  │  AgentCore + Tools│                                  │
│  └───────────────────┘                                  │
└─────────────────────────────────────────────────────────┘
```

---

## Two Sides to Implement

### Side 1: Glue ACP Agent (`glue --acp`)

A headless mode that speaks ACP over stdio. This is a prerequisite for the web UI
and also enables editor integrations (Zed, JetBrains, Neovim, VS Code).

**Library:** [`acp_dart`](https://github.com/SkrOYC/acp-dart) (v0.3.0) — handles
stdio framing, JSON-RPC routing, typed Dart objects. Depends on `json_annotation`,
`collection`, `path`.

**What to implement:**

| ACP Method           | Glue Mapping                                 | Notes                                           |
| -------------------- | -------------------------------------------- | ----------------------------------------------- |
| `initialize`         | Return capabilities, agent info              | Advertise `loadSession: false` initially        |
| `session/new`        | Create new `AgentCore` + tools per session   | Key by `sessionId`, use `params.cwd`            |
| `session/prompt`     | `AgentCore.run(userMessage)`                 | Stream events as `session/update` notifications |
| `session/cancel`     | Cancel the agent stream subscription         | Return `stopReason: cancelled`                  |
| `request_permission` | Before destructive tools (write, edit, bash) | Editor/web UI shows approve/deny                |

**Event mapping (inside `prompt`):**

| `AgentEvent`      | ACP `session/update` type | Content                                                                                 |
| ----------------- | ------------------------- | --------------------------------------------------------------------------------------- |
| `AgentTextDelta`  | `agent_message_chunk`     | `TextContentBlock(text: delta)`                                                         |
| `AgentToolCall`   | `tool_call`               | `toolCallId`, `title: call.name`, `kind`, `status: pending`                             |
| (tool executing)  | `tool_call_update`        | `status: in_progress`                                                                   |
| `AgentToolResult` | `tool_call_update`        | `status: completed/failed`, content with result text or `DiffToolCallContent` for edits |
| `AgentDone`       | (return `PromptResponse`) | `stopReason: endTurn`                                                                   |
| `AgentError`      | (return JSON-RPC error)   | Standard error codes                                                                    |

**Tool kind mapping:**

| Glue Tool        | ACP `ToolKind` |
| ---------------- | -------------- |
| `read_file`      | `read`         |
| `write_file`     | `edit`         |
| `edit_file`      | `edit`         |
| `bash`           | `execute`      |
| `grep`           | `search`       |
| `list_directory` | `read`         |
| `spawn_subagent` | `other`        |

**Permission model:** Request permission for destructive tools (`write_file`,
`edit_file`, `bash`). Auto-execute read-only tools (`read_file`, `grep`,
`list_directory`).

**File structure:**

| File                              | Purpose                                                         |
| --------------------------------- | --------------------------------------------------------------- |
| `lib/src/acp/glue_acp_agent.dart` | `Agent` implementation bridging to `AgentCore`                  |
| `lib/src/acp/acp_session.dart`    | Per-session state (AgentCore, tools, subscription)              |
| `bin/glue.dart` (modified)        | Add `--acp` flag, launch `ndJsonStream` + `AgentSideConnection` |

**Estimated size:** ~200–300 lines of Dart.

### Side 2: Web UI (ACP Client in the browser)

An Alpine.js single-page app that connects to Glue via WebSocket and renders the
agent's streaming output.

---

## Web UI: Two Approaches

### Approach A: Vanilla JS ACP Client (Recommended for v1)

Write a small `GlueAcpClient` class (~150 lines) directly in the `<script>` tag
that handles raw JSON-RPC over WebSocket. No build step, no npm, stays consistent
with the existing static site.

**Why this works:** The ACP client surface is genuinely small:

- **Outbound** (UI → agent): 4 methods
  - `initialize` — handshake
  - `session/new` — create session
  - `session/prompt` — send user message
  - `session/cancel` — abort

- **Inbound** (agent → UI): 2 handlers
  - `session/update` (notification) — text chunks, tool calls, plans
  - `session/request_permission` (request) — needs a response

**JSON-RPC client sketch:**

```javascript
class GlueAcpClient {
  constructor(wsUrl) {
    this._ws = null;
    this._nextId = 1;
    this._pending = new Map(); // id → {resolve, reject}
    this._handlers = {}; // method → callback
  }

  connect() {
    this._ws = new WebSocket(this.wsUrl);
    this._ws.onmessage = (e) => this._dispatch(JSON.parse(e.data));
    return new Promise((res) => (this._ws.onopen = res));
  }

  // Send a JSON-RPC request, return a promise for the response
  _request(method, params) {
    const id = this._nextId++;
    this._ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
    return new Promise((res, rej) =>
      this._pending.set(id, { resolve: res, reject: rej }),
    );
  }

  // Send a JSON-RPC notification (no response expected)
  _notify(method, params) {
    this._ws.send(JSON.stringify({ jsonrpc: "2.0", method, params }));
  }

  // Respond to an inbound request from the agent
  _respond(id, result) {
    this._ws.send(JSON.stringify({ jsonrpc: "2.0", id, result }));
  }

  _dispatch(msg) {
    if (msg.result !== undefined || msg.error) {
      // Response to our request
      const p = this._pending.get(msg.id);
      if (p) {
        this._pending.delete(msg.id);
        msg.error ? p.reject(msg.error) : p.resolve(msg.result);
      }
    } else if (msg.method) {
      // Inbound request or notification from agent
      const handler = this._handlers[msg.method];
      if (handler) handler(msg);
    }
  }

  // --- ACP methods ---

  async initialize(clientInfo) {
    return this._request("initialize", {
      protocolVersion: 1,
      clientCapabilities: {},
      clientInfo,
    });
  }

  async newSession(cwd) {
    return this._request("session/new", { cwd, mcpServers: [] });
  }

  async prompt(sessionId, text) {
    return this._request("session/prompt", {
      sessionId,
      prompt: [{ type: "text", text }],
    });
  }

  cancel(sessionId) {
    this._notify("session/cancel", { sessionId });
  }

  // --- Inbound handlers ---

  onSessionUpdate(callback) {
    this._handlers["session/update"] = (msg) => callback(msg.params);
  }

  onRequestPermission(callback) {
    // callback receives (params, respond) where respond(result) sends the reply
    this._handlers["session/request_permission"] = (msg) => {
      callback(msg.params, (result) => this._respond(msg.id, result));
    };
  }
}
```

**Alpine.js integration pattern:**

```javascript
function glue() {
  const client = new GlueAcpClient("ws://localhost:3000");

  return {
    connectionState: "disconnected",
    sessions: [],
    activeId: null,
    inputText: "",
    pendingPermission: null,

    async init() {
      await client.connect();
      this.connectionState = "connected";

      const { agentInfo } = await client.initialize({
        name: "glue-webui",
        title: "Glue Web UI",
        version: "0.1.0",
      });

      // --- Streaming updates ---
      client.onSessionUpdate((params) => {
        const session = this.sessions.find((s) => s.id === params.sessionId);
        if (!session) return;
        const update = params.update;

        switch (update.sessionUpdate) {
          case "agent_message_chunk":
            // Append to streaming block or create one
            const last = session.blocks.at(-1);
            if (last?.type === "assistant" && last.streaming) {
              last.text += update.content.text;
            } else {
              session.blocks.push({
                type: "assistant",
                text: update.content.text,
                streaming: true,
              });
            }
            break;

          case "tool_call":
            session.blocks.push({
              type: "tool",
              name: update.title,
              toolCallId: update.toolCallId,
              kind: update.kind,
              status: update.status,
              result: "",
            });
            break;

          case "tool_call_update":
            const tool = session.blocks.find(
              (b) => b.toolCallId === update.toolCallId,
            );
            if (tool) {
              tool.status = update.status;
              if (update.content?.length) {
                tool.result = update.content
                  .map((c) =>
                    c.type === "diff"
                      ? `${c.path} (edited)`
                      : (c.content?.text ?? ""),
                  )
                  .join("\n");
              }
            }
            break;
        }
      });

      // --- Permission requests ---
      client.onRequestPermission((params, respond) => {
        this.pendingPermission = {
          ...params,
          respond: (optionId) => {
            respond({ outcome: { outcome: "selected", optionId } });
            this.pendingPermission = null;
          },
          cancel: () => {
            respond({ outcome: { outcome: "cancelled" } });
            this.pendingPermission = null;
          },
        };
      });
    },

    async createSession(cwd) {
      const { sessionId } = await client.newSession(cwd);
      const session = {
        id: sessionId,
        cwd,
        blocks: [],
        streaming: false,
        tokens: 0,
      };
      this.sessions.push(session);
      this.activeId = sessionId;
    },

    async sendMessage() {
      if (!this.inputText.trim() || !this.activeId) return;
      const session = this.sessions.find((s) => s.id === this.activeId);
      // Mark previous streaming blocks as done
      session.blocks.forEach((b) => {
        if (b.streaming) b.streaming = false;
      });
      // Add user block
      session.blocks.push({ type: "user", text: this.inputText });
      const text = this.inputText;
      this.inputText = "";
      // Send prompt (resolves when the full turn is complete)
      const { stopReason } = await client.prompt(this.activeId, text);
      session.blocks.forEach((b) => {
        if (b.streaming) b.streaming = false;
      });
    },

    cancelPrompt() {
      if (this.activeId) client.cancel(this.activeId);
    },
  };
}
```

**Pros:**

- Zero build step — stays a single HTML file
- Full control over rendering and state
- Easy to understand and debug
- Consistent with existing website architecture

**Cons:**

- No TypeScript types — easy to mishandle a `sessionUpdate` variant
- No schema validation on incoming messages
- Manual JSON-RPC plumbing (but it's ~100 lines)

---

### Approach B: `@agentclientprotocol/sdk` + Vite

Use the official TypeScript SDK for full protocol correctness, with a Vite build
step.

**Dependencies:**

```json
{
  "dependencies": {
    "@agentclientprotocol/sdk": "^0.x",
    "alpinejs": "^3.x"
  },
  "devDependencies": {
    "vite": "^6.x",
    "typescript": "^5.x"
  }
}
```

**WebSocket → SDK Stream adapter (~20 lines):**

```typescript
import type { Stream, AnyMessage } from "@agentclientprotocol/sdk";

function webSocketStream(ws: WebSocket): Stream {
  const readable = new ReadableStream<AnyMessage>({
    start(controller) {
      ws.addEventListener("message", (e) => {
        controller.enqueue(JSON.parse(e.data));
      });
      ws.addEventListener("close", () => controller.close());
      ws.addEventListener("error", (e) => controller.error(e));
    },
  });
  const writable = new WritableStream<AnyMessage>({
    write(msg) {
      ws.send(JSON.stringify(msg));
    },
    close() {
      ws.close();
    },
  });
  return { readable, writable };
}
```

**Client setup:**

```typescript
import {
  ClientSideConnection,
  PROTOCOL_VERSION,
} from "@agentclientprotocol/sdk";

const ws = new WebSocket("ws://localhost:3000");
await new Promise((res) => ws.addEventListener("open", res));

const connection = new ClientSideConnection(
  (agent) => ({
    async sessionUpdate(params) {
      // Dispatch params.update into Alpine store
      const update = params.update;
      switch (update.sessionUpdate) {
        case "agent_message_chunk":
          /* ... */ break;
        case "tool_call":
          /* ... */ break;
        case "tool_call_update":
          /* ... */ break;
        case "plan":
          /* ... */ break;
      }
    },
    async requestPermission(params) {
      // Show Alpine modal, await user decision
      return new Promise((resolve) => {
        Alpine.store("permission").show(params, resolve);
      });
    },
  }),
  webSocketStream(ws),
);

await connection.initialize({
  protocolVersion: PROTOCOL_VERSION,
  clientCapabilities: { fs: { readTextFile: false, writeTextFile: false } },
  clientInfo: { name: "glue-webui", title: "Glue Web UI", version: "0.1.0" },
});
```

**Pros:**

- Full TypeScript types for all ACP messages
- Zod schema validation on incoming messages
- Correct JSON-RPC correlation handled by SDK
- Future-proof as ACP evolves

**Cons:**

- Requires build step (Vite), breaking single-HTML-file pattern
- Adds ~3 npm dependencies
- More complex project structure

---

### Approach C: `use-acp` React Hooks (Not recommended)

The [`use-acp`](https://github.com/marimo-team/use-acp) library by marimo-team
provides React hooks for ACP over WebSocket. It wraps the official SDK with
reactive state management (Zustand).

**Not recommended because:**

- Requires React — inconsistent with our Alpine.js stack
- The core protocol classes (`AcpClient`, `WebSocketManager`) are technically
  separable from React, but that's fighting the library rather than using it
- Adds React, Zustand, and the SDK as dependencies for something we can do in
  ~150 lines of vanilla JS

**When it would make sense:** If we later rebuild the web UI as a full React app
(e.g., for a hosted SaaS product), `use-acp` would be the right starting point.

---

## Bridge: `stdio-to-ws`

[`stdio-to-ws`](https://www.npmjs.com/package/stdio-to-ws) (by marimo-team)
bridges a stdio subprocess to a WebSocket server. It handles:

- Launching the subprocess
- Piping WebSocket messages → stdin, stdout → WebSocket messages
- NDJSON line framing (each stdout line = one WebSocket message)

**Usage:**

```bash
npx stdio-to-ws "dart run bin/glue.dart --acp" --port 3000
```

**Options:**

- `-p, --port <port>` — default 3000
- `-f, --framing <mode>` — `line` (default, for NDJSON) or `raw`
- `-q, --quiet` — suppress bridge logging

**Limitations:**

- Single-client only (one WebSocket connection = one agent process)
- No auth, no TLS — development use only
- No reconnection handling on the bridge side

**For production:** Replace `stdio-to-ws` with a custom backend that:

- Manages multiple agent processes (one per user/session)
- Handles authentication
- Persists session state
- Proxies WebSocket connections to the correct agent process

---

## `session/update` Notification Types Reference

All streamed via `session/update` notifications. The `update.sessionUpdate` field
is the discriminator:

| `sessionUpdate` value | Payload                                                            | UI action                                             |
| --------------------- | ------------------------------------------------------------------ | ----------------------------------------------------- |
| `agent_message_chunk` | `content: ContentBlock` (usually `TextContentBlock`)               | Append text to streaming assistant block              |
| `agent_thought_chunk` | `content: ContentBlock`                                            | Show in collapsible "thinking" block                  |
| `user_message_chunk`  | `content: ContentBlock`                                            | Echo user message (used during `session/load` replay) |
| `tool_call`           | `toolCallId`, `title`, `kind`, `status`, `locations?`, `rawInput?` | Create tool call block in UI                          |
| `tool_call_update`    | `toolCallId`, `status`, `content?` (text, diff, terminal)          | Update tool status, show result                       |
| `plan`                | `entries: [{content, priority, status}]`                           | Show agent's execution plan                           |
| `available_commands`  | `commands: [{name, description}]`                                  | Update slash command list                             |
| `current_mode`        | `currentModeId`                                                    | Reflect mode change in UI                             |

### Tool call content types (in `tool_call_update.content[]`):

| `type`     | Fields                       | UI rendering               |
| ---------- | ---------------------------- | -------------------------- |
| `content`  | `content: ContentBlock`      | Plain text result          |
| `diff`     | `path`, `oldText`, `newText` | Render as a file diff      |
| `terminal` | `terminalId`                 | Embed live terminal output |

### Tool call statuses:

`pending` → `in_progress` → `completed` | `failed`

### Stop reasons (in `PromptResponse`):

`end_turn` | `max_tokens` | `max_turn_requests` | `refusal` | `cancelled`

---

## Mapping to Existing `app.html` Mockup

The current mockup's data model maps directly to ACP concepts:

| Mockup concept               | ACP equivalent                                   |
| ---------------------------- | ------------------------------------------------ |
| `sessions[]`                 | One per `session/new` call, keyed by `sessionId` |
| `session.blocks[]`           | Built from `session/update` notifications        |
| `block.type === 'user'`      | User submits `session/prompt`                    |
| `block.type === 'assistant'` | `agent_message_chunk` updates                    |
| `block.type === 'tool'`      | `tool_call` + `tool_call_update` pairs           |
| `block.streaming`            | `true` while `session/prompt` is pending         |
| Tool pending approval        | `session/request_permission` → modal             |
| `sendMessage()`              | `session/prompt` RPC call                        |
| `closeSession()`             | Close WebSocket / cancel active prompt           |
| Session groups by project    | Group by `cwd` from `session/new`                |

---

## Client Capabilities to Advertise

For v1, keep it minimal:

```json
{
  "clientCapabilities": {}
}
```

No `fs` or `terminal` capabilities — Glue's tools handle file I/O and shell
execution directly via `dart:io`. The web UI just displays results.

Later, for a richer experience:

```json
{
  "clientCapabilities": {
    "fs": {
      "readTextFile": true,
      "writeTextFile": true
    },
    "terminal": true
  }
}
```

This would let the agent read unsaved editor state from the web UI (if we build
a code editor panel) and stream terminal output live.

---

## Implementation Order

### Phase 1: Glue ACP Agent (prerequisite)

1. Add `acp_dart` dependency to `pubspec.yaml`
2. Create `lib/src/acp/glue_acp_agent.dart` — implement `Agent` interface
3. Create `lib/src/acp/acp_session.dart` — per-session state management
4. Add `--acp` flag to `bin/glue.dart` — headless ACP entrypoint
5. Test manually: `echo '{"jsonrpc":"2.0","id":0,"method":"initialize",...}' | dart run bin/glue.dart --acp`
6. Test with Zed editor (validates correctness against a real ACP client)

### Phase 2: Minimal Web UI

1. Add the `GlueAcpClient` class to `app.html` (Approach A)
2. Wire `init()` → connect → initialize → ready state
3. Wire `createSession()` → `session/new`
4. Wire `sendMessage()` → `session/prompt` with `session/update` rendering
5. Wire `cancelPrompt()` → `session/cancel`
6. Add permission request modal → `session/request_permission` handling
7. Launch: `npx stdio-to-ws "dart run bin/glue.dart --acp" --port 3000`

### Phase 3: Polish

1. Tool call rendering — show kind icon, status badge, diff viewer for edits
2. Reconnection handling — auto-reconnect WebSocket with backoff
3. Multi-session — multiple concurrent sessions with tab/sidebar switching
4. Markdown rendering — parse agent text output as markdown
5. Session persistence — `session/load` support for resuming conversations

### Phase 4: Production (future)

1. Replace `stdio-to-ws` with a proper backend (manages agent processes, auth)
2. Move to Approach B (SDK + Vite) for type safety
3. Add `fs` and `terminal` client capabilities
4. User authentication and session sharing

---

## ACP Agent Registry

Once Glue's ACP agent is working, register it in the ACP registry so editors
auto-discover it:

```json
{
  "id": "glue",
  "name": "Glue",
  "version": "0.1.0",
  "description": "The coding agent that holds it all together",
  "repository": "https://github.com/helgesverre/glue",
  "authors": ["Helge Sverre"],
  "license": "Apache-2.0",
  "distribution": {
    "binary": {
      "darwin-aarch64": {
        "archive": "https://github.com/helgesverre/glue/releases/download/v0.1.0/glue-darwin-arm64.tar.gz",
        "cmd": "./glue",
        "args": ["--acp"]
      }
    }
  }
}
```

Submit a PR to https://github.com/nicholascelestin/acp-agent-registry.

---

## Available Libraries Reference

| Library                    | Language         | Purpose                                           | URL                                                    |
| -------------------------- | ---------------- | ------------------------------------------------- | ------------------------------------------------------ |
| `acp_dart`                 | Dart             | Agent-side ACP implementation for Glue            | https://github.com/SkrOYC/acp-dart                     |
| `@agentclientprotocol/sdk` | TypeScript       | Official SDK — client + agent, framework-agnostic | https://www.npmjs.com/package/@agentclientprotocol/sdk |
| `use-acp`                  | TypeScript/React | React hooks wrapping the SDK (WebSocket, state)   | https://github.com/marimo-team/use-acp                 |
| `stdio-to-ws`              | Node.js          | Bridges stdio subprocess ↔ WebSocket server       | https://www.npmjs.com/package/stdio-to-ws              |

---

## What's Out of Scope for v1

- Streaming HTTP transport (ACP spec draft, not finalized)
- `fs/*` client capabilities (Glue tools use `dart:io` directly)
- `terminal/*` client capabilities (Glue's BashTool runs locally)
- `session/load` (session resume)
- `session/set_mode` (agent modes)
- MCP server passthrough (editor forwards MCP configs to agent)
- Multi-user / authentication
- Code editor integration in the web UI
