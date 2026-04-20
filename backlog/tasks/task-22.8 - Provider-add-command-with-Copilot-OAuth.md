---
id: TASK-22.8
title: /provider add command with Copilot OAuth
status: In Review
assignee: []
created_date: "2026-04-19 12:00"
updated_date: "2026-04-20 00:09"
labels:
  - model-provider-2026-04
  - commands
  - oauth
  - ui
dependencies:
  - TASK-22.3
  - TASK-22.4
documentation:
  - docs/plans/2026-04-19-responsive-panels.md
parent_task_id: TASK-22
priority: high
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Close the credential-onboarding gap. After MP3–7 shipped, users with no API key set hit a dead-end error ("run `glue credentials set anthropic`") pointing at a command that doesn't exist. Add an in-app flow and extend it to OAuth so GitHub Copilot works end-to-end.

**Research-backed decisions:**

- Only `/provider` is user-facing. The word "credentials" and "auth" do not appear in UI copy — users "add a provider", not "configure credentials".
- One real OAuth provider ships: **GitHub Copilot device-code flow** (simpler than PKCE, no loopback server).
- Claude Pro / ChatGPT-subscription OAuth explicitly excluded (Anthropic TOS risk — OpenCode removed it in v1.3.0).
- Gemini PKCE scaffolded but not implemented.

**Scope:**

1. **Data model**
   - `AuthKind` becomes `{apiKey, oauth, none}` (drops `env`/`prompt`).
   - `AuthSpec` gains `helpUrl`.
   - New sealed `AuthFlow` hierarchy (`ApiKeyFlow`, `DeviceCodeFlow`, scaffolded `PkceFlow`) with `AuthFlowProgress` stream.
   - `ProviderAdapter` gains `beginInteractiveAuth(provider)` returning `AuthFlow?`.

2. **CredentialStore**
   - Add `setFields(providerId, Map<String, String>)` and `getField(providerId, fieldName)`.
   - `setApiKey` kept as convenience.
   - Storage JSON shape unchanged — already generic map.

3. **CopilotAdapter** (new third adapter alongside anthropic + openai)
   - Device code flow against `github.com/login/device/code` with client_id `Iv1.b507a08c87ecfe98`.
   - Exchange GitHub token for short-lived Copilot token via `api.github.com/copilot_internal/v2/token`.
   - `CopilotClient` composes `OpenAiClient` with custom headers: `Authorization: Bearer <copilot_token>`, `Copilot-Integration-Id: vscode-chat`, `Editor-Version: Glue/<ver>`.
   - Token refresh helper: `copilot_token_manager.dart` re-exchanges on expiry check.

4. **TUI panels**
   - `ApiKeyPromptPanel`: single masked input + help URL + env-prefill hint.
   - `DeviceCodePanel`: shows URL + user code (auto-copied), spinner while polling, "Connected as …" on success.

5. **Slash commands** — only `/provider`
   - `/provider` or `/provider list` — table: provider · status · auth kind · source.
   - `/provider add [<id>]` — picker if no id; API-key modal or device-code panel by `auth.kind`.
   - `/provider remove <id>` — confirm + clear stored fields.
   - `/provider test <id>` — run `adapter.validate(resolved)`, no HTTP.

6. **Catalog** — add `copilot` entry in `docs/reference/models.yaml` with `adapter: copilot`, device-code auth, and initial model set (claude-sonnet-4.6, gpt-4.1).

7. **Error wording** — `GlueConfig.validate()` points at `/provider add <id>`.

**Out of scope:**

- Claude Pro / ChatGPT OAuth (TOS risk).
- Gemini PKCE implementation (`PkceFlow` scaffolded only).
- OS keychain.
- Multi-field API-key forms (Azure, Bedrock, OpenAI org-id interactive UI). `setFields` makes them cheap to add later.
- First-launch wizard.

