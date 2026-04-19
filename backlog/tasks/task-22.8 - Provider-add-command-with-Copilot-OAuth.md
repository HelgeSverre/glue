---
id: TASK-22.8
title: /provider add command with Copilot OAuth
status: In Progress
assignee: []
created_date: '2026-04-19 12:00'
updated_date: '2026-04-19 12:00'
labels:
  - model-provider-2026-04
  - commands
  - oauth
  - ui
dependencies:
  - TASK-22.3
  - TASK-22.4
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
- [ ] #1 `/provider add anthropic` with no env opens masked input modal, stores on submit, reports "Connected".
- [ ] #2 `/provider add copilot` shows device URL + user code, polls, exchanges for Copilot token, stores all three fields.
- [ ] #3 Copilot token refreshes automatically when stored `copilot_token_expires_at` is past.
- [ ] #4 Copilot request carries `Copilot-Integration-Id: vscode-chat` + `Editor-Version: Glue/<ver>` headers.
- [ ] #5 `/provider list` renders table with status per provider (connected / missing / no-auth).
- [ ] #6 `/provider remove <id>` clears stored fields; notes if env var is still set.
- [ ] #7 `/provider test <id>` runs `adapter.validate` without HTTP or side effects.
- [ ] #8 Word "credentials" / "auth" does not appear in any user-visible string (slash command names, error messages, panel titles).
- [ ] #9 `GlueConfig.validate()` error message references `/provider add <id>`, not a legacy command.
- [ ] #10 Anthropic TOS risk: Claude Pro / ChatGPT-subscription OAuth is NOT shipped.
- [ ] #11 Tests: `auth_flow`, `credential_store` multi-field, `copilot_token_manager`, `copilot_adapter`, `provider_command`. `dart test` + `dart analyze --fatal-infos` green.
- [ ] #12 Manual: `./glue` → `/provider add copilot` → browser approval → `--model copilot/claude-sonnet-4.6 "hi"` responds.
<!-- AC:END -->

## Files

**Create:**
- `cli/lib/src/providers/auth_flow.dart`
- `cli/lib/src/providers/copilot_adapter.dart`
- `cli/lib/src/providers/copilot_token_manager.dart`
- `cli/lib/src/ui/api_key_prompt_panel.dart`
- `cli/lib/src/ui/device_code_panel.dart`
- `cli/lib/src/app/commands/provider_command.dart`

**Modify:**
- `cli/lib/src/catalog/model_catalog.dart` (`AuthKind`, `AuthSpec.helpUrl`)
- `cli/lib/src/catalog/catalog_parser.dart`
- `cli/tool/gen_models.dart`
- `cli/lib/src/catalog/models_generated.dart` (regen)
- `cli/lib/src/credentials/credential_store.dart` (`setFields`, `getField`)
- `cli/lib/src/providers/provider_adapter.dart` (`beginInteractiveAuth`, `isConnected`)
- `cli/lib/src/config/glue_config.dart` (register `CopilotAdapter`, new error wording)
- `cli/lib/src/commands/slash_commands.dart`
- `cli/lib/src/ui/panel_controller.dart`
- `docs/reference/models.yaml` (new `copilot` entry, `help_url` sprinkled)
