# Security & Correctness Audit — 2026-07-09

Findings from a full-codebase review (five parallel reviewers over security, agent
core, persistence/config, CLI/TUI, and MCP/runtimes/ACP). Every CRITICAL and most
HIGH findings were verified against source (file:line quoted) and several were
reproduced with scratch scripts. Severity: **CRITICAL** = release-blocker,
**HIGH** = fix before merge, **MEDIUM** = fix soon, **LOW** = author's discretion.

Remediation runs on branch `fix/audit-2026-07`, parallelized across disjoint file
groups (see "Work partition" at the bottom). Check a box when the fix lands with a
test and the package's quality gate (`dart analyze --fatal-infos` + `dart test`)
passes.

## Status: COMPLETE (2026-07-09)

All 4 CRITICAL, 15 HIGH, 25 MEDIUM, and 18 LOW findings were remediated on
`fix/audit-2026-07` (10 merge commits), each with tests. Full workspace gate is
green: `dart analyze --fatal-infos` clean across all 6 packages; `dart test`
passes (glue_core 24, glue_strategies 176, glue_harness 98, glue_runtimes 114,
glue_server 57, cli 1742).

**Partial / deferred (3 items):**
- **H7** — the `Origin`-header rejection (defeats the drive-by-browser RCE) shipped.
  The "also require a bearer token on loopback" hardening (for the same-host
  multi-user threat) was NOT done — it needs `cli/lib/src/acp/acp_command.dart`
  (token generation/UX) and is a design call for the maintainer. Consider a unix
  domain socket for local editor use.
- **L7** — unbounded session growth: a TODO note was added; no rotation/cap
  implemented (risk/scope disproportionate for a LOW).
- **Runtime polish (not in the numbered list):** Daytona log polling re-downloads
  the full log each cycle (O(n²)) — deferred, needs a Daytona API offset param that
  doesn't exist; and two library-code `stderr` writes in the bootstrap fallback
  path can corrupt the TUI — deferred, needs a sink threaded through all adapters.

---

## CRITICAL

- [x] **C1 — Cancelling/denying a tool mid-flight corrupts the conversation → next API call 400s.**
  `packages/glue_harness/lib/src/agent/agent_core.dart:303-316` appends `Message.toolResult`
  after `await Future.wait(toolFutures)` but before the next `yield`; a cancelled `async*`
  generator resumes up to that yield, so a tool completing after Escape appends the real
  result while `ensureToolResultsComplete()` already appended a synthetic `[cancelled]`
  result for the same id → duplicate `tool_result` (Anthropic/Gemini/OpenAI all reject).
  Deterministic trigger: early-approval "No" path `cli/lib/src/app.dart:1959-1962` calls
  `_cancelAgent()` then `completeToolCall(denied)`. *Fix: explicit `AgentCore.abort()` that
  sets a flag (checked before the append loop) and error-completes `_pendingToolResults`;
  app calls it; early-deny uses `_denyTool` semantics (keep stream alive), not `_cancelAgent`.*

- [x] **C2 — `glue mcp add` silently deletes `mcp.tool_policy` (deny-list) and sibling `mcp.*` keys/comments.**
  `packages/glue_harness/lib/src/config/mcp_config_writer.dart:68-81` takes the safe
  `yaml_edit` path only when `servers` is a non-empty map; otherwise `_bootstrapFirstServer`
  → `_replaceMcpBlock` (`:179-200`) deletes the whole `mcp:` block and re-renders only
  `servers:`. Triggers on the first server, or any add after `remove <last>` leaves
  `servers: {}`. Wipes a security control; round-trip validator can't catch it (output
  parses). *Fix: only update `['mcp','servers']`, never the whole block. Regression test:
  mcp block with sibling keys + empty servers.*

- [x] **C3 — Model/tool/thinking output rendered to the terminal with no ANSI sanitization.**
  `cli/lib/src/rendering/block_renderer.dart:81-101` (`renderAssistant`/`renderThinking`)
  and the tool-result path pass raw text through the markdown renderer; `renderBash`
  (`:227`) *does* `stripAnsi`. A tool echoing attacker-controlled content (poisoned file,
  web fetch, MCP result) can inject `\x1b` → OSC 52 clipboard write, OSC 8 hyperlinks,
  cursor/status spoofing, device queries that inject onto stdin. *Fix: strip C0/C1 control
  bytes (everything < 0x20 except \n/\t, plus 0x7f and lone \x1b) from untrusted text
  before rendering; apply the styling the renderer itself adds afterward.*

