# Gemini Provider Authentication Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-21

## Goal

Add Gemini support to Glue without collapsing multiple incompatible Google auth
systems into one vague "gemini" bucket.

This plan investigates:

- how Gemini CLI authenticates
- whether Glue should copy that behavior
- whether Gemini API key and Google-login flows belong under one provider or
  two
- what OpenCode does in practice
- how this should fit Glue's existing provider-adapter and `/provider add`
  architecture, especially the Copilot precedent

## Executive Summary

The short version:

1. **Gemini CLI is not just "Gemini API with OAuth".**
   Its recommended "Sign in with Google" path authenticates against Google's
   **Code Assist / Gemini-for-Cloud** stack, not the plain Gemini Developer API.

2. **There are at least three materially different auth modes we could support:**
   - **Gemini Developer API key** (`GEMINI_API_KEY`) via `ai.google.dev`
   - **Google account login / Gemini CLI-style OAuth** leading to Code Assist
     access and quota behavior
   - **Vertex AI** using `GOOGLE_API_KEY`, ADC, or service-account credentials

3. **These should not be silently merged into one provider unless Glue has a
   very explicit auth-mode model.** If we pretend they are the same provider,
   we will create confusing validation, storage, model availability, quota,
   and troubleshooting behavior.

4. **The safest first implementation is not the OAuth flow.**
   The safest first implementation is:
   - `gemini` provider = Gemini Developer API key
   - optionally later `gemini-code-assist` (or similar) = Google login
   - optionally later `vertex` = Vertex AI

5. **If we do support Gemini CLI-style Google login, we should model it like
   Copilot in structure, but not in protocol.** Copilot uses device code and a
   small stable token exchange. Gemini CLI uses browser-based OAuth/loopback,
   cached Google credentials, and then a separate Code Assist onboarding/
   project-selection layer.

## Why a Single "gemini" Provider Is Ambiguous

The phrase "Gemini" currently hides multiple products:

### 1. Gemini Developer API

This is the `ai.google.dev` / Google AI Studio path.

Characteristics:

- auth is usually `GEMINI_API_KEY`
- direct model API usage
- no Google-account browser login required
- simple fit for Glue's existing `AuthKind.apiKey`
- conceptually similar to OpenAI/Anthropic/Groq API-key providers

### 2. Gemini CLI Google Login / Code Assist

This is what Gemini CLI recommends for most local users.

Characteristics:

- browser-based Google OAuth
- credentials cached locally
- for some accounts, requires `GOOGLE_CLOUD_PROJECT`
- requests are routed through Google's Code Assist / Gemini-for-Cloud path,
  not the plain developer API
- account tier, project onboarding, and quota behavior differ from API-key mode
- not a simple `Authorization: Bearer <google-oauth-access-token>` drop-in for
  the Gemini Developer API

### 3. Vertex AI

This is the Google Cloud path.

Characteristics:

- can use ADC via `gcloud auth application-default login`
- can use service-account JSON
- can use `GOOGLE_API_KEY`
- requires `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION` in normal cases
- different endpoint semantics and org constraints

These are different enough that collapsing them into one provider would be a
bad abstraction unless we first introduce explicit per-provider auth modes with
mode-specific validation, docs, and stored credential schemas.

## What Gemini CLI Actually Does

From the public Gemini CLI docs and source:

### Auth modes exposed by Gemini CLI

Gemini CLI exposes these auth types:

- `LOGIN_WITH_GOOGLE` (`oauth-personal`)
- `USE_GEMINI` (`gemini-api-key`)
- `USE_VERTEX_AI` (`vertex-ai`)
- `COMPUTE_ADC`

### For Google login, Gemini CLI does not use the plain Gemini API path

Source inspection shows:

- `LOGIN_WITH_GOOGLE` and `COMPUTE_ADC` call `createCodeAssistContentGenerator`
- that calls `getOauthClient(...)`
- then `setupUser(...)`
- then constructs a `CodeAssistServer`

That means the login flow is tied to **Code Assist onboarding and project
resolution**, not just obtaining an OAuth access token and calling the regular
Gemini REST API.

### OAuth details in Gemini CLI

Gemini CLI's Google-login implementation uses:

- `google-auth-library`
- browser flow with local loopback callback on `127.0.0.1:<port>`
- fallback manual auth-code flow when browser launch is suppressed
- cached credentials in `~/.gemini/oauth_creds.json` or encrypted storage
- user-info fetch to cache the Google account email

