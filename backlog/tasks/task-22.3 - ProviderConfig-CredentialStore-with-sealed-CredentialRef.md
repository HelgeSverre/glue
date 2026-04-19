---
id: TASK-22.3
title: ProviderConfig + CredentialStore with sealed CredentialRef
status: To Do
assignee: []
created_date: '2026-04-19 00:36'
labels:
  - model-provider-2026-04
  - credentials
  - security
dependencies:
  - TASK-22.1
documentation:
  - cli/docs/plans/2026-04-19-provider-adapter-contract-plan.md
parent_task_id: TASK-22
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Credentials should live outside project config. Resolve via env, stored credentials file, inline value, or none.

**Shape (from Provider Adapter Contract plan):**
```dart
sealed class CredentialRef {}
class EnvCredential extends CredentialRef { final String name; }
class StoredCredential extends CredentialRef { final String key; }
class InlineCredential extends CredentialRef { final String value; }
class NoCredential extends CredentialRef {}

abstract class CredentialStore {
  Future<String?> resolve(CredentialRef ref, {required String providerId});
}

class ProviderConfig {
  final String id;
  final String name;
  final String adapter;           // anthropic | openai | gemini | mistral
  final Uri? baseUrl;
  final String compatibility;     // openai | groq | ollama | openrouter | vllm
  final Map<String, String> requestHeaders;
  final CredentialRef credential;
}
```

**Resolution order:** env var → `~/.glue/credentials.json` → inline (with warning) → `NoCredential`.

**`credentials.json` shape:**
```json
{ "version": 1, "providers": { "anthropic": { "api_key": "sk-ant-..." } } }
```

**Files to create:**
- `cli/lib/src/config/provider_config.dart`
- `cli/lib/src/config/credential_ref.dart` — sealed class + `CredentialRef.parse("env:FOO" | "none" | "inline:...")`
- `cli/lib/src/config/credential_store.dart` — `CredentialStore` impl reading env + JSON file
- `cli/test/config/credential_store_test.dart`
- `cli/test/config/credential_ref_test.dart`

**Gotchas:**
- File MUST be created with `0600` permissions on write
- Reads must never log key values (security)
- Do NOT read `Platform.environment` directly from adapters — route through `CredentialStore`
- Inline credentials in YAML emit a warning (discouraged; debug/throwaway only)

**Depends on:** MP1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `CredentialRef` is a sealed class with 4 variants (Env/Stored/Inline/No)
- [ ] #2 `CredentialStore.resolve()` follows order: env → file → inline → none
- [ ] #3 `credentials.json` created with `0600` permissions on write
- [ ] #4 Reads never log key values (no key appears in debug output)
- [ ] #5 `api_key: none` returns `null` without error (Ollama/local use case)
- [ ] #6 Inline credentials emit warning
- [ ] #7 Tests cover each resolution path + file-permissions assertion
<!-- AC:END -->