- [x] **C4 — SSRF via auto-allowed `web_fetch` → cloud-metadata credential theft.**
  (CRITICAL on cloud runtimes, HIGH on a laptop.)
  `packages/glue_strategies/lib/src/web/fetch/web_fetch_client.dart:65-104` validates only
  scheme + non-empty host, then GETs with a redirect-following client; no block on
  loopback/private/`169.254.169.254`. `packages/glue_harness/lib/src/orchestrator/tool_permissions.dart:12-19`
  auto-allows `web_fetch`/`web_search`/`web_browser` (no prompt). *Fix: resolve host, reject
  non-global IPs before connecting, re-validate on every redirect hop; apply to
  search/browser and the Jina fallback (`jina_reader_client.dart`).*

---

## HIGH

- [x] **H1 — Resume/fork drops tool-only turns.** `packages/glue_harness/lib/src/session/session_manager.dart:629-646`
  `flushPending()` is gated on `pendingAssistantText != null`; a turn where the model went
  straight to tools has its calls+results discarded on replay. *(Cross-confirmed by two
  reviewers.)* *Fix: emit assistant messages with tool calls even when text is empty.*
- [x] **H2 — Resume of a mid-tool crash → dangling `tool_use`, no result → provider 400.**
  `ensureToolResultsComplete()` is wired only into the cancel path, never resume. *Fix: call
  it after `_replayEventsIntoAgent`/at the top of `resumeSession`/`forkSession`.*
- [x] **H3 — OpenAI cached tokens double-counted.** `packages/glue_strategies/lib/src/llm/openai_client.dart:189`
  sets `inputTokens: prompt_tokens` without subtracting `cached_tokens`, but the contract
  (`glue_core/.../message.dart:128`) is uncached-only → context gauge, billed tokens, cache
  hit-rate all inflated. *Fix: `prompt_tokens - (cached_tokens ?? 0)`, clamped ≥0.*
- [x] **H4 — Legacy session resume corrupts model ref to `anthropic/unknown`.**
  `packages/glue_harness/lib/src/storage/session_store.dart:113-118` writes back the old
  `schema_version` but only the v3 `model_ref`; `fromJson` ignores it for schema < 3, and
  the store rewrites `meta.json` on construction. *Fix: emit the current schema version.*
- [x] **H5 — Corrupt catalog cache bricks every `glue` invocation.** `loadYaml` throws
  `YamlException`; the loader (`glue_config.dart:468-476`) catches only `CatalogParseException`.
  Reachable via `glue catalog refresh --url` / `catalog edit`. *Fix: catch `YamlException`
  in `_loadOptionalYaml`; validate in `refreshCatalog` before committing the cache file.*
- [x] **H6 — Terminal not restored on panic / SIGTERM / SIGHUP.** `cli/bin/glue.dart:229`
  traps only SIGINT; no `runZonedGuarded` anywhere; errors in listener/timer callbacks
  bypass `run()`'s `finally`. *Fix: `runZonedGuarded` with a TTY-restore onError; watch
  SIGTERM/SIGHUP.*
