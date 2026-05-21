# MCP OAuth — making remote MCP servers actually usable

**Status:** Design approved 2026-05-21. Implementation plan to follow.
**Owner:** Helge

## Why

A user added `smartbear-bugsnag` (`https://bugsnag.mcp.smartbear.com/mcp`) as an HTTP MCP server with no `auth:` field. On session start the pool ran three reconnect attempts against a 401-returning server and marked it `dead`. No prompt, no usable error — the agent just lost the tools silently.

The OAuth code path already exists (`oauth.dart` ships PKCE + DCR + refresh), the CLI command works (`glue mcp auth login`), and `McpServerAuthRequiredEvent` is defined and consumed by the App layer. None of that fires because **nothing emits it**: the HTTP transport collapses 401 into a generic `transportError`, and the pool's discovery doesn't follow RFC 9728 so it can't even find the auth server.

This design closes the gap and aligns glue with how every other MCP client (opencode, gemini-cli, Cline, official TS/Python SDKs) handles OAuth.

## Non-goals

- Multi-authorization-server picker (v1 takes the first listed).
- Client ID Metadata Documents (draft-ietf-oauth-client-id-metadata-document).
- RFC 8707 `resource=` parameter on token exchange.
- OAuth on the ACP transport (glue's agent host, not a consumer).
- stdio servers (per MCP spec, stdio uses env vars, not OAuth).
- Encrypting tokens at rest in the credential store.

---

## Architecture overview

Five independent touchpoints. Each is unit-testable in isolation. None reach beyond MCP.

1. **`oauth.dart`** — replace direct-discovery with an RFC 9728 pipeline. Legacy probe kept as last-resort fallback.
2. **`http_sse.dart`** — `McpHttpTransportError` carries `WWW-Authenticate`. The pool's `_failureKind` keys on status code so 401 → `authFailed`.
3. **`pool.dart`** — new `handleAuthChallenge` decision path: silent refresh, then emit auth-required and park the server in a new `McpAwaitingAuth` state that does **not** consume reconnect budget.
4. **`/mcp` panel** — context-aware action: `Authenticate` / `Re-authenticate` / `Sign out`, hidden for stdio.
5. **`McpAuthFlowRunner` + `McpAuthStatusPanel`** — shared runner backing the CLI command, the slash command, and the auto-triggered flow. Status panel renders discovery/registration/awaiting-callback state. Browser does the actual sign-in.

Credential schema unchanged. Config gains three optional fields per HTTP/WS server: `auth: oauth` (written back on first success), `resource_metadata_url`, `authorization_server` (cached after discovery, self-healing on staleness).

---

## §1 — Discovery pipeline (RFC 9728 + RFC 8414)

The MCP spec mandates RFC 9728. Discovery becomes a three-stage sequence with fallbacks:

```
discoverMcpAuth(serverUrl, {wwwAuthHeader, cachedResourceMetadataUrl}):
  # 1. Resource metadata URL: header → cache → well-known fallbacks
  resourceMetaUrl ← parseResourceMetadata(wwwAuthHeader)
                  ?? cachedResourceMetadataUrl
                  ?? tryWellKnown(serverUrl, [
                       "/.well-known/oauth-protected-resource{path}",
                       "/.well-known/oauth-protected-resource",
                     ])

  if resourceMetaUrl is null:
    # Server doesn't follow RFC 9728. Last-resort: existing direct probe.
    return legacyDirectDiscovery(serverUrl)

  # 2. Fetch & validate protected resource metadata
  meta ← GET resourceMetaUrl
  validate meta.resource matches serverUrl origin (RFC 9728)
  scopes ← meta.scopes_supported ?? []

  # 3. Resolve the first authorization_server
  authServer ← meta.authorization_servers.first
  endpoints ← discoverAuthorizationServer(authServer)
    # tries RFC 8414, then OIDC, in path-suffix order per spec section
    # validates issuer matches the URL used to fetch

  return McpAuthDiscovery(
    endpoints: endpoints,
    scopes: scopes,                          # carried through to authorize URL
    resourceMetadataUrl: resourceMetaUrl,    # cached back to config
    authorizationServer: authServer,         # cached back to config
  )
```

### Correctness rules

- **Issuer validation.** Skip metadata whose `issuer` doesn't equal the URL it was fetched from. Drop and try the next discovery path.
- **Multi-AS.** v1 uses the first `authorization_servers` entry. Log others at debug level for future-proofing.
- **`WWW-Authenticate` parsing.** RFC 6750 grammar — parser, not regex. Handles quoted commas and multiple challenges correctly.
- **Caching.** Successful discovery writes `resource_metadata_url` + `authorization_server` to the server's config entry. Self-healing: stale cache → fall back to fresh discovery.
- **Scopes.** `scope` from `WWW-Authenticate` wins over `scopes_supported` from resource metadata. Pass to `runOAuthAuthorizationCodeFlow`.

### Files

- `packages/glue_strategies/lib/src/mcp_client/oauth.dart` — new `discoverMcpAuth`, `parseWwwAuthenticate`, `discoverProtectedResourceMetadata`, `discoverAuthorizationServer`. Existing `discoverOAuthEndpoints` becomes a thin wrapper named `legacyDirectDiscovery`, used only as last-resort fallback.

---

## §2 — 401 → refresh → auth-required state machine

Pool's connect path becomes auth-aware:

```
pool._connect(snapshot):
  try:
    client ← factory(spec, credentials)     # builds transport with current token
    init   ← client.initialize()
    tools  ← client.listTools()
    → McpConnected
  catch McpCallFailure(reason: 'transport_error') with HTTP 401:
    handleAuthChallenge(snapshot, wwwAuthHeader)
  catch _:
    existing _handleFailure() with backoff
```

`handleAuthChallenge` is pure decision logic — no UI, no flow:

```
handleAuthChallenge(snapshot, wwwAuth):
  # Step A — silent refresh.
  refresh = credentials.getField('mcp:<id>', 'oauth_refresh')
  if refresh != null:
    try:
      newTokens ← refreshOAuthTokens(cachedEndpoints, client, refresh)
      storeMcpOAuthTokens(...)
      _connect(snapshot)              # one retry, same path
      return
    catch:
      invalidateMcpAuth(id, scope: 'tokens')   # keep DCR client_id
      # fall through

  # Step B — first-time auth or refresh exhausted.
  emit McpPoolServerAuthRequiredEvent(
    serverId: id,
    reauthCommand: '/mcp auth login <id>',
    resourceMetadataUrl: parseWwwAuth(wwwAuth).resourceMetadata,
    wwwAuthenticate: wwwAuth,
  )
  snapshot.state = McpAwaitingAuth(lastError: '401 from server')
  # NO retry timer armed. NO budget consumed. Server is parked.
```

### `McpAwaitingAuth` — new connection state

Sibling of `McpDead` in the `McpConnectionState` sealed union.

- Does **not** trigger reconnect backoff.
- Counted as `unhealthy` for the status-bar badge, labelled distinctly: `MCP: 1 needs auth`.
- Cleared by `pool.reconnect(id)` after successful auth flow.
- Applies to existing `McpDead` state on user action: clicking "Authenticate" on a dead server clears `dead` and runs the flow.

### Auto-upgrade on 401

The smartbear-bugsnag case has `auth: none`. We **do not** require explicit `auth: oauth` to trigger the flow — on 401 with a `WWW-Authenticate: Bearer` challenge we treat the server as OAuth regardless of declared auth. After successful login, `McpConfigWriter.updateAuth(id, McpOAuthAuth(), ...)` writes `auth: oauth` back to `~/.glue/config.yaml`, idempotently and only when currently `none`.

### Mid-session 401 from a tool call

`McpClient.callTool` catches transport-level 401 and fails with `reason: 'auth_expired', retryable: true`. The agent's existing single-retry on transport_error calls into `pool.attemptRefreshAndReconnect(serverId)` first. If silent refresh succeeds → tool call retries against fresh connection. If not → tool call fails with "MCP server needs re-authentication" + auth-required event.

### Granular invalidation

Inspired by the TS SDK's `invalidateCredentials(scope)`:

```dart
enum McpAuthInvalidation { all, tokens, discovery, client }

void invalidateMcpAuth(String serverId, McpAuthInvalidation scope) { ... }
```

- `tokens` → clear `oauth_access`, `oauth_refresh`, `oauth_expires_at`, `oauth_scope`. Keep `oauth_client_id` + secret. Used after silent-refresh failure.
- `discovery` → clear cached `resource_metadata_url` + `authorization_server` on the spec. Used when discovery returns inconsistent issuer.
- `client` → clear `oauth_client_id` + secret. Forces re-DCR. Used when auth server rejects stored client.
- `all` → wipe everything. Used by `/mcp auth logout`.

### Files

- `packages/glue_strategies/lib/src/mcp_client/connection_state.dart` — add `McpAwaitingAuth`.
- `packages/glue_strategies/lib/src/mcp_client/transport/http_sse.dart` — `McpHttpTransportError.wwwAuthenticate` field.
- `packages/glue_strategies/lib/src/mcp_client/pool.dart` — `handleAuthChallenge`, `attemptRefreshAndReconnect`, `invalidateMcpAuth`. Emits `McpPoolServerAuthRequiredEvent`.
- `packages/glue_strategies/lib/src/mcp_client/client.dart` — `callTool` translates 401 to `auth_expired`.
- `cli/lib/src/app.dart` — `McpPoolServerAuthRequiredEvent` opens `McpAuthStatusPanel` (preserving current TUI focus).

---

## §3 — TUI surfaces

### `McpAuthStatusPanel` (new)

```
┌─ Authenticating smartbear-bugsnag ────────────────────┐
│                                                       │
│  ● Discovered auth.smartbear.com                      │
│  ● Registered client                                  │
│  ◯ Waiting for browser sign-in…                       │
│                                                       │
│    https://auth.smartbear.com/oauth/authorize?...     │
│                                                       │
│    [O] Open browser   [C] Copy URL   [Esc] Cancel     │
└───────────────────────────────────────────────────────┘
        ↓ (loopback callback hits)
        auto-dismiss + pool.reconnect(serverId)
```

States: `discovering` → `registering` (only if DCR) → `awaitingCallback` → terminal (`success` | `error` | `cancelled` | `timeout`). Listens to a `Stream<McpAuthFlowState>` from `McpAuthFlowRunner`.

**Non-TTY fallback:** ACP server / headless tests / `--print` skip the panel and print URL + state lines as plain output. Same runner, different sink.

### `/mcp` panel — auth action

`_actionsFor(snapshot)` gains auth slot:

```dart
List<_McpAction> _actionsFor(McpServerSnapshot s) {
  final isRemote = s.spec is McpHttpServerSpec || s.spec is McpWebSocketServerSpec;
  final authState = isRemote ? _resolveAuthState(s) : _McpAuthState.notApplicable;

  return [
    if (s.state is McpAwaitingAuth || authState == _McpAuthState.needsAuth)
      _McpAction.authenticate,        // top — primary CTA
    if (authState == _McpAuthState.signedIn)
      _McpAction.reauthenticate,
    _McpAction.reconnect,
    _McpAction.toggle,
    if (s.tools.isNotEmpty) _McpAction.viewTools,
    _McpAction.copyId,
    if (authState == _McpAuthState.signedIn) _McpAction.signOut,
    if (s.lastError != null) _McpAction.showError,
  ];
}
```

Labels: `Authenticate` (or `Sign in to <serverName>` when known) / `Re-authenticate` / `Sign out`.

### `/mcp list` text form

Add a status column: `connected · oauth (stored)`, `dead · oauth (refresh failed)`, `awaiting-auth · oauth (not signed in)`.

### Status bar

`unhealthyCount` adds `McpAwaitingAuth`. Label switches: `MCP: 1 needs auth` instead of `MCP: 1 dead` when the unhealthy set is auth-only.

### Files

- `cli/lib/src/commands/slash/mcp.dart` — `_McpAuthState`, new actions, dispatch.
- `cli/lib/src/ui/mcp_auth_flow_panel.dart` (new) — `McpAuthStatusPanel` + state binding.
- `packages/glue_strategies/lib/src/mcp_client/auth_flow.dart` (new) — `McpAuthFlowRunner` shared across CLI / slash / auto-triggered surfaces.

---

## §4 — Config & credential schema

### Schema (additive)

```yaml
mcp:
  servers:
    smartbear-bugsnag:
      url: "https://bugsnag.mcp.smartbear.com/mcp"
      auth: oauth                                        # written back on first success
      resource_metadata_url: "https://…/.well-known/…"   # cached after discovery
      authorization_server: "https://auth.…"             # cached after discovery
```

All three new fields optional. Cached URLs are session-start fast paths; staleness is self-healing.

### Credential store

Unchanged. Existing `McpOAuthFields` (`oauth_access`, `oauth_refresh`, `oauth_expires_at`, `oauth_client_id`, `oauth_client_secret`, `oauth_scope`) is sufficient. We add only the `invalidateMcpAuth` helper.

### Migration

- Existing `auth: oauth` servers using legacy direct discovery keep working (fallback path).
- Existing `oauth_*` credentials remain valid.
- No data migration required.

### Files

- `packages/glue_strategies/lib/src/mcp_client/config.dart` — new fields on http/ws specs.
- `packages/glue_harness/lib/src/config/mcp_config_writer.dart` — new `updateAuth` method.

---

## §5 — Testing strategy

Three layers, all in existing test trees:

### Unit (`packages/glue_strategies/test/mcp_client/oauth_test.dart` — extend)

- `parseWwwAuthenticate`: quoted commas, multiple challenges, missing `resource_metadata`.
- `discoverMcpAuth`: WWW-Authenticate hint, well-known path-insertion fallback, root fallback, issuer mismatch rejection, multi-AS first-wins.
- `refreshOAuthTokens`: refresh token rotation case.
- `invalidateMcpAuth`: each scope clears exactly the expected fields.

### Pool-level (`packages/glue_strategies/test/mcp_client/pool_auth_test.dart` — new)

In-memory transport returning synthetic 401 with configurable `WWW-Authenticate`.

- `connect → 401 → no refresh token` → emits `AuthRequiredEvent` + `McpAwaitingAuth` + no retry timer armed.
- `connect → 401 → refresh succeeds` → `McpConnected`, single retry.
- `connect → 401 → refresh fails` → tokens invalidated (refresh cleared, client_id retained), `AuthRequiredEvent` emitted.
- `mid-session callTool 401 → silent refresh → retries → succeeds`.
- `McpAwaitingAuth` does not burn reconnect budget.

### Surface (`cli/test/commands/slash/mcp_auth_action_test.dart` — new)

- `_actionsFor` returns `Authenticate` for `McpAwaitingAuth`, `Re-authenticate` + `Sign out` when tokens stored.
- Stdio servers never get auth actions.
- `/mcp list` text form includes new status column.
- `McpAuthFlowRunner` end-to-end against in-memory http client: discovery → DCR → fake authorization → token exchange → tokens stored, `auth: oauth` written back to config.

No live-server e2e. Smartbear-bugsnag is reproducible against any RFC 9728 server; manual smoke after the design lands.