Important implementation details:

- it uses a fixed Google OAuth client id and secret from Gemini CLI
- scopes include:
  - `cloud-platform`
  - `userinfo.email`
  - `userinfo.profile`
- after auth, it runs Code Assist setup logic to determine project/tier access
- some account types require `GOOGLE_CLOUD_PROJECT`
- quota/tier handling is Code Assist-specific

### Project onboarding matters

Gemini CLI's `setupUser()` does more than validate a token:

- calls `loadCodeAssist`
- handles validation-required responses
- determines current/allowed tiers
- may onboard the user
- resolves/creates the project used for requests
- throws project-required errors when org-backed accounts need one

This is a huge sign that copying only the OAuth step is insufficient. The real
behavior lives in the Code Assist backend semantics after login.

## Comparison With Copilot Integration In Glue

Glue already has a good example of an OAuth-ish provider: Copilot.

### What Copilot looks like in Glue today

Current behavior:

- catalog provider uses `AuthKind.oauth`
- adapter overrides `beginInteractiveAuth`
- flow is `DeviceCodeFlow`
- success stores provider-specific fields in credentials.json:
  - `github_token`
  - `copilot_token`
  - `copilot_token_expires_at`
- runtime refresh logic exchanges GitHub token for short-lived Copilot token

This is clean because:

- the auth surface is self-contained
- provider runtime uses a stable token exchange contract
- provider identity and auth identity are effectively the same thing

### Why Gemini login is harder than Copilot

Gemini CLI-style login adds complexity Copilot does not have:

- browser/loopback flow instead of device code
- Google OAuth client behavior
- credential caching semantics
- account-type-dependent project requirements
- Code Assist onboarding
- quota/tier logic coupled to the auth path
- potentially different model availability than API-key Gemini

So yes, it is **similar to Copilot structurally** in the sense that Glue should
let the adapter drive interactive auth and store provider-specific fields.
But no, it is **not similar enough** that we should treat it as "just another
OAuth provider" and cram it into the same mental model without naming the
product boundary.

## What OpenCode Appears To Do

OpenCode itself does not appear to ship first-party Gemini Google-login support
in the same way Glue ships Copilot support. Instead, there are third-party
plugins that add Google/Gemini OAuth behavior.

The most relevant signal is not the exact plugin code but the ecosystem shape:

- people built a **separate plugin** for Gemini Google auth
- plugin README files explicitly warn that using Gemini CLI OAuth in third-party
  software may violate Google's policy or trigger abuse detection
- plugin docs distinguish Google-login usage from API-key usage
- plugin docs often require project configuration for org-backed accounts
- plugin authors describe themselves as mirroring Gemini CLI's OAuth + Code
  Assist flow, not the plain Gemini Developer API

This matters because it confirms the abstraction boundary:

- the ecosystem treats this as a special integration
- it is risky enough that plugin authors put warnings at the top
- it is not being treated as just another standard AI SDK API-key provider

## Policy / Risk Considerations

This is the biggest reason not to rush the Google-login path.

At least one OpenCode Gemini-auth plugin prominently warns that Google has
stated Gemini CLI OAuth use in third-party software is a policy-violating use
case and may trigger abuse detection or account restrictions.

Whether that warning is perfectly precise is almost secondary. The practical
point is:

- **there is real compliance/product risk here**
- Glue should not quietly ship this as if it were equivalent to supported
  API-key auth
- if we implement it, it likely needs:
  - explicit user opt-in
  - warning text in `/provider add`
  - docs explaining this is unofficial / higher risk
  - probably a separate provider id so users understand what they are choosing

If we skip that and present a single friendly "gemini" provider, we're lying by
omission.

## Recommended Provider Model

### Option A — one `gemini` provider with multiple auth modes

Example:

- provider id: `gemini`
- auth modes:
  - API key
  - Google login
  - Vertex

#### Pros

- one provider id for users
- model ids stay stable
- long-term maybe cleaner if auth-mode infrastructure becomes rich enough

#### Cons

- Glue does not currently have a first-class auth-mode layer for one provider
- validation and `/provider add` UI become more complex immediately
- stored credentials schema becomes mode-dependent
- model availability can differ by mode
- troubleshooting gets ugly: "Gemini connected" means what, exactly?
- high risk of papering over product differences

