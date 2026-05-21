# Plan: `glue mcp` add/remove/enable/disable + `/mcp` TUI actions

## Context

Glue can read MCP servers from `~/.glue/config.yaml` but offers no CLI or TUI surface to mutate that list. Today users hand-edit YAML to add, remove, or temporarily park a server. We want parity with Claude Code / Gemini CLI / Copilot CLI: explicit verbs for `add`, `remove`, `enable`, `disable` from the shell **and** from the running TUI's `/mcp` palette.

This is a two-phase shipment:
- **Phase 1 (this plan)** — `glue mcp add|remove|enable|disable` CLI verbs. Writes to user `config.yaml`. The next Glue session picks up changes.
- **Phase 2 (follow-up plan)** — `/mcp` panel gets action rows (enable/disable, remove) that mutate the same file *and* call existing `mcpPool.toggle(id)` so the running session sees the effect immediately.

Building the CLI first means the `McpConfigWriter` module exists by the time the TUI panel needs it — same writer, one source of truth, no duplicated YAML logic.

### Peer-tool conventions adopted

- **Verb set**: `add | remove | enable | disable | list` — same as Gemini CLI and Copilot CLI. (Claude Code uses add-only; we keep enable/disable because Glue's `McpServerSpec.enabled` field already exists and `mcpPool.connectAll()` already honors it.)
- **Transport flag**: explicit `--transport stdio|http|ws` (Claude/Gemini style) — safer than inferring from URL.
- **Stdio command grammar**: `--` separator — `glue mcp add foo --transport stdio -- node server.js --port 3000`. Matches Claude Code and Amp.
- **Env vars**: `-e KEY=value` repeatable.
- **HTTP headers**: `-H "Key: value"` repeatable (forward-compat; not used today since `McpHttpServerSpec` has no headers field — see Out of Scope).
- **Scope**: user-only for now (writes to `~/.glue/config.yaml`). Project scope is a future plan.
- **Remove + creds**: clear credentials by default, `--keep-credentials` opt-out.

## Existing pieces we reuse

| Piece | Location | Why |
|---|---|---|
| `McpServerSpec` (sealed) + `enabled` field | `packages/glue_strategies/lib/src/mcp_client/config.dart:12-75` | Already has `enabled: bool` (default true). No type changes needed. |
| `parseMcpConfig` + `_parseServer` | `packages/glue_harness/lib/src/config/mcp_config.dart:33,69` | Reuse to round-trip-validate the file after we mutate it. |
| `userConfigPath(Environment)` | `cli/lib/src/commands/config_command.dart` (exported) | Resolves `~/.glue/config.yaml` honoring `GLUE_HOME`. |
| `_safeLoadConfig()` | `cli/lib/src/commands/mcp_command.dart:415` | Existing helper — load config, surface `ConfigError` cleanly. Add commands use it for "already exists" / "unknown id" validation. |
| `clearMcpOAuthTokens()` + `CredentialStore.setFields()` | `cli/lib/src/commands/mcp_command.dart:400-408` (existing `auth logout` clears both) | Reuse for `remove --no-keep-credentials` (the default). Extract a private `_clearMcpCredentials(serverId, credentials)` helper since `auth logout` and `remove` do the same work. |
| `McpClientPool.toggle(id)` | `packages/glue_strategies/lib/src/mcp_client/pool.dart:219` | Already mutates session-scoped pool state. Phase 2 wires the TUI to call this *after* the writer persists. |

## What's new

### 1. New dependency: `yaml_edit`

Add `yaml_edit: ^2.2.1` to:
- `cli/pubspec.yaml` (used by the new CLI subcommands and slash command in Phase 2)
- `packages/glue_harness/pubspec.yaml` (used by the new writer module so it can live below the CLI surface)

Official Dart package; preserves comments, whitespace, and key order in `config.yaml`.

### 2. New module: `McpConfigWriter`

**Path**: `packages/glue_harness/lib/src/config/mcp_config_writer.dart` (export from `glue_harness.dart` barrel)

Surface:

```dart
class McpConfigWriter {
  McpConfigWriter(this.configPath);
  final String configPath;

  /// Adds a server entry under `mcp.servers.<id>`. Creates `mcp:` and
  /// `mcp.servers:` blocks if missing. Throws [McpConfigWriteError] if
  /// the id already exists and [overwrite] is false.
  void addServer(McpServerSpec spec, {bool overwrite = false});

  /// Removes `mcp.servers.<id>`. Throws if id not present.
  void removeServer(String id);

  /// Sets `mcp.servers.<id>.enabled`. Throws if id not present.
  void setEnabled(String id, bool enabled);

  /// Returns true if `mcp.servers.<id>` exists in the YAML.
  bool hasServer(String id);
}

class McpConfigWriteError implements Exception {
  McpConfigWriteError(this.message);
  final String message;
}
```

**Atomic write**: same pattern as `CatalogRefreshService` — write to `$configPath.tmp`, `rename` over `configPath`. No half-truncated config on crash.

**Bootstrapping an empty file**: if `configPath` doesn't exist, write `buildConfigTemplate()` first (reusing `config_template.dart`), then mutate. Mirrors `glue config init`.

**Validation safeguard**: after every mutation, re-parse the file via `parseMcpConfig` to confirm the result still loads. If it doesn't, restore the pre-write content from a local backup and throw `McpConfigWriteError`. Catches `yaml_edit` API misuse before it corrupts a user's file.

### 3. New CLI subcommands in `mcp_command.dart`

All four added to `McpCommand`'s `addSubcommand(...)` list at line 28-33.

#### `glue mcp add <id> [options]`

```
glue mcp add <id> --transport stdio [-e K=V]... [--cwd <dir>] [--timeout <s>] [--disabled] [--force] -- <cmd> [args...]
glue mcp add <id> --transport http  --url <url> [--auth none|bearer|oauth] [-H "K: V"]... [--timeout <s>] [--disabled] [--force]
glue mcp add <id> --transport ws    --url <url> [--auth none|bearer|oauth] [--timeout <s>] [--disabled] [--force]
```

- Validates `id` matches `^[a-z0-9][a-z0-9_-]*$` (tool namespacing requires it).
- For `stdio`: everything after `--` is `command` + `args`. Empty rest → error.
- For `http`/`ws`: `--url` required; parsed via `Uri.parse`. Scheme must match transport.
- Mutually-exclusive flag groups enforced (e.g., `-e` rejected when `--transport http`).
- `--auth bearer|oauth` only sets the spec kind; user runs `glue mcp auth set <id> --bearer` (already exists) or `glue mcp auth login <id>` (already exists) afterward.
- On success, prints `Added <transport> server '<id>'. Run 'glue' to load it.` (or `(disabled — enable with 'glue mcp enable <id>')` when `--disabled`).

#### `glue mcp remove <id> [--keep-credentials]`

- Verifies `id` exists via `McpConfigWriter.hasServer`.
- Removes the YAML entry.
- Unless `--keep-credentials`: clears bearer and OAuth fields under `mcp:<id>` (extract helper `_clearMcpCredentials` shared with `auth logout`).
- Prints `Removed server '<id>'.` (+ `Credentials cleared.` line when applicable).

#### `glue mcp enable <id>` / `glue mcp disable <id>`

- Both call `McpConfigWriter.setEnabled(id, true|false)`.
- Idempotent: re-enabling an already-enabled server prints a no-op message and exits 0.
- Output: `Enabled '<id>'. Will connect on next session start.` / `Disabled '<id>'.`

### 4. Tests

**New**: `cli/test/commands/mcp_command_test.dart` and `packages/glue_harness/test/config/mcp_config_writer_test.dart`

`McpConfigWriter` tests (the meat of the coverage):
- Add stdio server to an empty file → file parses, contains the spec.
- Add to a heavily commented file → comments and key order preserved (golden compare).
- Add duplicate id without `--force` → throws.
- `setEnabled` on unknown id → throws.
- `removeServer` on the only server → leaves `mcp.servers: {}` (not a dangling `mcp:` block).
- Atomic write: simulate a write failure mid-mutation by injecting a fake filesystem error → original file intact.
- Round-trip validation: after a mutation, the file re-parses cleanly via `parseMcpConfig`.

CLI tests (lighter — exercise the arg parser, delegating writer behavior to the writer tests):
- `add` rejects unknown transport.
- `add --transport stdio` without `--` rest → usage error.
- `add` with bad id → validation error.
- `remove` non-existent id → exit 1 with helpful message.
- `enable`/`disable` round trip via a scratch `GLUE_HOME`.

Pattern: same scratch-temp approach as `cli/test/commands/config_command_test.dart` — `Environment.test(home: tempDir.path)` to redirect `~/.glue`.

### 5. Documentation touch-ups (light)

- `website/docs/cli/mcp.md` (or wherever `glue mcp` is documented) — add the new verbs.
- Mention in `cli help mcp` text via the standard `Command.description` strings.

## Files to create / modify

```
+ packages/glue_harness/lib/src/config/mcp_config_writer.dart    (new module)
+ packages/glue_harness/test/config/mcp_config_writer_test.dart  (new tests)
+ cli/test/commands/mcp_command_test.dart                        (new tests)
M packages/glue_harness/lib/glue_harness.dart                    (export McpConfigWriter)
M packages/glue_harness/pubspec.yaml                             (+ yaml_edit)
M cli/pubspec.yaml                                               (+ yaml_edit)
M cli/lib/src/commands/mcp_command.dart                          (+ add/remove/enable/disable, extract _clearMcpCredentials)
M website/docs/cli/mcp.md                                        (doc the new verbs)
```

No changes needed to:
- `McpServerSpec` / `McpConfig` types — `enabled` already exists.
- `parseMcpConfig` — already handles all the fields we write.
- `McpClientPool` — Phase 2 reuses its existing `toggle()` method.

## Verification

End-to-end run from the repo root after `dart pub get`:

```sh
# 1. Add a stdio server
dart run cli/bin/glue.dart mcp add demo --transport stdio -- echo hello
dart run cli/bin/glue.dart mcp list   # expect 'demo  stdio  enabled'
grep -A3 'demo:' ~/.glue/config.yaml  # YAML inspected by hand

# 2. Disable / enable
dart run cli/bin/glue.dart mcp disable demo
dart run cli/bin/glue.dart mcp list   # expect 'demo  stdio  disabled'
dart run cli/bin/glue.dart mcp enable demo

# 3. Add HTTP with auth, then login (existing flow)
dart run cli/bin/glue.dart mcp add gh --transport http --url https://example.com/mcp --auth bearer
# auth set is the existing path — proves remove clears creds:
echo 'sekret' | dart run cli/bin/glue.dart mcp auth set gh --bearer
dart run cli/bin/glue.dart mcp remove gh
dart run cli/bin/glue.dart mcp auth status   # gh absent

# 4. Comment preservation
# Before/after diff of ~/.glue/config.yaml across the operations above
# should leave every pre-existing comment line untouched.

# 5. Quality gate
just cli::check
```

Plus `just check` (full quality gate: format + analyze + tests across the monorepo).

## Out of scope (call out for Phase 2 or later)

- **`/mcp` TUI panel actions** — the action-row buttons (enable/disable/remove) that wire this same writer to the running session. Tracked as Phase 2 of this work; the writer is built CLI-first so the TUI can reuse it without refactoring.
- **`McpHttpServerSpec.requestHeaders`** — the parser already supports `request_headers:` in YAML, but the typed spec doesn't expose them yet. Forwarding `-H` through `add` requires a small type addition. Defer to a separate change unless it blocks a real user.
- **Project-scope config** (`./.glue/config.yaml`) — Glue has no project config loader today. A separate plan.
- **`glue mcp rename`** / **`glue mcp edit`** — not requested. Users can `remove` + `add`.
- **Auto-reload of a running TUI when the CLI mutates config** — would need a file watcher; out of scope. Mutations take effect on next session start.

## Risks

1. **`yaml_edit` formatting drift** — the package preserves comments but can re-indent in edge cases. The round-trip validation + golden tests on a commented config guard against silent corruption.
2. **Concurrent writes** — two `glue mcp` processes mutating the same file at once would race. Atomic rename gives last-write-wins (no torn files) but not transactional. Acceptable since this is an interactive command, not a server.
3. **Credential helper extraction** — pulling shared `_clearMcpCredentials` from `auth logout` could regress that path. The existing tests for `auth logout` (if any) cover it; otherwise add one.
