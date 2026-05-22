# dart_authmd — package implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:
> executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Glue-local Dart package, `packages/dart_authmd/`, that any project can use to act as an **issuer** (
agent provider), **verifier** (service), or **agent** (client) in the auth.md agent-verified flow. The package owns all
JOSE plumbing, metadata serialization, and spec-mandated error semantics so adopters only deal with their own business
logic.

**Architecture:** Three logical surfaces — issuer / verifier / agent — sharing a `core/` of value types and a minimal
JOSE layer. Each surface is its own top-level library so consumers only import what they need. No dependency on any
`glue_*` package; the only reason to live in this monorepo today is iteration speed.

**Tech Stack:** Dart `^3.12.0` workspace, `package:jose_plus` for JOSE primitives, `package:http` for client calls,
`package:shelf` + `package:shelf_router` for the bundled example servers, `package:meta`, `package:test`.

---

## Status

Plan only. No package files have been created yet. The `dart_authmd` name is currently free on pub.dev; reserve it when
the package is ready to publish.

The package is Glue-local for now, per product choice, so `pubspec.yaml` uses `publish_to: none`. The public API should
be clean enough that publishing later is a metadata-and-docs decision rather than a rewrite.

## Source notes

- Internalized spec: [./spec-summary.md](./spec-summary.md). Treat that file as the single source of truth for protocol
  behavior referenced by tests below.
- auth.md spec page — <https://workos.com/auth-md/docs/agent-providers>
- ID-JAG draft — <https://datatracker.ietf.org/doc/html/draft-ietf-oauth-identity-assertion-authz-grant>
- RFC 9728 Protected Resource Metadata, RFC 8414 Authorization Server Metadata, RFC 7517 JWKS, RFC 7519 JWT, RFC 8417
  SET
- CIMD draft — <https://datatracker.ietf.org/doc/draft-ietf-oauth-client-id-metadata-document/>
- `package:jose_plus` — JOSE primitives (JWT sign/verify, JWK/JWKS, ES256/RS256/PS256)

## Package shape

Create:

```text
packages/dart_authmd/
  pubspec.yaml
  analysis_options.yaml
  README.md
  CHANGELOG.md
  lib/
    dart_authmd.dart            # shared types: claims, metadata, errors
    issuer.dart                 # IdJagIssuer, JwksHost, CimdDocument, LogoutTokenIssuer
    verifier.dart               # IdJagVerifier, ProviderRegistry, RevocationAcceptor, ReplayCache
    agent.dart                  # AgentAuthClient, PrmDiscovery, CredentialExchange
    src/
      core/
        claims.dart             # IdJagClaims, AgentAuthCredential
        metadata.dart           # ProtectedResourceMetadata, AuthorizationServerMetadata, AgentAuthMetadata
        errors.dart             # AuthMdError sealed family, error_code enum
        time.dart               # Clock abstraction for deterministic tests
        jose/
          jwk.dart              # Jwk, JwkSet, key resolution
          jwt_codec.dart        # sign/verify wrappers over jose_plus
      issuer/
        id_jag_issuer.dart
        jwks_host.dart          # serializes JwkSet for hosting at /.well-known/jwks.json
        cimd.dart               # CimdDocument + serialization
        logout_token_issuer.dart
      verifier/
        id_jag_verifier.dart    # the central verification pipeline (issuer/sig/aud/exp/jti/contact)
        provider_registry.dart  # trusted-issuer list, JWKS fetch & cache
        revocation.dart         # RevocationAcceptor verifies inbound logout tokens
        replay_cache.dart       # ReplayCache abstract class + InMemoryReplayCache
        credential_issuer.dart  # serializes the exchange response (access_token vs api_key)
      agent/
        prm_discovery.dart      # fetch & cache PRM + AS metadata
        as_metadata.dart        # parse AgentAuthMetadata block out of AS metadata
        credential_exchange.dart # POST /agent/auth, parse typed response
        www_authenticate.dart   # parse `WWW-Authenticate: Bearer resource_metadata="..."`
  example/
    issuer_server.dart          # minimal shelf server: mints + JWKS + CIMD
    verifier_server.dart        # minimal shelf server: PRM + AS metadata + /agent/auth + /agent/auth/revoke
    agent_cli.dart              # CLI that discovers, exchanges, and calls a protected resource
    README.md                   # how to run the three together
  test/
    core/
      claims_serialization_test.dart
      metadata_serialization_test.dart
      errors_test.dart
    issuer/
      id_jag_issuer_test.dart
      jwks_host_test.dart
      cimd_test.dart
      logout_token_issuer_test.dart
    verifier/
      id_jag_verifier_test.dart
      provider_registry_test.dart
      replay_cache_test.dart
      revocation_test.dart
    agent/
      prm_discovery_test.dart
      www_authenticate_test.dart
      credential_exchange_test.dart
    golden/
      id_jag_payload_golden.json
      protected_resource_metadata_golden.json
      authorization_server_metadata_golden.json
      cimd_golden.json
      logout_token_golden.json
    integration/
      end_to_end_test.dart      # @Tags(['integration']) — boots example servers in-process
```

