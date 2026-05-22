# Glue ↔ dart_authmd integration

Glue acts as the **agent (consumer)** in the auth.md flow and, for Phase 1, also as its **own trusted issuer**. The user authorizes Glue on their machine, Glue signs ID-JAGs with a locally-generated key, and downstream services that have added Glue's issuer URL (or its CIMD) to their trusted-provider list accept those tokens.

The Phase 2 story — Anthropic / OpenAI / Cursor as the issuer — slots in cleanly behind the same `IdJagIssuer` abstraction whenever those providers ship issuance.

This document covers the agent and self-issuer paths. Glue does not act as a verifier (it does not accept ID-JAGs from other agents); that surface stays in `package:dart_authmd/verifier.dart` for third-party services.

## Why Glue can be the issuer

The spec only requires three things from an issuer:

1. **A signing key whose public half is fetchable** — solved with a generated EC keypair stored at `~/.glue/keys/id_jag_signing.jwk` and a hosted JWKS (static page on Cloudflare/GitHub Pages, or a `file://` URL for fully-local deployments).
2. **A stable `iss` URL** — `https://glue.helge.dev/<install-id>` (hosted) or `glue://<install-id>` (local-only). Optionally a CIMD document so the user's signing key can rotate without churning consumers' trust lists.
3. **At least one verified contact claim in the JWT** — bridged from an existing OAuth login (see "Email verification bridge" below).

There is **no spec-level requirement** that the issuer be a hosted LLM provider; the trust model is per-service and per-issuer. What hosted LLM providers will eventually offer is *mass-market trust* — Linear, Sentry, GitHub etc. shipping with Anthropic/OpenAI pre-trusted. For Phase 1, Glue targets:

- The user's own MCP servers (they control both sides of the trust list).
- Services whose operators have explicitly added Glue's issuer URL to their trusted-provider list (early-adopter design partners).
- Local dev loops against the `dart_authmd` example verifier server.

## Phase 1 design — Glue is its own issuer

### Email verification bridge

The spec requires `email_verified == true` (or `phone_number_verified == true`). Glue gets this without operating its own identity infrastructure by bridging from an existing OAuth login the user has already completed:

| Source                                  | Provides                                       | Status                                    |
| --------------------------------------- | ---------------------------------------------- | ----------------------------------------- |
| `CopilotAdapter` (GitHub OAuth device)  | GitHub email + verified flag                   | Already shipping (`copilot_adapter.dart`) |
| Future OIDC-shaped provider OAuth       | Provider's verified email                      | Add when adapter is built                 |
| Local OTP fallback                      | User clicks an emailed link once, persisted    | Phase 1 fallback; ~50 LOC + Resend dep    |

Stored under `~/.glue/identity.json`:

```json
{
  "subject": "<stable opaque id, e.g. ulid>",
  "email": "helge.sverre@gmail.com",
  "email_verified": true,
  "verified_at": "2026-05-23T10:14:00Z",
  "verification_source": "github_oauth"
}
```

The `subject` value is generated once on first run and persisted; it remains stable across email changes so services can match the same user even if the verified contact rotates.

### Issuer surface inside Glue

A thin wrapper over `package:dart_authmd/issuer.dart` in `packages/glue_harness/lib/src/agent_auth/`:

```dart
class GlueIdJagIssuer {
  GlueIdJagIssuer({
    required this.identity,        // from identity.json
    required this.signingKey,      // from ~/.glue/keys/id_jag_signing.jwk
    required this.issuerUrl,       // https://glue.helge.dev/<install-id> or glue://<install-id>
    Clock clock = const Clock.system(),
  });

  Future<String> mintFor({
    required Uri audience,
    required Uri? resource,
    Uri? agentContextId, // session id, for audit
  }) async {
    final claims = IdJagClaims(
      iss: issuerUrl,
      sub: identity.subject,
      aud: audience,
      clientId: issuerUrl, // or the CIMD URL if hosted
      jti: _newJti(),
      iat: clock.now(),
      exp: clock.now().add(const Duration(minutes: 5)),
      email: identity.email,
      emailVerified: identity.emailVerified,
      resource: resource,
      agentPlatform: 'glue',
      agentContextId: agentContextId?.toString(),
    );
    return _underlying.mint(claims);
  }

  final IdJagIssuer _underlying = /* package:dart_authmd issuer */;
}
```

### One-time setup commands

```
glue agent-auth init        # generate keypair, write identity.json, bridge from Copilot/GitHub login if present
glue agent-auth jwks        # print the JWKS so the user can host it (or copy to ~/.glue/jwks.json)
glue agent-auth cimd        # print a CIMD document for the user to host
glue agent-auth identity    # show the current verified identity & rotate verification source
glue agent-auth rotate-key  # generate a new signing key while keeping iss/CIMD stable
```