**Plan document:** `/Users/helge/.claude/plans/lets-plan-out-the-goofy-scroll.md`

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [x] #1 `/provider add anthropic` with no env opens masked input modal, stores on submit, reports "Connected". (panel_controller.\_runApiKeyFlow)
- [x] #2 `/provider add copilot` shows device URL + user code, polls, exchanges for Copilot token, stores all three fields. (panel_controller.\_runDeviceCodeFlow + CopilotAdapter)
- [x] #3 Copilot token refreshes automatically when stored `copilot_token_expires_at` is past. (copilot_token_manager.freshCopilotToken — `copilot_token_manager_test`)
- [x] #4 Copilot request carries `Copilot-Integration-Id: vscode-chat` + `Editor-Version: Glue/<ver>` headers. (\_CopilotClient.stream injects via extraHeaders)
- [x] #5 `/provider list` renders table with status per provider (connected / missing / no-auth). (\_formatProviderList)
- [x] #6 `/provider remove <id>` clears stored fields; notes if env var is still set. (\_providerRemove)
- [x] #7 `/provider test <id>` runs `adapter.validate` without HTTP or side effects. (\_providerTest)
- [x] #8 Word "credentials" / "auth" does not appear in any user-visible string.
- [x] #9 `GlueConfig.validate()` error message references `/provider add <id>`, not a legacy command.
- [x] #10 Claude Pro / ChatGPT-subscription OAuth is NOT shipped.
- [x] #11 Tests: `auth_flow` (6), `credential_store` (multi-field), `copilot_token_manager` (6), `copilot_adapter` (5), `provider_adapter_auth` (7), `provider_command` (1). `dart test` + `dart analyze --fatal-infos` green (1208 tests).
- [ ] #12 Manual verification: `./glue` → `/provider add copilot` → browser approval → `--model copilot/claude-sonnet-4.6 "hi"` responds. _(not yet run — needs real GitHub Copilot subscription)_
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->

## Follow-up (post-review fix)

Manual check surfaced that Copilot models were missing from the `/model` / `/models` picker even after `/provider add copilot` reported "connected". Root cause was a leftover code path from the pre-OAuth era: the picker filtered catalog rows through `CredentialStore.health()`, which explicitly returns `missing` for `AuthKind.oauth` (since OAuth tokens don't live under a single `api_key` field).

**Fix** (in this session):

- `cli/lib/src/ui/panel_controller.dart` — `openModel()` filter now uses `adapter.isConnected(p, config.credentials)`, matching the pattern already used for `/provider list` and the provider action panel. Drops the `AuthKind.none` branch; the base `ProviderAdapter.isConnected()` handles it.
- `cli/lib/src/credentials/credential_store.dart` — deleted `CredentialHealth` enum and `health()` method (sole caller replaced; no production code still references them).
- `cli/lib/glue.dart` — removed `CredentialHealth` from the public export.
- `cli/test/credentials/credential_store_test.dart` — removed the three `CredentialStore.health` tests.

`dart analyze --fatal-infos` clean; `dart test` all pass (the pre-existing Docker executor test is unrelated and fails on main as well when Docker isn't running).

AC #12 is still partially verified — user confirmed the OAuth connect path works; sending a completion via `--model copilot/...` now becomes possible once they run `/model` and pick a Copilot entry.

## Follow-up 2: responsive TUI panels (2026-04-19)

The `/models` visibility fix above was a symptom of a wider issue: every picker (`/model`, `/resume`, `/history`, `/provider`, `/help`) baked its rendered content at open time and never re-flowed on terminal resize. A unified refactor landed as an 11-commit series on `main`:

- `PanelFluid` small-terminal fallback (`7484f0d`) — when the min floor dominates (>75% of terminal width), expand to `available - margin` instead of an awkward cramped box.
- `SelectOption.responsive` (`174cf1e`) — per-render label builder `String Function(int contentWidth)`.
- `SelectPanel.headerBuilder` (`4b0bd71`) — per-render header list.
- `PanelModal.responsive` (`d31bffb`) — per-render content list with cached `_lastLines` for `handleEvent`.
- `ResponsiveTable<T>` helper (`61df08a`) — width-aware wrapper over `TableFormatter` with single-slot memoization.
- Picker migrations: model (`621b042`), resume (`132866c`), history (`1c2241a`, also deleted dead `_contentWidthFor`/`_terminalWidth`/`_defaultTerminalWidth`), provider list + `/provider add` picker (`566242d`), help (`bb87b5c`).
- Dead code removal (`4571b89`): `formatModelPanelLines` + `ModelPanelLines` class (-142 LoC net).
- Formatter sweep (`f06567c`).

`dart analyze --fatal-infos` clean; `dart test` all pass (1270) except the pre-existing Docker test that fails without a Docker daemon.

Future follow-up tracked in TASK-30: `BlockRenderer` / `MarkdownRenderer` also take `width` once at construction and would benefit from the same pattern, but they don't cause user-visible breakage today.

<!-- SECTION:FINAL_SUMMARY:END -->
