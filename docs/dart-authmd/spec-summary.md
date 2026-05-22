# auth.md spec summary (agent verified flow)

This is an internalized synthesis of
the [auth.md agent-providers documentation](https://workos.com/auth-md/docs/agent-providers) and
the [ID-JAG draft](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-identity-assertion-authz-grant). The package
design in [package-plan.md](./package-plan.md) and the integration sketch
in [glue-integration.md](./glue-integration.md) reference this document as a single source of truth.

The spec defines two flows: **user claimed** (an app and a user via OTP, no agent provider involved) and **agent
verified** (an agent provider asserts a user's identity to a downstream service). This document covers only the agent
verified flow.

## Actors & responsibilities

| Actor              | Signs                | Verifies                 | Stores                                                             |
|--------------------|----------------------|--------------------------|--------------------------------------------------------------------|
| **Agent provider** | ID-JAG, logout token | —                        | Signing keys, JWKS (and optionally CIMD), audit log of delegations |
| **Agent**          | —                    | Service metadata         | The active ID-JAG and exchanged credential                         |
| **Service**        | Issued credentials   | ID-JAG signature, claims | Trusted-provider list, issued credentials, JTI replay cache        |

A user's role is implicit — the agent provider runs the consent prompt and revocation UX on behalf of the user. The
service only sees verified claims in the JWT.

## Discovery is two-hop

When an agent encounters a `401 Unauthorized` from a service, the service includes:

```
WWW-Authenticate: Bearer resource_metadata="https://api.service.com/.well-known/oauth-protected-resource"
```

### Hop 1 — Protected Resource Metadata (PRM)

Fetched from `<resource>/.well-known/oauth-protected-resource` per RFC 9728:

```json
{
  "resource": "https://api.service.com/",
  "resource_name": "Service",
  "resource_logo_uri": "https://service.com/logo.png",
  "authorization_servers": [
    "https://auth.service.com/"
  ],
  "scopes_supported": [
    "api.read",
    "api.write"
  ],
  "bearer_methods_supported": [
    "header"
  ]
}
```

### Hop 2 — Authorization Server Metadata

Fetched from `<authorization_servers[0]>/.well-known/oauth-authorization-server` per RFC 8414, extended with an
`agent_auth` block:

```json
{
  "resource": "https://api.service.com/",
  "authorization_servers": [
    "https://auth.service.com/"
  ],
  "scopes_supported": [
    "api.read",
    "api.write"
  ],
  "bearer_methods_supported": [
    "header"
  ],
  "agent_auth": {
    "skill": "https://workos.com/auth.md",
    "register_uri": "https://auth.service.com/agent/auth",
    "claim_uri": "https://auth.service.com/agent/auth/claim",
    "revocation_uri": "https://auth.service.com/agent/auth/revoke",
    "identity_types_supported": [
      "anonymous",
      "identity_assertion"
    ],
    "anonymous": {
      "credential_types_supported": [
        "api_key"
      ]
    },
    "identity_assertion": {
      "assertion_types_supported": [
        "urn:ietf:params:oauth:token-type:id-jag",
        "verified_email"
      ],
      "credential_types_supported": [
        "access_token",
        "api_key"
      ]
    },
    "events_supported": [
      "https://schemas.workos.com/events/agent/auth/identity/assertion/revoked"
    ]
  }
}
```

Services can publish an `auth.md` document that breadcrumbs back to the protected resource document; agents can also
reach the flow via service docs, SDKs, and self-documenting APIs. RFC 9728 is the canonical machine-readable path.

## ID-JAG structure

A signed JWT. The header carries a content-type marker; the payload carries the audience-scoped identity assertion.

**Header**

```json
{
  "typ": "oauth-id-jag+jwt",
  "alg": "ES256",
  "kid": "<provider key id>"
}
```

Supported `alg` values follow standard JOSE — `ES256` (recommended), `ES384`, `RS256`, `PS256`. Symmetric `HS*`
algorithms are inappropriate here and should be rejected.

**Payload — required claims**

| Claim            | Meaning                                                                 |
|------------------|-------------------------------------------------------------------------|
| `iss`            | Agent provider URL                                                      |
| `sub`            | Opaque user identifier in the provider's namespace                      |
| `aud`            | Service's authorization server URL (matches `authorization_servers[0]`) |
| `client_id`      | Provider issuer URL **or** CIMD URL                                     |
| `jti`            | Unique token identifier (used by the verifier for replay detection)     |
| `iat`            | Issuance time (epoch seconds)                                           |
| `exp`            | Expiry (recommended `iat + 5m`)                                         |
| `email`          | Verified email of the user                                              |
| `email_verified` | `true`                                                                  |

(Either `email`+`email_verified=true` or `phone_number`+`phone_number_verified=true` is required — the service rejects
the token if neither verified contact is present.)

**Payload — optional claims**

| Claim                   | Meaning                                            |
|-------------------------|----------------------------------------------------|
| `amr`                   | Authentication methods, e.g. `["mfa"]`             |
| `auth_time`             | Original user-authentication time                  |
| `name`                  | Full name                                          |
| `phone_number`          | E.164 phone                                        |
| `phone_number_verified` | Boolean                                            |
| `resource`              | The specific resource being granted access to      |
| `agent_platform`        | Free-form provider identifier (e.g. `claude-code`) |
| `agent_context_id`      | Conversation/session ID — useful for audit         |

## CIMD — Client ID Metadata Document

A
CIMD ([draft-ietf-oauth-client-id-metadata-document](https://datatracker.ietf.org/doc/draft-ietf-oauth-client-id-metadata-document/))
is an optional, agent-provider-hosted JSON document whose URL is used as the `client_id` value in the ID-JAG. Example:

```json
{
  "client_id": "https://api.agent-provider.com/agent-auth.json",
  "client_name": "Agent Provider",
  "logo_uri": "https://agent-provider.com/logo.png",
  "client_uri": "https://agent-provider.com",
  "tos_uri": "https://agent-provider.com/tos",
  "policy_uri": "https://agent-provider.com/privacy",
  "token_endpoint_auth_method": "private_key_jwt",
  "jwks_uri": "https://agent-provider.com/.well-known/jwks.json",
  "scope": "openid email profile"
}
```

Adopt CIMD when:

- You expect to rotate signing keys without churning every consumer's trust list.
- You want to list your provider in a trusted-provider registry where the listing's identity is the CIMD URL rather than
  your raw issuer URL.

Otherwise, `client_id` can simply be the issuer URL and the verifier fetches JWKS from a `.well-known/jwks.json` derived
from that.

## Exchange protocol

Once the ID-JAG is minted, the agent POSTs it to the service's `register_uri` (typically `/agent/auth`):

```http
POST /agent/auth HTTP/1.1
Host: auth.service.com
Content-Type: application/json

{
  "type": "identity_assertion",
  "assertion_type": "urn:ietf:params:oauth:token-type:id-jag",
  "assertion": "eyJhbGc...",
  "requested_credential_type": "access_token"
}
```

The service supports two response shapes depending on `requested_credential_type`.

**`access_token` response**

```json
{
  "registration_id": "reg_...",
  "registration_type": "agent-provider",
  "credential_type": "access_token",
  "credential": "<token>",
  "credential_expires": "2026-05-04T13:00:00.000Z",
  "scopes": [
    "api.read",
    "api.write"
  ]
}
```

**`api_key` response**

```json
{
  "registration_id": "reg_...",
  "registration_type": "agent-provider",
  "credential_type": "api_key",
  "credential": "sk_live_...",
  "credential_expires": null,
  "scopes": [
    "api.read",
    "api.write"
  ]
}
```

Access tokens issued from ID-JAG verification **do not include a refresh token**. To extend access, the agent presents a
fresh ID-JAG. This keeps the agent provider on the critical path for every delegated session — the same property that
gives the user a single revocation UX.

## Error taxonomy

All exchange and revocation failures return a JSON body of the shape `{ "error": "<code>", "message": "..." }`.

| Error code                         | Meaning                                                                  |
|------------------------------------|--------------------------------------------------------------------------|
| `invalid_issuer`                   | Token `iss` isn't in the service's trusted providers list.               |
| `invalid_signature`                | JWKS lookup failed or the signature didn't verify against any known key. |
| `expired`                          | `exp` is in the past.                                                    |
| `replay_detected`                  | `jti` has already been seen within the replay window.                    |
| `invalid_audience`                 | `aud` doesn't match the service's auth server.                           |
| `invalid_client_id`                | `client_id` doesn't resolve to a known provider identity.                |
| `missing_verified_email`           | Neither `email_verified` nor `phone_number_verified` is true.            |
| `unsupported_credential_type`      | Requested credential type isn't offered by the service.                  |
| `insufficient_user_authentication` | Auth context didn't meet policy (RFC 9470 pattern).                      |

## Revocation

The user's control plane (inside the agent provider's product) triggers revocation by POSTing a logout token to the
service's `revocation_uri`:

```http
POST /agent/auth/revoke HTTP/1.1
Host: auth.service.com
Content-Type: application/logout+jwt

{
  "typ": "logout+jwt",
  "alg": "ES256",
  "kid": "<provider key id>"
}
.
{
  "iss": "https://api.agent-provider.com",
  "sub": "<opaque user identifier>",
  "aud": "https://auth.service.com",
  "jti": "<unique identifier to prevent replay>",
  "iat": <epoch seconds>,
  "events": {
    "https://schemas.workos.com/events/agent/auth/identity/assertion/revoked": {}
  }
}
```

The service invalidates the credentials associated with the affected `(iss, sub)` or `registration_id`. The `events`
claim follows [RFC 8417 Security Event Token (SET)](https://datatracker.ietf.org/doc/html/rfc8417) shape; the spec
anticipates extending this surface with [OpenID CAEP](https://openid.net/specs/openid-caep-1_0-final.html) for
session-change events beyond pure revocation (e.g. step-up auth required, session terminated), delivered via webhook or
SSE.

## Trust model

Services maintain a list of trusted agent providers, identified by their issuer URL or CIMD URL. On exchange:

1. Match an existing customer by `(iss, sub)` first.
2. If unmatched, match by verified contact (`email_verified` or `phone_number_verified`) and JIT-provision a user.
3. If neither match nor verified contact is available, reject with `missing_verified_email`.

The service then mints a credential of the requested type and returns it. There is no requirement that the user already
exist — the verified contact channel is enough for JIT provisioning and for sending the user a "claim this account"
message later if they show up directly.

## What the spec does *not* cover

- **User claimed flow** — out of scope for this directory. The standalone Dart package may add support later, but the
  agent verified flow is the priority because that's the one Glue needs.
- **Session-change events beyond revocation** — anticipated via CAEP but not yet specified.
- **Scope negotiation semantics** — services advertise `scopes_supported`, but neither the exchange request nor the
  response has a formal scope-request shape; today this is implicit per credential type.
- **Persistent storage shapes** — replay cache, credential storage, audit log are left to the implementer.