All implemented under `cli/lib/src/commands/agent_auth_command.dart`, following the noun-namespace convention in `CLAUDE.md`.

### Hosting JWKS

Three options, all supported, user picks:

1. **Static host** — copy the JWKS JSON to Cloudflare Pages / GitHub Pages, advertise via `https://glue.helge.dev/<install-id>/.well-known/jwks.json`. This is the path that lets remote services verify.
2. **Local file** — for fully-local deployments (a self-hosted MCP server on the same machine), `iss = file:///Users/.../glue/install.json` works because the verifier is also local.
3. **Glue-served** — `glue agent-auth serve --port 7717` runs a tiny `shelf` server that hosts `/.well-known/jwks.json` and the CIMD doc. Useful when the user already has a Tailscale or Cloudflare tunnel pointing at their laptop.

### MCP transport integration

Reuse the existing 401-handling plumbing:

| Existing Glue surface                                                                           | Change                                                                                                                                                                                                                            |
|-------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `packages/glue_strategies/lib/src/mcp_client/transport/http_sse.dart` — `McpHttpTransportError` | Already captures `WWW-Authenticate` on 401. ID-JAG discovery enters here.                                                                                                                                                         |
| `packages/glue_strategies/lib/src/mcp_client/client.dart` — `McpCallFailure.wwwAuthenticate`    | Surfaces the challenge to the pool.                                                                                                                                                                                               |
| `packages/glue_strategies/lib/src/mcp_client/pool.dart` — `McpPoolServerAuthRequiredEvent`      | Extend with an `agentAuth` block when discovery surfaces one.                                                                                                                                                                     |
| `packages/glue_strategies/lib/src/mcp_client/oauth.dart` — `discoverMcpAuth()`                  | Extend the two-hop PRM/AS metadata fetcher to parse `agent_auth` and return a typed `AgentAuthMetadata` (from `package:dart_authmd/agent.dart`).                                                                                  |
| `packages/glue_strategies/lib/src/credentials/credential_store.dart` — `setFields()`            | Already keyed by `mcp:<server-id>`. Add `agent_auth_credential` + `agent_auth_expires_at` fields.                                                                                                                                |
| `packages/glue_strategies/lib/src/providers/copilot_adapter.dart`                               | The refresh-before-call pattern (`freshCopilotToken()` in `_CopilotClient.stream()`) is the template for re-minting an ID-JAG before each tool call when the exchanged credential is near expiry.                                 |

### Required code changes (Phase 1)

#### 1. New MCP auth spec variant

In `packages/glue_strategies/lib/src/mcp_client/config.dart`, alongside `McpNoAuth`, `McpBearerAuth`, `McpOAuthAuth`:

```dart
final class McpAgentAuthSpec extends McpAuthSpec {
  const McpAgentAuthSpec({
    required this.audience,
    this.requestedCredentialType = CredentialType.accessToken,
  });

  final Uri audience;
  final CredentialType requestedCredentialType;
}
```

#### 2. Surface the `agent_auth` block from discovery

```dart
class McpAuthDiscovery {
  ProtectedResourceMetadata get prm;
  AuthorizationServerMetadata get authServer;
  AgentAuthMetadata? get agentAuth; // null when service does not advertise it
}
```

#### 3. New `AgentAuthFlow`

In `packages/glue_strategies/lib/src/providers/auth_flow.dart`:

```dart
sealed class AuthFlow { /* existing */ }

final class AgentAuthFlow extends AuthFlow {
  AgentAuthFlow({
    required this.audience,
    required this.issuer,        // GlueIdJagIssuer
    required this.serviceClient, // AgentAuthClient from package:dart_authmd/agent.dart
  });

  Future<AgentAuthCredential> exchange({Uri? sessionId}) async {
    final jwt = await issuer.mintFor(audience: audience, resource: null, agentContextId: sessionId);
    return serviceClient.exchange(/* registerUri, jwt, requestedCredentialType */);
  }
}
```

#### 4. Refresh-before-call

Mirror `CopilotAdapter._CopilotClient.stream()` (lines ~81–211 of `copilot_adapter.dart`):

```dart
Future<AgentAuthCredential> _freshAgentAuthCredential(McpServerId server) async {
  final stored = credentialStore.getFields('mcp:$server');
  final expiresAt = stored['agent_auth_expires_at'];
  if (expiresAt != null && DateTime.parse(expiresAt).isAfter(DateTime.now().add(_skew))) {
    return AgentAuthCredential.fromStored(stored);
  }
  final fresh = await _agentAuthFlow.exchange();
  await credentialStore.setFields('mcp:$server', fresh.toFields());
  return fresh;
}
```

#### 5. Per-service trust config