Root workspace change in `/Users/helge/code/glue/pubspec.yaml`:

```yaml
workspace:
  - cli
  - packages/dart_authmd
  - packages/glue_core
  - packages/glue_strategies
  - packages/glue_runtimes
  - packages/glue_harness
  - packages/glue_server
```

Package dependencies:

```yaml
name: dart_authmd
description: Dart implementation of the auth.md agent-verified flow (ID-JAG issuance, verification, and exchange).
version: 0.0.1
publish_to: none

environment:
  sdk: '>=3.12.0 <4.0.0'

resolution: workspace

dependencies:
  http: ^1.6.0
  jose_plus: ^0.5.0
  meta: ^1.15.0

dev_dependencies:
  lints: ^6.1.0
  shelf: ^1.4.2
  shelf_router: ^1.1.4
  test: ^1.30.0
```

`shelf` and `shelf_router` are dev-only because they are used solely by the bundled examples and the integration test.
Consumers running their own server can pick any HTTP framework.

## Public API

`lib/dart_authmd.dart` re-exports shared types so consumers can write a single import for value objects:

```dart
export 'src/core/claims.dart' show IdJagClaims, AgentAuthCredential, CredentialType;
export 'src/core/metadata.dart'
    show
    ProtectedResourceMetadata,
    AuthorizationServerMetadata,
    AgentAuthMetadata,
    AssertionType,
    IdentityType;
export 'src/core/errors.dart' show AuthMdError, AuthMdErrorCode;
```

`lib/issuer.dart`:

```dart
class IdJagIssuer {
  IdJagIssuer({
    required this.issuerUrl,
    required this.signingKey,
    Duration tokenLifetime = const Duration(minutes: 5),
    Clock clock = const Clock.system(),
  });

  final Uri issuerUrl;
  final Jwk signingKey;

  Future<String> mint(IdJagClaims claims);
}

class JwksHost {
  JwksHost(this.keys);

  final JwkSet keys;

  Map<String, Object?> toJson(); // serve at /.well-known/jwks.json
}

class CimdDocument {
  // serializes the Client ID Metadata Document
}

class LogoutTokenIssuer {
  LogoutTokenIssuer({required this.issuerUrl, required this.signingKey});

  Future<String> mint({
    required String subject,
    required Uri audience,
    required String jti,
  });
}
```

`lib/verifier.dart`:

```dart
class IdJagVerifier {
  IdJagVerifier({
    required this.providerRegistry,
    required this.expectedAudience,
    required this.replayCache,
    Duration clockSkew = const Duration(seconds: 30),
  });

  Future<IdJagClaims> verify(String token); // throws AuthMdError on failure
}

abstract interface class ProviderRegistry {
  Future<JwkSet> resolveKeysFor(Uri issuer);

  bool isTrusted(Uri issuer);
}

class StaticProviderRegistry implements ProviderRegistry {
  /* ... */
}

abstract interface class ReplayCache {
  Future<bool> seen(String jti, DateTime expiry); // true if already-seen, atomic check-and-set
}

class InMemoryReplayCache implements ReplayCache {
  /* ... */
}

class RevocationAcceptor {
  RevocationAcceptor({required this.providerRegistry});

  Future<RevocationEvent> verify(String logoutToken);
}
```

`lib/agent.dart`:

```dart
class AgentAuthClient {
  AgentAuthClient({http.Client? httpClient});

  Future<AgentAuthDiscovery?> discoverFromChallenge(String wwwAuthenticate);

  Future<AgentAuthDiscovery> discoverFromResource(Uri resource);

  Future<AgentAuthCredential> exchange({
    required Uri registerUri,
    required String assertion,
    required CredentialType requestedCredentialType,
  });
}

class AgentAuthDiscovery {
  ProtectedResourceMetadata get prm;

  AuthorizationServerMetadata get authServer;

  AgentAuthMetadata get agentAuth;
}
```

## Implementation bundles

### Bundle 1 — Scaffold the workspace member

- [ ] Create `packages/dart_authmd/` with `pubspec.yaml`, `analysis_options.yaml` (inherits from
  `package:lints/recommended.yaml` plus `always_use_package_imports`), `README.md`, `CHANGELOG.md`.
- [ ] Add `packages/dart_authmd` to the root `pubspec.yaml` `workspace:` list.
- [ ] Create empty top-level libraries (`lib/dart_authmd.dart`, `lib/issuer.dart`, `lib/verifier.dart`,
  `lib/agent.dart`).
- [ ] Run `dart pub get` from the repo root, then `dart analyze packages/dart_authmd`. Both must succeed with no output.

### Bundle 2 — Core types + golden serialization

- [ ] Implement `IdJagClaims` (required + optional fields), `AgentAuthCredential`, `CredentialType`, `AssertionType`,
  `IdentityType` enums.
- [ ] Implement `ProtectedResourceMetadata`, `AuthorizationServerMetadata`, `AgentAuthMetadata`.
- [ ] Implement the `AuthMdError` sealed family with one variant per code in [./spec-summary.md](./spec-summary.md)
  error taxonomy.
- [ ] Add `Clock` abstraction in `core/time.dart`.
- [ ] Golden tests: round-trip a representative ID-JAG payload, PRM, AS metadata, CIMD, and logout token against the
  JSON fixtures under `test/golden/`. Tests fail if serialization drifts.

### Bundle 3 — JOSE codec

