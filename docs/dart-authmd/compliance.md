# dart_authmd — spec compliance matrix

This document tracks which auth.md requirements the `dart_authmd` package covers, deferred, or explicitly excludes. It
is the truth source for spec conformance and the artifact to update when the underlying drafts move.

**Status legend**

- **MVP** — in scope for `v0.0.1` (see [package-plan.md](./package-plan.md) bundles 1–8).
- **Later** — planned for a subsequent release.
- **Out of scope** — not planned. Consumers can layer it on top.

Spec source: [./spec-summary.md](./spec-summary.md). Tests live under `packages/dart_authmd/test/` once the package is
created; the table below uses the planned test paths.

## Discovery — RFC 9728 + RFC 8414 + `agent_auth` extension

| Spec requirement                                                                              | Package surface                                      | Status       | Test reference                               |
|-----------------------------------------------------------------------------------------------|------------------------------------------------------|--------------|----------------------------------------------|
| Parse PRM at `<resource>/.well-known/oauth-protected-resource`                                | `agent.dart` → `PrmDiscovery.fetch`                  | MVP          | `test/agent/prm_discovery_test.dart`         |
| Parse AS metadata at `<authorization_servers[0]>/.well-known/oauth-authorization-server`      | `agent.dart` → `PrmDiscovery.fetch`                  | MVP          | `test/agent/prm_discovery_test.dart`         |
| Parse the `agent_auth` block (`register_uri`, `claim_uri`, `revocation_uri`, supported types) | `dart_authmd.dart` → `AgentAuthMetadata`             | MVP          | `test/core/metadata_serialization_test.dart` |
| Parse `WWW-Authenticate: Bearer resource_metadata="..."` on 401                               | `agent.dart` → `WwwAuthenticate.parse`               | MVP          | `test/agent/www_authenticate_test.dart`      |
| Discover via service-published `auth.md` breadcrumb document                                  | Not implemented; RFC 9728 path is the canonical hook | Out of scope | —                                            |
| Cache PRM / AS metadata with `Cache-Control: max-age`                                         | `agent.dart` → `PrmDiscovery` internal cache         | MVP          | `test/agent/prm_discovery_test.dart`         |

## ID-JAG claims — required & optional

| Spec requirement                                                                      | Package surface                                      | Status | Test reference                                                                   |
|---------------------------------------------------------------------------------------|------------------------------------------------------|--------|----------------------------------------------------------------------------------|
| Header `typ: oauth-id-jag+jwt` enforced on mint and verify                            | `core/jose/jwt_codec.dart`                           | MVP    | `test/issuer/id_jag_issuer_test.dart`, `test/verifier/id_jag_verifier_test.dart` |
| Required claims (`iss`, `sub`, `aud`, `client_id`, `jti`, `iat`, `exp`)               | `core/claims.dart` → `IdJagClaims`                   | MVP    | `test/core/claims_serialization_test.dart`                                       |
| At least one of `email_verified` or `phone_number_verified` is `true`                 | `verifier.dart` → `IdJagVerifier` pipeline           | MVP    | `test/verifier/id_jag_verifier_test.dart` (`missing_verified_email` case)        |
| Optional `amr`, `auth_time`, `name`, `resource`, `agent_platform`, `agent_context_id` | `core/claims.dart` → `IdJagClaims` (nullable fields) | MVP    | `test/core/claims_serialization_test.dart`                                       |
| Recommended `exp = iat + 5m`                                                          | `issuer.dart` → `IdJagIssuer(tokenLifetime:)`        | MVP    | `test/issuer/id_jag_issuer_test.dart`                                            |
| Supported `alg`: `ES256` (default), `ES384`, `RS256`, `PS256`                         | `core/jose/jwt_codec.dart` allow-list                | MVP    | `test/issuer/id_jag_issuer_test.dart`                                            |
| Reject `alg: none` and `HS*`                                                          | `core/jose/jwt_codec.dart` reject-list               | MVP    | `test/verifier/id_jag_verifier_test.dart`                                        |

## CIMD — Client ID Metadata Document

| Spec requirement                                                 | Package surface                                                 | Status       | Test reference                              |
|------------------------------------------------------------------|-----------------------------------------------------------------|--------------|---------------------------------------------|
| Issue a CIMD document and host it at a stable URL                | `issuer.dart` → `CimdDocument`                                  | MVP          | `test/issuer/cimd_test.dart`                |
| Verifier resolves `client_id` to a CIMD when it looks like a URL | `verifier.dart` → `ProviderRegistry` (CIMD fetch)               | MVP          | `test/verifier/provider_registry_test.dart` |
| Verifier resolves `client_id` to issuer URL otherwise            | `verifier.dart` → `ProviderRegistry`                            | MVP          | `test/verifier/provider_registry_test.dart` |
| Use `private_key_jwt` for client auth at the AS                  | Out of scope — not exercised in the agent-verified flow we ship | Out of scope | —                                           |

## Exchange protocol — `POST /agent/auth`