Add to `~/.glue/config.yaml`:

```yaml
agent_auth:
  issuer_url: https://glue.helge.dev/01HXY...   # or glue://<install-id>
  cimd_url: https://glue.helge.dev/01HXY.../cimd.json  # optional
  jwks_path: ~/.glue/keys/jwks.json
mcp_servers:
  - id: my-linear-clone
    url: https://my-mcp.example.com
    auth:
      type: agent_auth
      audience: https://my-mcp.example.com/auth
```

Parsed by `packages/glue_harness/lib/src/config/glue_config.dart`.

#### 6. Slash command + doctor block

- `/agent-auth` — show identity, issuer URL, JWKS host, and active credentials per MCP server.
- `/agent-auth refresh <server>` — force-re-mint and exchange.
- `/agent-auth revoke <server>` — purge stored credential and POST a logout token (signed by `LogoutTokenIssuer`) to the service's `revocation_uri`.
- `glue doctor` gains an `agent auth` block reporting: identity verification source + freshness, JWKS reachability, signing-key path & permissions, and a per-server "uses agent_auth" tally.

### Test strategy

Because Glue is its own issuer, the entire flow tests end-to-end without depending on any external provider. The `dart_authmd` package already plans an `example/verifier_server.dart`; the Glue-side integration test pairs against it:

1. Boot `example/verifier_server.dart` from `packages/dart_authmd/example/`.
2. Configure the test verifier to trust Glue's test issuer URL.
3. Start Glue with a test `~/.glue/keys/` and `identity.json`.
4. Configure an MCP server in Glue with `McpAgentAuthSpec(audience: <verifier-as-url>)`.
5. Run a tool call. Assert: 401 → discovery → mint → exchange → retry-with-token → success.
6. Negative tests: tampered signature, expired token, untrusted issuer, missing verified contact (synthesize an identity.json with `email_verified: false`).

Tagged `@Tags(['integration'])` per repo convention; runs via `just integration`.

If the `dart_authmd` example verifier isn't built yet, a minimal mock verifier (~80 LOC of `shelf`) lives alongside the test at `test/integration/mock_verifier.dart` and exercises the same flow against the same shapes. This keeps the Glue integration unblocked even if `dart_authmd` lands in a different order.

## Phase 2 — external issuers (Anthropic / OpenAI / Cursor)

When a hosted LLM provider ships an ID-JAG minting endpoint, drop in an alternative `IdJagIssuer` implementation behind the same `AgentAuthFlow` plumbing:

```dart
abstract class ProviderAdapter {
  // ...existing...
  Future<String> mintIdJag({required Uri audience}) =>
      throw UnsupportedError('${runtimeType} cannot mint ID-JAGs.');
}
```

`AnthropicAdapter.mintIdJag` and `OpenAiAdapter.mintIdJag` override when the API lands. `agent_auth.issuer_source` in `config.yaml` becomes a choice: `glue` (Phase 1 default), `anthropic`, `openai`, `copilot`. Per-service overrides let a user route different services to different issuers (e.g. use Anthropic's issuer for services that have Anthropic in their trust list, fall back to Glue's own issuer otherwise).

Nothing in the Phase 1 design has to change to accommodate this — the same MCP transport, the same `AgentAuthFlow`, the same credential store namespace, the same refresh loop.

## Open questions

- **Where should hosted JWKS live by default?** Cloudflare Pages is the easiest free option, but it ties identity to a domain. Offer GitHub Pages (`https://<gh-user>.github.io/glue-jwks/<install-id>/`) as the recommended default since Glue users overwhelmingly have a GitHub account already.
- **Per-tool-call vs per-session minting.** Spec recommends `exp = iat + 5m`. For a long-running session that hammers a tool, the exchanged credential covers most of it (its expiry is service-controlled). Re-mint only when the *exchanged credential* is near expiry, not the ID-JAG itself.
- **CIMD adoption from day one?** Mild bias toward yes — it makes signing-key rotation a CIMD-document edit rather than a coordinated trust-list update across every consuming service.
- **Revocation responsibility.** When the user runs `/agent-auth revoke`, do we attempt to call the service's `revocation_uri` (best-effort) or just purge the local credential? Lean: do both, but never block on the network call.

## Out of scope

- Glue acting as a **verifier** (accepting ID-JAGs from other agents). Lives in `package:dart_authmd/verifier.dart` for third-party services.
- A **bundled trusted-issuer registry**. Glue ships only the user's own issuer URL by default; Phase 2 adds whichever providers ship issuance endpoints.
- **Cross-machine identity continuity.** A user with multiple Glue installs ends up with multiple `iss/sub` identities. Could be solved later by syncing `identity.json` + signing key via a personal store; not needed for v1.