- [ ] Implement `Jwk` and `JwkSet` parsers (from JSON, from `package:jose_plus`'s key types).
- [ ] Implement `JwtCodec.sign(claims, key, header)` and `JwtCodec.verify(token, keys)`.
- [ ] Restrict supported algorithms to `ES256`, `ES384`, `RS256`, `PS256`. Reject `none` and `HS*` explicitly.
- [ ] Tests: sign + verify happy paths for ES256 and RS256; reject tampered signatures; reject disallowed algorithms.

### Bundle 4 — Issuer surface

- [ ] `IdJagIssuer.mint(claims)` produces a signed JWT with `typ: oauth-id-jag+jwt`, the configured `iss`, and `iat`/
  `exp` derived from `Clock`.
- [ ] `JwksHost.toJson()` serializes the configured keys (public-half only — never expose private material).
- [ ] `CimdDocument` builds and serializes the CIMD JSON.
- [ ] `LogoutTokenIssuer.mint(...)` produces a signed JWT with `typ: logout+jwt` and the required `events` claim.
- [ ] `example/issuer_server.dart`: a `shelf` server exposing `GET /.well-known/jwks.json`, `GET /agent-auth.json` (
  CIMD), and a CLI-style `POST /mint` for the bundled e2e test.
- [ ] Tests: keys round-trip through JWKS without leaking private material; minted tokens contain the required claims;
  logout tokens carry the `events` envelope.

### Bundle 5 — Verifier surface

- [ ] `ProviderRegistry` interface + `StaticProviderRegistry` (issuer → JWKS URL, cached with TTL).
- [ ] `ReplayCache` interface + `InMemoryReplayCache` (TTL = `exp + clockSkew`).
- [ ] `IdJagVerifier.verify(token)` runs the pipeline in this order, throwing the spec-mandated `AuthMdError` on the
  first failure:
    1. Parse JOSE header → check `typ == oauth-id-jag+jwt`, `alg` in allow-list.
    2. Resolve `iss` against `ProviderRegistry.isTrusted` → `invalid_issuer` on miss.
    3. Resolve `client_id` (issuer URL or CIMD URL) → `invalid_client_id` on miss.
    4. Fetch JWKS for issuer, verify signature → `invalid_signature` on failure.
    5. Check `aud == expectedAudience` → `invalid_audience`.
    6. Check `exp > now - clockSkew` → `expired`.
    7. Check `email_verified == true || phone_number_verified == true` → `missing_verified_email`.
    8. `replayCache.seen(jti, exp)` → `replay_detected`.
- [ ] `RevocationAcceptor.verify(token)` reuses the same pipeline minus replay (logout tokens have their own jti space)
  and additionally checks the `events` claim envelope.
- [ ] `CredentialIssuer` serializes the exchange response with the right shape for `access_token` vs `api_key`.
- [ ] Tests: one test per error code in the spec taxonomy, plus a happy-path test; revocation test exercises the events
  envelope.

### Bundle 6 — Agent surface

- [ ] `WwwAuthenticate.parse(header)` extracts `resource_metadata` from a `Bearer` challenge.
- [ ] `PrmDiscovery.fetch(resource)` follows the two-hop chain (`/.well-known/oauth-protected-resource` → AS metadata)
  and surfaces the `agent_auth` block as a typed `AgentAuthMetadata`. Returns `null` if the service does not advertise
  agent_auth.
- [ ] `CredentialExchange.exchange(...)` POSTs the JSON body to `register_uri`, parses both response shapes, and
  surfaces typed errors mapped from server-side error codes.
- [ ] `AgentAuthClient` composes the three above into a single ergonomic entry point.
- [ ] Tests: parse all the WWW-Authenticate variants in RFC 9728; happy-path discovery; parse both response shapes;
  surface server-side `error` codes as `AuthMdError` correctly.

### Bundle 7 — End-to-end example + integration test

- [ ] `example/agent_cli.dart`: a CLI that discovers a resource, mints an ID-JAG via the example issuer server,
  exchanges at the example verifier server, and calls a "protected" endpoint with the returned credential.
- [ ] `test/integration/end_to_end_test.dart` (tagged `@Tags(['integration'])` per repo convention): boots
  `issuer_server`, `verifier_server`, and exercises `agent_cli` flow in-process. Asserts the happy path plus rejection
  on tampered signature, expired token, replayed `jti`, and missing verified contact.
- [ ] `example/README.md`: how to run the three locally (with a `just` recipe if it earns its keep).

### Bundle 8 — Polish & release prep

- [ ] `README.md`: usage examples for each of the three surfaces, copy-pastable.
- [ ] `CHANGELOG.md`: initial `## 0.0.1` entry.
- [ ] Confirm `dart format --set-exit-if-changed packages/dart_authmd` passes.
- [ ] Confirm `dart analyze --fatal-infos packages/dart_authmd` passes.
- [ ] Confirm `dart test packages/dart_authmd` passes (and `dart test packages/dart_authmd --run-skipped -t integration`
  for the e2e).
- [ ] Update `docs/dart-authmd/compliance.md` status column to reflect the actual ship state.

## Test plan

| Layer       | Strategy                                                                                                |
|-------------|---------------------------------------------------------------------------------------------------------|
| Core types  | Round-trip JSON via golden files under `test/golden/`.                                                  |
| JOSE        | Sign + verify ES256/RS256; reject `none`, `HS*`, tampered signatures, mismatched `kid`.                 |
| Issuer      | Minted JWT carries the right claims and header `typ`; JWKS does not leak private material.              |
| Verifier    | One test per error code in the spec taxonomy; happy path; replay cache atomicity.                       |
| Agent       | WWW-Authenticate parsing for every RFC 9728 variant; discovery returns null when no `agent_auth` block. |
| Integration | All three example servers run in-process; happy path; representative rejection scenarios.               |
| Security    | Reject `none`/`HS*`, oversized tokens, replay, expired, missing verified contact, wrong audience.       |

## Assumptions

- Dart SDK `^3.12.0` (matches the rest of the workspace).
- `package:jose_plus` provides ES256/RS256 sign/verify and JWK parsing. If it does not, this plan grows a small
  primitives module on top of `package:cryptography`.
- `shelf` is dev-only — consumers bring their own HTTP framework.
- In-memory `ReplayCache` is the default. Production users plug in their own backed by Redis or a database.
- Clock skew tolerance defaults to 30 seconds. Configurable.

## Risks

- **JOSE library churn.** `package:jose_plus` is the current recommended Dart JOSE library, but the ecosystem is small.
  If it goes unmaintained, the abstraction boundary in `core/jose/jwt_codec.dart` keeps the swap to
  `package:cryptography` primitives a one-file change.
- **Replay cache scoping.** An in-memory cache is single-process; deployed services with multiple instances must
  implement their own. The interface is small enough that this is a reasonable burden, but the README needs to call it
  out.
- **Spec drift.** ID-JAG and CIMD are pre-RFC drafts. `compliance.md` is the place to track drift; every bump tags the
  change with the draft revision it tracks.
- **`alg=none` and `HS*`.** Both must be explicitly rejected. Tests are non-negotiable here.

## Acceptance criteria

- Issuer mints a token that the verifier accepts on the happy path.
- Verifier rejects each of the nine error cases from the spec error taxonomy with the exact `error` code, and exposes
  them via the `AuthMdError` sealed family.
- Agent successfully exchanges on the happy path and surfaces typed errors on each failure path.
- Integration test runs all three example servers in-process and demonstrates discovery → mint → exchange → use.
- `dart format`, `dart analyze --fatal-infos`, and `dart test` all pass for the package.

## Out of scope (for v0.0.1)

- The **user claimed flow** (OTP-based) — add later if there is demand.
- SET/CAEP event types beyond the single `identity/assertion/revoked` event.
- Scope grammar, scope-request semantics, or scope-related UX.
- Persistent storage backends (Redis, Postgres) for replay cache or credential storage.
- A bundled trusted-provider registry; consumers configure their own `ProviderRegistry`.
- Browser/JS support — Dart VM and AOT only for v0.0.1.

## Open questions

- Should the package ship a `package:dart_authmd/shelf.dart` adapter exposing pre-built `shelf` handlers for the
  verifier? Decide after bundle 5 lands and we have hands-on feedback from `example/verifier_server.dart`.
- Should `ProviderRegistry` cache JWKS responses, or delegate caching to the caller? Default to a sensible cache (TTL =
  `Cache-Control: max-age` or 5m fallback) with an opt-out.
- The Glue integration ([./glue-integration.md](./glue-integration.md)) consumes the issuer surface in Phase 1. That
  means the issuer/verifier/agent surfaces all need to ship together rather than in sequence — there is no "deferred
  verifier" path. Adjust bundle priority if the implementation order otherwise tempts splitting them.
