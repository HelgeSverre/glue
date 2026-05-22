# dart-authmd — design notes and scaffolding

This directory captures the design and scaffolding for adding **auth.md** support to the Glue ecosystem. It does not
contain any Dart code yet — only the plans, spec synthesis, compliance matrix, and forward-looking Glue integration
sketch that should be in place before any package is created.

## What is auth.md?

[auth.md](https://workos.com/auth-md) is an emerging spec that lets autonomous agents authenticate to downstream
services on behalf of a user without leaking long-lived API keys. The flow this directory targets is the **agent
verified flow**:

1. An **agent provider** (Anthropic, OpenAI, Cursor, …) signs a short-lived JWT —
   an [Identity Assertion JWT Authorization Grant (ID-JAG)](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-identity-assertion-authz-grant) —
   that asserts a user's identity to a specific service.
2. The agent presents that JWT at the service's `/agent/auth` endpoint and receives a credential (`access_token` or
   `api_key`).
3. The service trusts the credential because it trusts the issuer's signing keys.

Discovery rides on existing OAuth metadata standards: [RFC 9728](https://datatracker.ietf.org/doc/html/rfc9728)
Protected Resource Metadata plus [RFC 8414](https://datatracker.ietf.org/doc/html/rfc8414) Authorization Server
Metadata, with an `agent_auth` block describing the agent-specific endpoints.

## What's in this directory?

- **[spec-summary.md](./spec-summary.md)** — an internalized synthesis of the auth.md spec. Read this first if you are
  new to the protocol.
- **[package-plan.md](./package-plan.md)** — the implementation roadmap for `packages/dart_authmd/`, a single Dart
  package exposing three top-level libraries: `issuer.dart`, `verifier.dart`, `agent.dart`.
- **[compliance.md](./compliance.md)** — a spec-coverage matrix tracking which auth.md requirements the package
  addresses at MVP, which are deferred, and which are explicitly out of scope.
- **[glue-integration.md](./glue-integration.md)** — how Glue consumes the `dart_authmd` package as an agent (consumer)
  **and** acts as its own trusted issuer in Phase 1. Phase 2 swaps in Anthropic/OpenAI as alternative issuers when their
  APIs land.

## Status

| Artifact                | Status                                                                                |
|-------------------------|---------------------------------------------------------------------------------------|
| `packages/dart_authmd/` | **Not created.** Plan only.                                                           |
| Glue integration        | **Phase 1 designed, shippable.** Glue is its own trusted issuer; no external blockers.|
| Spec stability          | ID-JAG draft is pre-RFC. CIMD draft is pre-RFC. Subject to change.                    |

There is no code to run yet. Phase 1 unlocks self-hosted MCP servers, opt-in services, and full local dev loops without
depending on any hosted LLM provider. Phase 2 swaps in Anthropic/OpenAI as alternative issuers when their APIs land.

## Reading order

1. [spec-summary.md](./spec-summary.md) — understand the protocol.
2. [package-plan.md](./package-plan.md) — see what the Dart package will look like.
3. [compliance.md](./compliance.md) — see what's in scope vs. deferred.
4. [glue-integration.md](./glue-integration.md) — see how Glue would consume it.

## External references

Pinned for convenience; check the source for the latest version.

- auth.md spec (agent providers) — <https://workos.com/auth-md/docs/agent-providers>
- ID-JAG draft — <https://datatracker.ietf.org/doc/html/draft-ietf-oauth-identity-assertion-authz-grant>
- RFC 9728 — OAuth 2.0 Protected Resource Metadata
- RFC 8414 — OAuth 2.0 Authorization Server Metadata
- RFC 7517 — JSON Web Key Set (JWKS)
- RFC 7519 — JSON Web Token (JWT)
- RFC 8417 — Security Event Token (SET)
- OAuth Client ID Metadata Document
  draft — <https://datatracker.ietf.org/doc/draft-ietf-oauth-client-id-metadata-document/>
- OpenID Connect Back-Channel Logout 1.0 (logout token shape)
- OpenID CAEP (Continuous Access Evaluation Profile) — referenced as the extension trajectory for revocation events.