| Spec requirement                                                                        | Package surface                                                  | Status       | Test reference                             |
|-----------------------------------------------------------------------------------------|------------------------------------------------------------------|--------------|--------------------------------------------|
| Request body shape (`type`, `assertion_type`, `assertion`, `requested_credential_type`) | `agent.dart` → `CredentialExchange.exchange`                     | MVP          | `test/agent/credential_exchange_test.dart` |
| Response shape for `access_token` (includes `credential_expires`, `scopes`)             | `core/claims.dart` → `AgentAuthCredential`                       | MVP          | `test/agent/credential_exchange_test.dart` |
| Response shape for `api_key` (`credential_expires: null`)                               | `core/claims.dart` → `AgentAuthCredential`                       | MVP          | `test/agent/credential_exchange_test.dart` |
| No refresh token; re-mint a fresh ID-JAG to extend                                      | Documented in `agent.dart` dartdoc; no refresh API exposed       | MVP          | (doc-only)                                 |
| `identity_assertion` request type                                                       | `agent.dart`                                                     | MVP          | `test/agent/credential_exchange_test.dart` |
| `anonymous` request type (api_key only)                                                 | `agent.dart` accepts but no flow scaffolded                      | Later        | —                                          |
| Scope negotiation (request-side scope grammar)                                          | Not implemented — service uses its advertised `scopes_supported` | Out of scope | —                                          |

## Error taxonomy

Each row maps to a typed `AuthMdError` variant; the variant carries the `error` code byte-for-byte from the spec.

| Spec error code                    | Package surface                                                                                   | Status | Test reference                              |
|------------------------------------|---------------------------------------------------------------------------------------------------|--------|---------------------------------------------|
| `invalid_issuer`                   | `verifier.dart` step 2                                                                            | MVP    | `test/verifier/id_jag_verifier_test.dart`   |
| `invalid_signature`                | `verifier.dart` step 4                                                                            | MVP    | `test/verifier/id_jag_verifier_test.dart`   |
| `expired`                          | `verifier.dart` step 6                                                                            | MVP    | `test/verifier/id_jag_verifier_test.dart`   |
| `replay_detected`                  | `verifier.dart` step 8                                                                            | MVP    | `test/verifier/id_jag_verifier_test.dart`   |
| `invalid_audience`                 | `verifier.dart` step 5                                                                            | MVP    | `test/verifier/id_jag_verifier_test.dart`   |
| `invalid_client_id`                | `verifier.dart` step 3                                                                            | MVP    | `test/verifier/id_jag_verifier_test.dart`   |
| `missing_verified_email`           | `verifier.dart` step 7                                                                            | MVP    | `test/verifier/id_jag_verifier_test.dart`   |
| `unsupported_credential_type`      | Returned by `CredentialIssuer`                                                                    | MVP    | `test/verifier/credential_issuer_test.dart` |
| `insufficient_user_authentication` | Surfaced by `AuthMdError`; pipeline does not enforce policy itself (consumer-provided check hook) | MVP    | `test/verifier/id_jag_verifier_test.dart`   |

## Revocation

| Spec requirement                                                                          | Package surface                                             | Status       | Test reference                              |
|-------------------------------------------------------------------------------------------|-------------------------------------------------------------|--------------|---------------------------------------------|
| Issuer mints `typ: logout+jwt` with `events` envelope                                     | `issuer.dart` → `LogoutTokenIssuer`                         | MVP          | `test/issuer/logout_token_issuer_test.dart` |
| Verifier accepts logout token via `RevocationAcceptor.verify`                             | `verifier.dart` → `RevocationAcceptor`                      | MVP          | `test/verifier/revocation_test.dart`        |
| `Content-Type: application/logout+jwt` on the POST                                        | `agent.dart` does not yet send revocations (issuer concern) | MVP          | `test/issuer/logout_token_issuer_test.dart` |
| SET (`urn:ietf:params:secevent:event-type:*`) catalog beyond `identity/assertion/revoked` | Single event constant exposed; others added on demand       | Later        | —                                           |
| CAEP session-change events (step-up, session terminated)                                  | —                                                           | Later        | —                                           |
| Webhook / SSE delivery of session-change events                                           | —                                                           | Out of scope | —                                           |

## Trust model

| Spec requirement                                  | Package surface                                                   | Status | Test reference                              |
|---------------------------------------------------|-------------------------------------------------------------------|--------|---------------------------------------------|
| Match user by `(iss, sub)` first                  | `verifier.dart` exposes claims; matching is consumer's job        | MVP    | (consumer test territory)                   |
| JIT-provision from verified contact when no match | Verifier surfaces verified contact in claims; consumer provisions | MVP    | (consumer test territory)                   |
| Reject when no match and no verified contact      | `verifier.dart` step 7 (`missing_verified_email`)                 | MVP    | `test/verifier/id_jag_verifier_test.dart`   |
| Trusted-provider registry semantics               | `verifier.dart` → `ProviderRegistry` interface + `Static…` impl   | MVP    | `test/verifier/provider_registry_test.dart` |

## Out of scope (explicit)

- **User claimed flow.** This package covers only the agent-verified flow. If demand emerges, ship as a separate
  top-level library (`package:dart_authmd/user_claimed.dart`).
- **Browser / JS targets.** Dart VM + AOT only for v0.0.1.
- **Persistent backends** for replay cache, credential storage, audit logs.
- **A bundled trusted-provider registry.** Consumers configure their own; the package will not ship an opinionated list
  of "trusted" agent providers.
- **Server-side scope grammar.** Services advertise their scopes; we do not invent a request-side scope DSL.