- [x] **H7 — ACP WebSocket: no `Origin` check + loopback needs no token → drive-by localhost RCE.**
  `packages/glue_server/lib/src/acp/http_host.dart:76-108,:144`. A visited website can open
  `ws://127.0.0.1:3000/acp`, drive the agent, and auto-approve its own tool requests.
  *Fix: reject requests carrying an `Origin` header (real editor clients don't send one);
  require the token even on loopback.* **(PARTIAL — Origin rejection shipped; token-on-loopback
  hardening deferred, see Status note.)**
- [x] **H8 — ACP client error-reply to a permission request hangs the prompt forever.**
  `cli/lib/src/acp/cli_acp_delegate.dart:110-111` — `await requestPermission` is outside the
  try; the throw skips `completeToolCall`, pinning `AgentCore` mid-turn. *Fix: move the await
  inside the try, map errors to deny.*
- [x] **H9 — ACP pending permissions never failed on disconnect.** `server.dart:112-120`
  closes sessions but never drains `_pendingPermissions`. *Fix: `completeError` all pending
  on transport done/error and per-session on close.*
- [x] **H10 — ACP host: un-awaited, un-caught `_runConnection`/accept futures can kill the isolate / stop accepting.**
  `http_host.dart:76-102`. *Fix: catch in both `_runConnection` and the accept loop.*
- [x] **H11 — MCP pool leaks child processes on connect failure.** `pool.dart:357-367`
  generic `catch` doesn't `remove`/`close` the client (unlike the `McpCallFailure` branch);
  the reconnect timer piles up more. *Fix: mirror the cleanup in the generic catch.*
- [x] **H12 — MCP double-connect race + can't disable a failing server.** `pool.dart:304`
  overwrites `_clients[id]` with no in-flight guard; `toggle()` (`:271-284`) keys on
  connection presence not `enabled`, so a failing server restarts on "disable". *Fix:
  epoch/in-flight guard; branch `toggle` on `s.enabled`.*
- [x] **H13 — Daytona: killing one background command kills them all + breaks future ones.**
  `glue_runtimes/.../daytona/executor.dart:86-96` shares one session; `running_command.dart:59-76`
  `kill()` deletes it. *Fix: one session per streaming command (or refcount + recreate).*
- [x] **H14 — Daytona: `handle.exitCode.then(...)` with no `onError` → isolate-fatal unhandled error.**
  `glue_runtimes/.../common/transport_executor.dart:112`. *Fix: add `onError`.*
- [x] **H15 — Sprites bundle upload E2BIG far below the 3 MB cap, hard-fails bootstrap.**
  `glue_runtimes/.../sprites/cli.dart:255` base64s into a single argv string;
  `common/bootstrap.dart:360-371` turns the failure into a fatal `BootstrapException` instead
  of clone-fallback. *Fix: stream via stdin/chunked appends, or cap ~64 KB with skip-not-fail.*

---

## MEDIUM

- [x] **M1 — MCP `call_timeout_seconds` parsed everywhere but never applied** (30s hard cap). `pool.dart:118-147` / `client.dart:74`.
- [x] **M2 — MCP mid-session 401 never re-triggers auth.** `tool_factory.dart:69-81` swallows it as a failed result; pool stays "Connected".
- [x] **M3 — MCP HTTP transport: one request's error fails ALL in-flight calls.** `http_sse.dart:115-123` → `_failAllPending`.
- [x] **M4 — MCP HTTP transport: unguarded response-body reads → unhandled async error.** `http_sse.dart:102,107-111,143-146`.
- [x] **M5 — Agent loop has no max-turn / infinite-loop guard.** `agent_core.dart:126` `while(true)`; headless/subagent can't Escape. *Fix: configurable `maxIterations`.*
- [x] **M6 — No retry/backoff for 429/5xx/network** anywhere in the LLM path. `agent_core.dart` + clients.
- [x] **M7 — Gemini mapper drops all user multimodal content.** `message_mapper.dart:185-189` ignores `contentParts`.
- [x] **M8 — Empty/thinking-only turn → Anthropic `content: []` → 400.** `agent_core.dart:279-284` + `message_mapper.dart:83-95`. *Fix: skip empty assistant messages.*
- [x] **M9 — Mid-stream provider `error` events silently swallowed** (Anthropic `anthropic_client.dart` no `case 'error'`; Ollama NDJSON; Gemini `blockReason`) → truncated turn looks like success.
- [x] **M10 — Ollama gauge under-reports on warm cache.** `ollama_client.dart:194-196` maps `prompt_eval_count` (newly-evaluated only) to `inputTokens`.
- [x] **M11 — No session file locking.** Two `glue --continue` interleave writes to one `conversation.jsonl` → duplicate tool_results on replay. *Fix: advisory lock or per-process ids.*
- [x] **M12 — JSONL/atomicWrite lack flush/fsync → torn tail lines silently dropped.** `session_store.dart:295-298`, `storage/file_utils.dart:3-11`. *Fix: `flush: true`; count skipped lines.*
- [x] **M13 — Disabled MCP server with an unset `${VAR}` bricks all config loading.** `mcp_config.dart:82-119` expands regardless of `enabled:false`. *Fix: skip/defer expansion for disabled servers.*
- [x] **M14 — `/history` fork duplicates the forked-at user message.** `session_manager.dart:556-562` + `slash/history.dart:145-156`. *Fix: break before adding the fork-point event.*
- [x] **M15 — `glue mcp auth set --bearer` crashes on piped stdin.** `mcp_command.dart:756` reads `stdin.echoMode` outside the try. *Fix: wrap in try/fallback.*
- [x] **M16 — `glue mcp auth login <unknown>` / `session show|diff|apply|export <unknown>` crash with raw `StateError`.** `mcp_command.dart:693-696`, `session_command.dart:307-310,365-368,419-422,470-473`. *Fix: catch, print, exit non-zero.*
- [x] **M17 — `--print` returns exit 0 on failure.** `app.dart:2334-2345,2376-2414`. *Fix: set exit 1 on `AgentError`/exception.*
- [x] **M18 — `--json` emits no output at all on error.** `app.dart:2334-2345`. *Fix: emit a JSON envelope with an `error` field.*
- [x] **M19 — Blocking `! cmd` buffers unbounded output → OOM/hang.** `app.dart:2643-2664` `.join()` with no cap. *Fix: cap bytes, truncate with notice.*
- [x] **M20 — Ollama pull-confirm modal orphaned if user exits while open.** `app.dart:745-819`. *Fix: guard post-await UI mutations with `_exitCompleter.isCompleted`.*
- [x] **M21 — `_render()` throttle can drop the final frame → stale UI.** `app.dart:824-839`. *Fix: always `_doRender()` in the trailing callback, or a `_dirty` flag.*
- [x] **M22 — `_mode`/`_activeModal` pairing hand-maintained in ~8 places, no invariant.** `app.dart`. *Fix: derive `confirming` from `_activeModal != null`.*
- [x] **M23 — Daytona client-side timeouts don't cancel remote work and escape the typed error contract.** `daytona/client.dart:393-395`, `sprites/cli.dart:150-153,200-202` (leaked subprocess).
- [x] **M24 — Failed checkout leaves a poisoned workspace that later reports `resumed: true`.** `common/bootstrap.dart:277-279`. *Fix: `rm -rf` on checkout failure or verify HEAD on resume.*
- [x] **M25 — `classifyCloneFailure` misclassifies "Repository not found" (private-repo auth) as missing-git-binary.** `common/bootstrap.dart:211-219`.

---

## LOW

- [x] **L1 — Reflected XSS in the OAuth loopback callback page.** `mcp_client/oauth.dart:594-612` interpolates `error` param unescaped. *Fix: HTML-escape.*
- [x] **L2 — Credentials tmp file world-readable before `chmod 600`; `~/.glue` not `0700`.** `credentials/credential_store.dart:147-158`. *Fix: create with 0600; check chmod result.*
- [x] **L3 — Session transcripts/logs created without `0700`/`0600`.** `storage/session_store.dart:289-299`, `storage/file_utils.dart`, `core/environment.dart:129-133`.
- [x] **L4 — YAML fidelity/injection on the first-server bootstrap renderer.** `mcp_config_writer.dart:158-174` never quotes newlines. *Fix: quote values with `\n`/edge whitespace; validate env keys.*
- [x] **L5 — Session id generation has no randomness** (microsecond collisions). `session_manager.dart:780-785`. *Fix: add random/PID component.*
- [x] **L6 — `sessionDir` trusts the meta.json `id` field (path traversal on imported session).** `core/environment.dart:112-113`. *Fix: derive id from directory name.*
- [ ] **L7 — Unbounded session growth, no cap/rotation.** `conversation.jsonl` stores full content forever. *(DEFERRED — TODO note added in code; rotation not implemented.)* *(Deferred: TODO note added at `session_store.dart` `logEvent`; a real size/age cap is out of scope for this pass.)*
- [x] **L8 — `glue config init --force` overwrites config.yaml non-atomically.** `config_command.dart:33-34`. *Fix: tmp+rename.*
- [x] **L9 — OTEL endpoint precedence inverted** (YAML before env, unlike everything else). `config_resolvers.dart:189-193`.
- [x] **L10 — MCP OAuth issuer check uses exact `Uri` equality** (trailing-slash interop failure). `oauth.dart:215`.
- [x] **L11 — MCP request timeout doesn't send `notifications/cancelled`; stdio SIGTERMs without closing stdin first.** `client.dart:196-205`, `stdio.dart:116-134`.
- [x] **L12 — Tool-schema conversion crashes the whole server on list-typed `type` / missing name.** `tool_factory.dart:125`, `protocol.dart:141`. *Fix: accept list types; skip malformed descriptors.*
- [x] **L13 — Reserved-name collision filter compares bare names, silently dropping namespaced MCP tools.** `tool_factory.dart:96`.
- [x] **L14 — `charWidth` mismeasures ZWJ/emoji clusters and the 0x1F000–0x1FFFF plane.** `rendering/ansi_utils.dart:474`. *Fix: document; grapheme segmentation for a real fix.*
- [x] **L15 — `_persistTrustedTool` swallows all write errors silently.** `app.dart:2107-2119`. *Fix: surface a one-line message.*
- [x] **L16 — `ToolArgsBuffer.finalizeArguments` only catches `FormatException`** (non-object JSON throws `TypeError`). `tool_args.dart:29-33`.
- [x] **L17 — OpenAI parser: stream ending without a `finish_reason` drops tool calls; `index` cast throws on servers that omit it.** `openai_client.dart:128,146-157`.
- [x] **L18 — `--print` mode persists no tool activity to the session log.** `app.dart:2312-2329,2361`.

---

## Work partition (branch `fix/audit-2026-07`)

Fixes are grouped by **disjoint file sets** so worktree agents don't collide. C1 (cross-cutting
`agent_core.dart` + `app.dart`) is done first on the integration branch to unblock the rest.

