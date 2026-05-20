# `glue://` URL Scheme Handler — Research + Plan

**Status:** 📋 Research / Design — not yet approved for implementation
**Date:** 2026-05-20
**Owner:** Helge
**Goal:** Allow MCP registries and documentation sites to embed one-click "Add to Glue" buttons that hand off to the Glue CLI, like VS Code's `vscode:mcp/install` and Cursor's `cursor://...cursor-deeplink/mcp/install`.

This document is **research + spec + roadmap**. No code is to be written yet — get sign-off on the URL grammar and platform strategy first, then split implementation into the bundles below.

---

## 1. Why this is worth doing

MCP registries currently emit per-client install buttons. The dominant patterns:

| Client | Scheme | Grammar | Config encoding |
|---|---|---|---|
| VS Code | `vscode:` | `vscode:mcp/install?name=<id>&config=<json>` | URL-encoded JSON |
| Cursor | `cursor:` | `cursor://anysphere.cursor-deeplink/mcp/install?name=<id>&config=<b64>` | Base64-encoded JSON |
| Windsurf | `windsurf:` | `windsurf://windsurf-mcp-registry?serverName=<id>` | None — registry lookup only |
| Smithery (multi-target) | per target | Generates target-specific deeplinks | per target |

Without a `glue://` handler, the [MCP registry](https://registry.modelcontextprotocol.io) and third-party catalogs (Smithery, mcp.so, registry.npmjs.org, GitHub READMEs) cannot offer an "Add to Glue" button. Users have to read JSON, run `glue mcp add ...` by hand, and hope they got the transport flags right.

There is a **secondary** benefit: the same scheme can carry session-resume URLs, share links for prompts, and similar deep-linking — but MCP install is the only obviously-justified use case today. Everything else stays out of v1.

---

## 2. Ecosystem conventions — what to copy, what to ignore

### 2.1 Config-inline pattern (VS Code, Cursor, Smithery)

The URL carries the full server config inline. The client decodes, validates, prompts, and writes.

- **Pro:** Self-contained — no registry dependency, works for private/unlisted servers.
- **Con:** URLs grow long. The `command`/`args` fields can carry shell-executable strings, which is a real security surface. See [CursorJack](https://www.proofpoint.com/us/blog/threat-insight/cursorjack-weaponizing-deeplinks-exploit-cursor-ide) and [GHSA-r22h-5wp2-2wfv](https://github.com/cursor/cursor/security/advisories/GHSA-r22h-5wp2-2wfv): one-click MCP install via a malicious deeplink can persist arbitrary code execution.

### 2.2 Registry-lookup pattern (Windsurf)

The URL carries only a canonical name (e.g. `serverName=github-mcp-server`). The client fetches the config from a trusted registry.

- **Pro:** Short URLs. Config is audited and signed by the registry. Easier to inspect.
- **Con:** Requires a registry to exist and be reachable. Cannot install arbitrary/unlisted servers. Locked to one registry per scheme.

### 2.3 The user's `vscode:mcp/by-name/io.github.upstash/context7` example

Worth flagging directly: I could not find an official `vscode:mcp/by-name/` path in VS Code's [MCP developer guide](https://code.visualstudio.com/api/extension-guides/ai/mcp) or [MCP configuration reference](https://code.visualstudio.com/docs/copilot/reference/mcp-configuration). The official VS Code shape is `vscode:mcp/install?name=<id>&config=<json>` — i.e. config-inline only.

The `by-name` *concept* is real though: the [MCP registry](https://github.com/modelcontextprotocol/registry) uses reverse-DNS canonical IDs like `io.github.upstash/context7`, with two authentication-determined namespaces:

- `io.github.<user-or-org>/<server>` — proven by GitHub OAuth.
- `<reverse-dns-domain>/<server>` — proven by DNS TXT or HTTP challenge.

If a "by-name" deeplink form does exist in VS Code, it's undocumented and we shouldn't bet on it. But we *should* support the registry-lookup pattern in Glue because it solves the security problem cleanly: a curated registry is a much better trust boundary than a raw URL.

### 2.4 Decision

**Support both.** Two routes under `glue://mcp/`:

- `glue://mcp/install?...` — config-inline, parity with VS Code/Cursor so registries can target us.
- `glue://mcp/by-name/<canonical-id>` — registry-lookup against `registry.modelcontextprotocol.io`, the safer default.

---

## 3. Feasibility per platform

A `glue://` handler requires the OS to launch `glue` (or a shim) with the URL when the user clicks a link. Glue is a CLI binary, not a GUI app — this complicates registration on macOS.

### 3.1 macOS — **shim required**

macOS Launch Services only routes URL schemes to bundles with a `CFBundleURLTypes` entry in `Info.plist`. A bare CLI binary cannot register a scheme. References: [LSRegisterURL docs](https://developer.apple.com/documentation/coreservices/1446350-lsregisterurl), [jw bargsten's writeup](https://bargsten.org/wissen/custom-protocol-handler-macos/).

**Approach:** Ship a minimal `Glue URL Handler.app` bundle:

```
Glue URL Handler.app/
  Contents/
    Info.plist             # declares scheme `glue` under CFBundleURLTypes
    MacOS/
      handler              # tiny shell stub: exec /path/to/glue handle-url "$@"
```

`Info.plist` registers `glue` as the only handled scheme. The launcher stub `exec`s the real `glue` binary (path resolved at install time). Install registers the bundle with Launch Services via `lsregister -f`.

**Open question:** the stub runs detached from any terminal. For v1 the handler is **non-interactive** — it parses, writes config, posts a system notification ("Added MCP server `foo` to Glue. Run `glue` to load it."). We do **not** try to spawn a Terminal window. This matches Windsurf's UX (the URL just queues the config) and sidesteps the "which terminal emulator?" problem entirely.

### 3.2 Linux — **`.desktop` file**

Native support via XDG. Reference: [Arch Wiki XDG MIME Applications](https://wiki.archlinux.org/title/XDG_MIME_Applications).

```ini
# ~/.local/share/applications/glue-url-handler.desktop
[Desktop Entry]
Type=Application
Name=Glue URL Handler
Exec=/usr/local/bin/glue handle-url %u
NoDisplay=true
MimeType=x-scheme-handler/glue;
```

Then `update-desktop-database ~/.local/share/applications/` and `xdg-mime default glue-url-handler.desktop x-scheme-handler/glue`.

### 3.3 Windows — **registry entries**

Standard pattern under `HKEY_CLASSES_ROOT\glue`:

```
HKCU\Software\Classes\glue\(Default) = "URL:Glue Protocol"
HKCU\Software\Classes\glue\URL Protocol = ""
HKCU\Software\Classes\glue\shell\open\command\(Default) = "\"C:\\Program Files\\Glue\\glue.exe\" handle-url \"%1\""
```

Per-user under `HKCU` to avoid needing admin. v1 may defer Windows support if the maintenance cost outweighs demand — flag this for sign-off.

### 3.4 Summary

| Platform | Mechanism | Effort | v1? |
|---|---|---|---|
| macOS | Bundled `.app` shim, registered via `lsregister` | High (need shim, codesign) | Yes |
| Linux | `.desktop` file + `xdg-mime` | Low | Yes |
| Windows | Registry write under `HKCU` | Medium | Defer — gate on demand |

---

## 4. Proposed `glue://` URL grammar

### 4.1 Top-level shape

```
glue://<authority>/<path>?<query>
```

`<authority>` is the namespace (`mcp`, future: `session`, `config`). `<path>` is the verb + identifiers. Query is the payload.

This mirrors VS Code's `vscode:mcp/install` (authority+path = `mcp/install`), so the mental model transfers.

### 4.2 v1 routes (MCP only)

#### `glue://mcp/install?name=<id>&config=<encoded-json>`

**Parameters:**
- `name` — server id, must match `^[a-z0-9][a-z0-9_-]*$` (same regex `McpAddCommand` already enforces at `cli/lib/src/commands/mcp_command.dart:53`).
- `config` — server config, JSON. Two encodings accepted:
  - **URL-encoded JSON** (matches VS Code): detected if the first decoded character is `{`.
  - **Base64-encoded JSON** (matches Cursor): detected if the value matches `^[A-Za-z0-9+/=_-]+$` and base64-decodes to valid JSON starting with `{`.
- Optional: `source=<url>` — registry URL the config came from, surfaced in the confirmation prompt for auditability.

**`config` schema** (mirrors VS Code's mcp.json + Cursor's mcp config):

```jsonc
// stdio
{ "type": "stdio", "command": "node", "args": ["server.js"], "env": {"K": "v"}, "cwd": "..." }
// http (with bearer or oauth)
{ "type": "http", "url": "https://api.example.com/mcp", "auth": "bearer" | "oauth" | "none", "headers": {...} }
// websocket
{ "type": "ws", "url": "wss://...", "auth": "bearer" | "oauth" | "none" }
```

Field rules — explicit reuse of existing types from `packages/glue_harness/lib/src/config/mcp_config.dart`:

| URL `config` field | Maps to | Notes |
|---|---|---|
| `type: "stdio"` | `McpStdioServerSpec` | `command` + `args` required |
| `type: "http"` | `McpHttpServerSpec` | `url` required, scheme must be `http`/`https` |
| `type: "ws"` | `McpWebSocketServerSpec` | `url` required, scheme must be `ws`/`wss` |
| `auth: "bearer"` | `McpBearerAuth()` | Token NOT carried in URL — user runs `glue mcp auth set <id> --bearer` after install |
| `auth: "oauth"` | `McpOAuthAuth()` | User runs `glue mcp auth login <id>` |
| `env` | `McpStdioServerSpec.env` | Values containing `${input:foo}` are rejected for v1 (no input-prompting in handler) |
| `headers` | (not yet supported) | Accepted but ignored in v1 with a warning |

Unknown fields are rejected (strict). Pattern-substitution placeholders like VS Code's `${input:api-key}` are explicitly **not** supported in v1 — the handler is non-interactive, and silently dropping them would surprise users.

#### `glue://mcp/by-name/<canonical-id>`

**Path:** `<canonical-id>` follows the MCP registry reverse-DNS form, e.g. `io.github.upstash/context7`. The single `/` between namespace and name is preserved in the URL (it's a legal path character, no need to encode).

**Behaviour:** Handler resolves the ID against `https://registry.modelcontextprotocol.io/v0/servers/<canonical-id>`, picks the latest version, presents the resulting config in the same confirmation prompt as the inline form, then writes it.

**Local server-id derivation:** canonical IDs contain `.` and `/`, neither legal in Glue's `^[a-z0-9][a-z0-9_-]*$` server-id regex. The handler derives a local id by taking the last path segment (`context7`) and offering it as the default in the confirmation prompt, with the user able to override.

**Optional query params:**
- `version=<semver>` — pin to a specific registry version.
- `as=<local-id>` — override the derived local id without prompting.

### 4.3 Routes deferred past v1 (documented for grammar consistency)

- `glue://session/resume/<session-id>` — open a stored session.
- `glue://config/show` — print config paths.
- `glue://skill/install?source=<url>` — once skills support remote install.

Listing them now locks in the namespace shape so we don't paint ourselves into a corner.

### 4.4 Things we explicitly will NOT do

- **No `command` execution on install.** The handler only writes config. Tools are not invoked until the user runs `glue` or `/mcp reconnect`.
- **No silent install.** Every URL produces a confirmation prompt by default; `--yes` exists for scripts but is not the default in the OS handler path.
- **No tokens in URLs.** Bearer tokens stay out of the deeplink — the handler instructs the user to run `glue mcp auth set` afterwards.

---

## 5. Security model

The CursorJack class of attack is the explicit threat model: a malicious page hosting a `glue://mcp/install?...` link that, if blindly accepted, installs a stdio server whose `command` runs arbitrary code on next session start.

**Defences:**

1. **Confirmation prompt is mandatory in the OS-handler path.** The `handle-url` subcommand renders a structured diff of what will be written (full `command`/`args`/`env`/`url`/`headers`) and requires explicit consent. The prompt is rendered in a new terminal window opened by the shim (macOS: via `osascript` to open Terminal.app running `glue handle-url <url>`; Linux: via `x-terminal-emulator` or similar; we'll need to choose the safest cross-platform path here — flag for sign-off).
   - Open question: on macOS, do we instead post a system notification "click to review" and have the user run `glue handle-url <url>` themselves? Safer (no surprise terminal) but worse UX. **Recommendation: notification-only for v1, terminal-launch as a follow-up once we've validated which emulator to call.**
2. **stdio servers get an extra warning.** "This server will run `<command>` with arguments `<args>` on your machine every time Glue connects. Only proceed if you trust `<source>`."
3. **Source provenance is surfaced.** If `source=<url>` is provided, it's displayed prominently. If absent, the prompt notes "no source provided — install only if you copied this link from a trusted page."
4. **Auth secrets are out-of-band.** The URL cannot deliver a bearer token. User must run `glue mcp auth set` separately.
5. **Strict schema validation.** Unknown fields → reject. Unknown `type` → reject. Invalid `env` value (e.g. `${input:...}`) → reject.
6. **No autoload.** Newly-added servers default to `enabled: true` to match `glue mcp add`, but the running session (if any) does not auto-reconnect; user must `/mcp reconnect` or restart Glue. This is the same behaviour today.

---

## 6. Surface (CLI + slash)

Following `CLAUDE.md`'s conventions — top-level CLI for setup/diagnostic; slash for interactive in-session.

### 6.1 New top-level CLI

`glue url-handler <verb>` — noun namespace, parallel to `glue config`, `glue doctor`, `glue mcp`.

| Command | Purpose |
|---|---|
| `glue url-handler install` | Register the `glue://` scheme on the current OS. Prints what it's writing and where. |
| `glue url-handler uninstall` | Reverse of install. |
| `glue url-handler status` | Print whether the scheme is registered, what binary it points to, and any drift (e.g. shim points to an old `glue` path). |
| `glue url-handler test <url>` | Parse and validate a URL without writing config. Same output the handler would show in the confirmation prompt. |

`glue handle-url <url>` — the verb the OS invokes. Hidden from `glue --help` by default (it's an implementation detail, not a user-facing command). Mirrors `glue serve` style.

### 6.2 No slash command in v1

A `/mcp install <url>` slash equivalent is plausible but not justified yet — pasting a URL into a running TUI is awkward when the URL might span multiple lines, and `glue mcp add` already covers the in-session add path. Deferred until users ask.

### 6.3 Doctor block

Add a new section to `glue doctor` (`cli/lib/src/doctor/doctor.dart`):

- Is the `glue://` scheme registered?
- Does the registered handler resolve to the currently-running `glue` binary?
- On macOS, does the shim bundle exist where we expect it?

---

## 7. Architecture sketch (no code yet)

```
cli/lib/src/url_handler/
  url_parser.dart           # Pure: glue:// URL -> ParsedGlueUrl (sealed: McpInstallUrl, McpByNameUrl, ...)
  install_macos.dart        # Build/install the .app shim, run lsregister
  install_linux.dart        # Write .desktop, run update-desktop-database, xdg-mime
  install_windows.dart      # Registry writes (deferred)
  handle_url.dart           # Orchestrates: parse -> resolve (if by-name) -> confirm -> write -> notify

cli/lib/src/commands/
  url_handler_command.dart  # `glue url-handler install|uninstall|status|test`
  handle_url_command.dart   # `glue handle-url <url>` (hidden)

packages/glue_harness/lib/src/mcp_registry/
  client.dart               # Thin HTTP client for registry.modelcontextprotocol.io
  types.dart                # ServerEntry, VersionEntry — only what we use
```

Reuse, not duplicate:

- `McpConfigWriter.addServer(spec)` — already does the YAML-preserving write.
- `_buildSpec()` logic in `McpAddCommand` — extract its core into a pure `McpServerSpec.fromJsonConfig(Map)` constructor so both `glue mcp add` and `glue handle-url` go through the same validator.

---

## 8. Implementation roadmap

Bundles sized like the [MCP implementation plan](2026-05-15-mcp-implementation.md). Each is a landable PR.

### Bundle 1 — URL grammar + parser + `glue url-handler test`

Pure, no OS interaction. Lets us validate the grammar by parsing URLs in tests, with no install machinery yet.

- New: `cli/lib/src/url_handler/url_parser.dart`, `parsed_glue_url.dart`.
- Refactor: extract `McpServerSpec.fromJsonConfig(Map)` out of `_buildSpec` in `mcp_command.dart` so the parser produces the same `McpServerSpec` shape `mcp add` produces.
- New: `glue url-handler test <url>` CLI subcommand. Prints the parsed-and-validated config in the same diff style we'll use in the confirmation prompt. No-op otherwise.
- Tests: URL fixtures for every shape (VS Code-style URL-encoded JSON, Cursor-style base64, malformed, unknown `type`, `${input:...}` rejection, by-name with/without version/as overrides).

**Done criteria:** `dart test` green. `glue url-handler test 'glue://mcp/install?name=foo&config=...'` round-trips against fixtures.

### Bundle 2 — `glue handle-url` writes config

The handler verb itself. Still no OS-level registration.

- New: `cli/lib/src/url_handler/handle_url.dart` — orchestrator.
- New: `cli/lib/src/commands/handle_url_command.dart` — hidden CLI.
- Reuses Bundle 1's parser + `McpConfigWriter.addServer`.
- Interactive confirmation prompt (yes/no with the structured diff).
- `--yes` flag for scripted use.
- Adds source/provenance display when `?source=` is present.
- Adds the stdio-`command` extra warning.

**Done criteria:** `glue handle-url 'glue://mcp/install?...'` prompts, writes to `~/.glue/config.yaml`, and the next `glue mcp list` shows the new entry.

### Bundle 3 — MCP registry lookup for `by-name`

Adds the `glue://mcp/by-name/<id>` route.

- New: `packages/glue_harness/lib/src/mcp_registry/client.dart` — thin HTTP client for `registry.modelcontextprotocol.io`. Just `getServer(canonicalId, {version})`.
- Maps the registry's server-config shape to the same `Map` shape the inline parser expects, then funnels through Bundle 2.
- Includes `version=` and `as=` query-param handling.

**Done criteria:** `glue handle-url 'glue://mcp/by-name/io.github.upstash/context7'` resolves against the live registry, prompts, writes.

### Bundle 4 — Linux registration

`glue url-handler install|uninstall|status` on Linux only.

- New: `cli/lib/src/url_handler/install_linux.dart` — writes the `.desktop` file, runs `update-desktop-database` and `xdg-mime default`. `status` reads `xdg-mime query default x-scheme-handler/glue` and parses.
- `install` is idempotent. `uninstall` removes the `.desktop` file and clears the default handler.
- Doctor block: new section in `cli/lib/src/doctor/doctor.dart` calling the same status helper.

**Done criteria:** Fresh Linux install — `glue url-handler install`, then `xdg-open 'glue://mcp/install?...'` opens the confirmation prompt in a new terminal (or posts a notification — TBD per §5).

### Bundle 5 — macOS registration

The hardest bundle — the shim bundle.

- New: `cli/lib/src/url_handler/install_macos.dart` — generates the shim bundle in `~/Library/Application Support/Glue/Glue URL Handler.app/`, writes `Info.plist`, writes the launcher script that `exec`s `glue handle-url`, runs `lsregister -f`.
- Codesigning: ad-hoc sign the shim so Gatekeeper doesn't quarantine it. Document the limitation that distribution-time codesigning will need a real developer cert.
- Decide UX path for the prompt (§5 open question) — recommend system notification + user-launched `glue handle-url` for v1.
- Doctor block reuses §4 helper, branches on platform.

**Done criteria:** Fresh macOS install — `glue url-handler install`, click a `glue://` link in a browser, see the confirmation flow.

### Bundle 6 — Documentation + `glue://` button generator

User-facing finish. Mirrors VS Code's [install link generator](https://github.com/merill/vscode-mcp-install-link-creator).

- New docs page on `getglue.dev/docs/url-handler` covering: how to install the handler, how to author URLs, the security model, and a copy-paste button generator.
- Add `glue url-handler emit <id> --transport ...` (or similar — name TBD) that prints a `glue://mcp/install?...` URL the user can paste into a registry/README.

### Bundle 7 (optional, deferred) — Windows support

`install_windows.dart`. Gate on whether anyone's actually asked for it.

---

## 9. Open questions for sign-off

Before any code lands, get explicit decisions on:

1. **Confirmation UX on macOS.** Notification-only (safer, worse UX) vs auto-launch a terminal window (better UX, more surface area). Recommendation: notification-only for v1.
2. **Windows v1 inclusion.** Build it in Bundle 5 or defer to Bundle 7? Recommendation: defer.
3. **Base64 acceptance for `config=`.** Cursor uses base64; VS Code uses URL-encoded. Supporting both means registries can paste their existing payloads in. Recommendation: accept both, auto-detect.
4. **Registry endpoint for `by-name`.** Hardcode `registry.modelcontextprotocol.io` or make it configurable via `~/.glue/config.yaml`? Recommendation: hardcode for v1, add config later if a self-hosted registry case appears.
5. **`${input:foo}` placeholder support.** VS Code prompts for inputs during install. Glue's handler is non-interactive in v1 — accept and prompt (interactive) or reject (strict)? Recommendation: reject, document, revisit if it bites.
6. **Hidden `handle-url` vs visible.** Hide from `glue --help` because it's an OS implementation detail, or show because it's also useful for scripted "preview this URL" workflows? Recommendation: hide; `glue url-handler test <url>` covers the preview case.

---

## 10. Sources

- VS Code: [MCP servers docs](https://code.visualstudio.com/docs/copilot/customization/mcp-servers), [MCP developer guide](https://code.visualstudio.com/api/extension-guides/ai/mcp), [MCP configuration reference](https://code.visualstudio.com/docs/copilot/reference/mcp-configuration), [install link generator](https://github.com/merill/vscode-mcp-install-link-creator)
- Cursor: [Developers docs](https://docs.cursor.com/en/tools/developers)
- Smithery: [Deep linking spec](https://smithery.ai/docs/use/deep-linking)
- Windsurf: [Cascade MCP integration](https://docs.windsurf.com/windsurf/cascade/mcp)
- MCP registry: [registry repo](https://github.com/modelcontextprotocol/registry), [generic-server-json](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/server-json/generic-server-json.md), [authentication / namespace rules](https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/authentication.mdx)
- Security: [Proofpoint CursorJack](https://www.proofpoint.com/us/blog/threat-insight/cursorjack-weaponizing-deeplinks-exploit-cursor-ide), [GHSA-r22h-5wp2-2wfv](https://github.com/cursor/cursor/security/advisories/GHSA-r22h-5wp2-2wfv)
- Platform mechanics: [Apple LSRegisterURL](https://developer.apple.com/documentation/coreservices/1446350-lsregisterurl), [jw bargsten — custom protocol handler on macOS](https://bargsten.org/wissen/custom-protocol-handler-macos/), [Arch Wiki XDG MIME Applications](https://wiki.archlinux.org/title/XDG_MIME_Applications)