### Option B — split providers by auth/product boundary

Example:

- `gemini` = Gemini Developer API key
- `gemini-code-assist` = Gemini CLI-style Google login
- `vertex` = Vertex AI

#### Pros

- matches actual backend/product differences
- simplest fit for Glue's current provider architecture
- clear auth UX
- clear credential storage per provider
- clear docs and troubleshooting
- lets us ship API-key Gemini first without committing to riskier OAuth support

#### Cons

- duplicate model lists unless we introduce shared model groups
- users must understand which Google product they want
- some model ids may overlap conceptually across providers

### Recommendation

**Choose Option B.**

At least for the first implementation, splitting providers is the least bad
choice. One-provider-many-modes is a future refactor if we later add a proper
provider auth-mode abstraction.

## Recommended Scope

### Phase 1 — ship the boring part first

Implement:

- `gemini` provider using `AuthKind.apiKey`
- adapter that talks to Gemini Developer API
- env var: `GEMINI_API_KEY`
- `/provider add gemini` uses existing `ApiKeyFlow`

Do **not** implement Google login in the same pass.

Why:

- lowest engineering risk
- lowest policy risk
- fits Glue today
- unblocks actual Gemini model support quickly

### Phase 2 — optional explicit Google-login provider

Add a separate provider, tentatively:

- `gemini-code-assist`

Implement:

- `AuthKind.oauth`
- adapter-owned browser/PKCE/loopback flow
- provider-specific stored fields, likely something like:
  - `refresh_token` or serialized Google credential blob
  - cached account email
  - project id
  - maybe tier metadata
- runtime Code Assist client
- explicit warning that this path is unofficial/riskier than API-key auth

### Phase 3 — optional Vertex provider

Add:

- `vertex`

Likely not through `/provider add` initially. Better as config/env-driven setup
because Vertex commonly relies on:

- ADC
- service-account JSON
- `GOOGLE_CLOUD_PROJECT`
- `GOOGLE_CLOUD_LOCATION`

Trying to jam that into today's `/provider add` flow is probably overkill.

## Required Glue Architecture Changes For Google Login

If we do Phase 2 later, these are the minimum architectural needs.

### 1. Add PKCE / browser-loopback auth flow support

Current Glue auth flow types:

- `ApiKeyFlow`
- `DeviceCodeFlow`
- `PkceFlow` scaffold only

The `PkceFlow` scaffold exists but is not implemented. Gemini Google login is
our first real use case.

Needed work:

- browser launch helper
- local callback server on loopback port
- state verification
- timeout/cancel behavior
- fallback manual code paste path for headless/no-browser cases
- UI states comparable to current device flow UX

### 2. Decide credential storage shape

Do not store this as a single `api_key` string. That would be fake.

Need provider-specific fields, likely one of:

#### Option 2A: raw Google credential blob

Store the relevant authorized-user credentials as JSON-ish fields under
`providers.gemini-code-assist`.

Pros:

- closest to Gemini CLI
- easiest parity with refresh behavior

Cons:

- more sensitive credential material in Glue's credentials store
- requires careful schema/versioning

#### Option 2B: minimal extracted fields

Store only what Glue needs, for example:

- `refresh_token`
- `account_email`
- `project_id`

Pros:

- cleaner schema
- less junk

Cons:

- must reimplement more of the Google auth-client setup carefully

Recommendation: prefer **minimal extracted fields** if feasible, but only if we
can prove we are not fighting the Google auth libraries. Otherwise store a
small structured credential object and version it explicitly.

### 3. Add a Code Assist runtime client, not just a Gemini API client

If we implement Google login by copying Gemini CLI semantics, Glue needs a
runtime client for the Code Assist backend.

That is a separate adapter/client concern from Gemini Developer API.

Needed capabilities:

- use Google-auth credentials
- handle project selection
- call Code Assist endpoints
- handle quota/tier errors distinctly
- possibly fallback/remediation messages for validation-required states

### 4. Add provider-specific warnings in UI/docs

For `gemini-code-assist`, `/provider add` should not look like a normal happy
path. It should probably say something like:

- uses Google account login rather than Gemini API keys
- may require a Google Cloud project for work/school/org accounts
- may be subject to Google policy limitations for third-party clients

If we are unwilling to say that in the product, we probably should not ship it.

## Catalog Recommendations

### Initial catalog

Add at least:

- `gemini` provider
with adapter either:
- `gemini` if we implement a native Gemini adapter
- or `openai` only if we were proxying through an OpenAI-compatible endpoint
  (which we are not)

So realistically this means adding a **native Gemini adapter**.

That adapter should cover the Gemini Developer API key path.

### Later catalog additions

If Phase 2 happens:

- add `gemini-code-assist` provider
- reuse the same or similar model IDs if the runtime supports them
- keep docs explicit about auth differences

If Phase 3 happens:

- add `vertex` provider

## Implementation Plan

### Phase 1 — Gemini Developer API key

1. **Add native Gemini adapter**
   - request/response mapping for chat/tool calls
   - streaming support
   - auth via `GEMINI_API_KEY`

2. **Add catalog provider entry**
   - id: `gemini`
   - auth: `api_key`
   - env var: `GEMINI_API_KEY`
   - docs URL: Gemini API docs

3. **Add curated Gemini models**
   - start small; do not mirror the full Google catalog
   - include only coding/tool-capable chat models we actually want users to see

4. **Wire service locator / adapter registry**
   - register `GeminiAdapter`

5. **Tests**
   - adapter validate behavior
   - client request shape
   - `/provider add gemini` api-key flow
   - config resolution

### Phase 2 — Gemini Code Assist / Google login

1. **Implement real `PkceFlow` support in Glue UI/runtime**
2. **Add Google-login adapter/client**
3. **Add credential storage schema for Google auth**
4. **Add Code Assist onboarding/project logic**
5. **Add explicit warning UX and docs**
6. **Add provider entry `gemini-code-assist`**
7. **Tests**
   - auth flow state handling
   - callback server behavior
   - credential persistence
   - project-required errors
   - config/runtime validation

### Phase 3 — Vertex AI

1. Add provider entry `vertex`
2. Decide env/config-only support vs interactive support
3. Implement validation around project/location/ADC
4. Add tests

## Open Questions / Ambiguities To Resolve Before Coding

### 1. Do we actually want unofficial Gemini CLI OAuth support?

This is the first question, not an implementation detail.

Because if Google's stance is effectively "don't do this in third-party apps",
then implementing it may be a bad product decision even if it's technically
possible.

### 2. Is the desired user story API billing or subscription reuse?

These are different products:

- API key path = clear BYOK billing
- Google login path = attempt to reuse Gemini/Gemini Code Assist entitlements

If the real goal is "I want Gemini models in Glue", Phase 1 solves it.
If the real goal is "I want to reuse my Google/Gemini subscription in Glue",
that pushes us toward the riskier Code Assist path.

### 3. Should `gemini-code-assist` be hidden/experimental?

Probably yes, at least initially.

### 4. Do we need a generalized provider-auth-mode abstraction first?

Probably not for Phase 1.
Maybe for long-term unification, but introducing that now smells like yak
shaving.

### 5. How much of Gemini CLI parity do we need?

We should not blindly chase full parity. The useful parity target is:

- same broad auth behavior
- same project requirement semantics
- same rough credential lifecycle

Not:

- every experiment flag
- every telemetry feature
- every fallback path
- every admin control hook

## Recommended Decision

**Recommended product decision:**

1. **Implement Gemini Developer API first** as `gemini` using API key auth.
2. **Do not ship Google-login support in the first Gemini PR.**
3. If the team explicitly wants subscription/Code Assist reuse, implement it as
   a separate provider such as `gemini-code-assist`, marked experimental and
   documented as higher risk.
4. Treat **Vertex AI as a separate provider** rather than a hidden auth mode of
   `gemini`.

That gives Glue a clean provider story:

- `gemini` = Gemini Developer API
- `gemini-code-assist` = Google-login Code Assist path
- `vertex` = Google Cloud Vertex AI

Anything else is likely to turn into a confusing mess.

## Concrete Next Step

Before implementation, decide one of these explicitly:

### Decision A — conservative

> We only want officially supportable Gemini integration right now.

Then implement only:

- native `gemini` adapter
- API key auth
- curated models

### Decision B — experimental expansion

> We explicitly want unofficial Google-login support to reuse Gemini/GCA quota.

Then create a follow-up design/implementation task specifically for:

- `gemini-code-assist`
- PKCE/loopback auth flow
- Code Assist runtime client
- warning UX
- credential schema

Do not combine A and B into one vague provider ticket. That is how this gets
implemented badly.