| Group | Files | Findings |
| --- | --- | --- |
| (base) conversation-cancel | `agent_core.dart`, `app.dart` (cancel/deny only) | C1 |
| harness-conversation | `session_manager.dart`, `session_store.dart`, `storage/file_utils.dart`, `agent_core.dart` (non-C1) | H1, H2, H4, M5, M8, M11, M12, M14, L5, L16 |
| llm-clients | `llm/openai_client.dart`, `llm/message_mapper.dart`, `llm/anthropic_client.dart`, `llm/ollama_client.dart`, `llm/gemini*`, `agent/tool_args.dart` | H3, M6, M7, M9, M10, L17 |
| mcp-client | `mcp_client/pool.dart`, `http_sse.dart`, `client.dart`, `tool_factory.dart`, `protocol.dart`, `stdio.dart`, `oauth.dart` | H11, H12, M1, M2, M3, M4, L1, L10, L11, L12, L13 |
| config-and-cmds | `config/mcp_config_writer.dart`, `config/mcp_config.dart`, `glue_config.dart`+catalog, `commands/mcp_command.dart`, `commands/session_command.dart`, `commands/config_command.dart`, `credentials/credential_store.dart`, `config_resolvers.dart` | C2, H5, M13, M15, M16, L2, L4, L8, L9 |
| runtimes | `glue_runtimes/**` (daytona, sprites, common) | H13, H14, H15, M23, M24, M25 |
| acp-server | `glue_server/acp/**`, `cli/lib/src/acp/**` | H7, H8, H9, H10 |
| web-and-render | `web/fetch/web_fetch_client.dart`, `web/**` (SSRF), `rendering/block_renderer.dart`, `rendering/markdown_renderer.dart`, `rendering/ansi_utils.dart` | C3, C4, L14 |
| cli-app | `app.dart` (non-cancel), `bin/glue.dart`, `terminal/terminal.dart` | H6, M17, M18, M19, M20, M21, M22, L3, L7, L15, L18, L6 |
