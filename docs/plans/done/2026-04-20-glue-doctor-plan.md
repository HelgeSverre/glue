# Plan: `glue doctor`

## Objective

Add a non-interactive `glue doctor` CLI command that inspects the user's Glue installation and reports:

- resolved `GLUE_HOME` and core paths
- presence/absence of expected files and directories
- parse/shape errors in `config.yaml`, `preferences.json`, `credentials.json`, and optional catalog override files
- config validation issues such as missing required provider credentials for the selected active model
- malformed session files (`meta.json`, `conversation.jsonl`) and other session directory inconsistencies
- any additional high-signal filesystem problems like orphaned `.tmp` files

The command should be safe, local-only, and read-mostly. It should not mutate user state except possibly future optional repair flags; the initial version should be pure diagnosis.

---

## Codebase findings

### CLI integration

Top-level CLI commands are handled in `bin/glue.dart` via `GlueCommandRunner extends CompletionCommandRunner<int>`.

Current patterns:

- flags such as `--where` are handled directly in `runCommand`
- subcommands currently only include `completions`
- interactive TUI startup goes through `_runApp`

This makes `glue doctor` best implemented as a new top-level `Command<int>` subcommand rather than a TUI slash command.

Relevant files:

- `bin/glue.dart`

### Filesystem/path model

All Glue paths are centralized in `Environment`.

Relevant paths:

- `configYamlPath` → `~/.glue/config.yaml`
- `configPath` → `~/.glue/preferences.json`
- `credentialsPath` → `~/.glue/credentials.json`
- `modelsYamlPath` → `~/.glue/models.yaml`
- `sessionsDir`
- `logsDir`
- `cacheDir`
- `skillsDir`
- `plansDir`

Relevant files:

- `lib/src/core/environment.dart`
- `lib/src/core/where_report.dart`

### Config loading and validation

`GlueConfig.load()`:

- reads YAML from `config.yaml`
- merges bundled + cached + local model catalogs
- constructs `CredentialStore`
- resolves active model
- can throw `ConfigError` for invalid config states
- rejects legacy v1 config format with a migration hint

`GlueConfig.validate()`:

- validates the resolved active provider and adapter health
- reports missing credentials or unknown adapters as `ConfigError`

Caveat:

- `_loadOptionalYaml()` swallows catalog parse errors and returns `null`
- good for normal startup, bad for diagnostics
- `doctor` should use stricter parsing for `models.yaml` and cached catalog files to expose those suppressed errors

Relevant files:

- `lib/src/config/glue_config.dart`
- `lib/src/catalog/catalog_parser.dart`
- `lib/src/catalog/catalog_loader.dart`

### Preferences JSON

`ConfigStore` reads `preferences.json` and intentionally keeps last-known-good cache on parse error.

Caveat:

- that means normal app flow may tolerate bad JSON silently
- `doctor` should parse the file directly and report JSON syntax/shape issues explicitly

Relevant files:

- `lib/src/storage/config_store.dart`

### Credentials JSON

`CredentialStore` treats missing/corrupt `credentials.json` as empty.
This is correct for resilience during normal app use, but `doctor` should surface corruption directly.

Relevant behaviors:

- expected top-level shape is roughly:
  - `version`
  - `providers: { <providerId>: { <field>: <string> } }`
- writes are atomic and may leave `.tmp` only on interrupted failure

Relevant files:

- `lib/src/credentials/credential_store.dart`
- `test/credentials/credential_store_test.dart`

### Sessions

Session storage is under `~/.glue/sessions/<id>/`.

Per-session files:

- `meta.json`
- `conversation.jsonl`

`SessionStore.listSessions()` and `loadConversation()` currently swallow parse errors and skip bad records.
That is fine for UX, but insufficient for diagnostics.

Doctor needs stricter checks such as:

- session dir exists but `meta.json` missing
- `meta.json` invalid JSON
- `meta.json` wrong shape or required fields missing
- `conversation.jsonl` invalid JSON on line N
- `conversation.jsonl` non-object JSON line
- missing `type` field
- possibly mismatched or suspicious event structures

Relevant files:

- `lib/src/storage/session_store.dart`
- `lib/src/session/session_manager.dart`
- `test/storage/session_resume_test.dart`
- `test/storage/session_store_test.dart`

### Service startup caveat

`ServiceLocator.create()` calls:

- `GlueConfig.load()`
- `config.validate()`
- `environment.ensureDirectories()`

This means `doctor` should not go through `ServiceLocator`, because doctor must inspect broken setups without failing early or mutating directories.

Relevant file:

- `lib/src/core/service_locator.dart`

---

## Proposed UX

### CLI surface

Primary command:

```bash
glue doctor
```

Optional future flags, not required in v1:

- `glue doctor --json`
- `glue doctor --strict`
- `glue doctor --sessions <limit>`
- `glue doctor --repair` (future only, not in initial scope)

### Output style

Human-readable summary with severity levels.

Suggested sections:

1. Environment
2. Core files
3. Config validation
4. Sessions
5. Summary

Suggested status levels:

- `OK`
- `WARN`
- `ERROR`

Example sketch:

```text
Glue Doctor
===========

Environment
  OK    GLUE_HOME: /Users/x/.glue
  OK    cwd: /work/project

Core files
  OK    config.yaml exists
  WARN  preferences.json missing
  OK    credentials.json parsed
  ERROR models.yaml invalid YAML: line 12, column 5 ...
  OK    sessions/ exists
  WARN  logs/ missing

Config validation
  ERROR active_model provider anthropic missing credential
  OK    config.yaml parsed
  OK    active_model resolved to anthropic/claude-sonnet-4-6

Sessions
  OK    scanned 17 session directories
  WARN  2 session dirs missing conversation.jsonl
  ERROR session 171234... meta.json invalid JSON
  ERROR session 171235... conversation.jsonl line 43 invalid JSON

Summary
  8 OK, 3 WARN, 3 ERROR
  Exit code: 1
```

### Exit codes

Recommended:

- `0` = no errors (warnings allowed)
- `1` = one or more errors found
- `2` = command usage / internal doctor failure

---

## Proposed architecture

Create a dedicated diagnostic subsystem rather than trying to reuse app startup paths directly.

### New module

Suggested files:

- `lib/src/doctor/doctor.dart`
- `lib/src/doctor/doctor_check.dart`
- `lib/src/doctor/doctor_report.dart`
- `lib/src/doctor/session_diagnostics.dart`
- `lib/src/doctor/file_diagnostics.dart`

Minimal alternative if you want to stay very small initially:

- `lib/src/doctor/doctor.dart`
- `lib/src/doctor/doctor_renderer.dart`

### Core types

```dart
enum DoctorSeverity { ok, warning, error }

class DoctorFinding {
  final DoctorSeverity severity;
  final String section;
  final String message;
  final String? path;
}

class DoctorReport {
  final List<DoctorFinding> findings;
  int get errorCount;
  int get warningCount;
  int get okCount;
  bool get hasErrors;
}
```

### Main entrypoint

```dart
DoctorReport runDoctor(Environment env)
```

This should:

1. inspect filesystem presence
2. parse files directly with strict readers
3. run config-level semantic validation where possible
4. scan sessions strictly
5. return a report object

### Rendering

Provide a pure renderer:

```dart
String renderDoctorReport(DoctorReport report)
```

This keeps CLI wiring simple and testable.

---

## Diagnostic scope for v1

### 1. Environment/path checks

Checks:

- report `GLUE_HOME`
- report whether glue dir exists
- report existence of:
  - config.yaml
  - preferences.json
  - credentials.json
  - models.yaml
  - sessions/
  - logs/
  - cache/
  - skills/
  - plans/

Severity guidance:

- missing `logs/`, `cache/`, `plans/`, `skills/` → `WARN` or `OK` depending on intent
- missing `sessions/` when no sessions yet → `WARN` at most
- missing `config.yaml` should probably be `WARN`, not `ERROR`

### 2. `config.yaml` checks

Checks:

- file exists or not
- YAML parse success/failure
- legacy v1 shape detection
- `GlueConfig.load(environment: env)` success/failure
- `config.activeModel` resolves
- `config.validate()` success/failure

Important nuance:

- if `config.yaml` is missing, `GlueConfig.load()` can still succeed via defaults/env
- doctor should distinguish:
  - file absence
  - file syntax problem
  - semantic config problem
  - runtime validation problem (missing credentials)

### 3. `preferences.json` checks

Checks:

- file exists or not
- valid JSON object or not
- optional spot-check for known fields such as `trusted_tools` being a list of strings

Because `ConfigStore` is intentionally forgiving, doctor should use direct `jsonDecode` and explicit shape validation.

### 4. `credentials.json` checks

Checks:

- file exists or not
- valid JSON object or not
- expected top-level `providers` map shape
- each provider entry is a JSON object
- each value under provider is a string
- optional POSIX permissions check (`0600`) on non-Windows
- detect orphaned `credentials.json.tmp`

Missing credentials file should usually be `WARN` or `OK`, not `ERROR`.
Malformed credentials file should be `ERROR`.

### 5. `models.yaml` and cached catalog checks

Checks:

- local override file `~/.glue/models.yaml` parses via `parseCatalogYaml`
- cached remote catalog in `~/.glue/cache/models.yaml` parses via `parseCatalogYaml`
- if parse fails, report exact exception message

This fills a current observability gap because `GlueConfig.load()` suppresses those parse errors.

### 6. Session checks

For each directory under `sessions/`:

Checks:

- `meta.json` exists
- `meta.json` parses as JSON object
- required fields present for `SessionMeta.fromJson`:
  - `id`
  - `start_time`
  - enough model/provider/model_ref info for compatibility
- `SessionMeta.fromJson` succeeds
- `conversation.jsonl` existence (probably `WARN` if missing)
- each non-empty line parses as JSON object
- each record has `type`
- include line number in failures
- detect orphaned `.tmp` files

Potential extra checks:

- session dir name vs meta.id mismatch → `WARN`
- malformed timestamps → `ERROR`

### 7. Summary/aggregation

Aggregate counts by severity and return process exit code accordingly.

---

## Implementation plan

### Phase 1: add doctor command skeleton

1. Add a new CLI subcommand in `bin/glue.dart`:
   - `class DoctorCommand extends Command<int>`
2. Resolve `Environment.detect()`
3. Call a new `runDoctor(env)`
4. Print rendered report
5. Return exit code `0` or `1`

Tests:

- command invocation returns expected exit code for empty temp environment
- output contains `Glue Doctor`

### Phase 2: add report types and path scanning

1. Introduce `DoctorFinding`, `DoctorReport`, severity enum
2. Implement filesystem/path checks only
3. Render report sections deterministically

Tests:

- report counts ok/warn/error correctly
- path presence and absence produce expected findings

### Phase 3: strict file diagnostics

1. Add strict parsers/checkers for:
   - `config.yaml`
   - `preferences.json`
   - `credentials.json`
   - local `models.yaml`
   - cached `cache/models.yaml`
2. Use direct parsing, not forgiving runtime wrappers
3. Then separately run `GlueConfig.load()` and `config.validate()` to report semantic issues

Tests:

- malformed YAML in config.yaml becomes `ERROR`
- legacy config format becomes `ERROR` with migration hint
- malformed preferences.json becomes `ERROR`
- malformed credentials.json becomes `ERROR`
- invalid local models.yaml becomes `ERROR`

### Phase 4: session diagnostics

1. Add strict session scanner over `sessions/`
2. Report malformed `meta.json`
3. Report invalid `conversation.jsonl` lines with line numbers
4. Report missing files and orphaned tmp files

Tests:

- missing meta.json
- bad meta.json JSON
- `SessionMeta.fromJson` failure
- bad conversation line N
- missing conversation file
- dir name != meta id warning

### Phase 5: polish

1. Improve messages and grouping
2. Add optional POSIX permission checks for credentials file
3. Consider JSON output if desired

---

## Recommended implementation details

### Do not reuse forgiving readers for diagnostics

Avoid relying only on:

- `ConfigStore.load()`
- `CredentialStore._readRaw()` behavior
- `SessionStore.listSessions()`
- `SessionStore.loadConversation()`

These intentionally hide errors for app resilience.
Doctor should instead parse files directly and explicitly.

### Keep doctor pure and side-effect free

Do not call:

- `ServiceLocator.create()`
- `environment.ensureDirectories()`

Doctor should inspect, not repair or initialize.

### Keep rendering separate from diagnosis

A structured report object will make:

- unit testing easier
- future `--json` support trivial
- slash command integration possible later if desired

---

## Open questions

1. Should missing optional files/directories be `OK` or `WARN`?
   - Recommendation: `WARN` for visibility, but never `ERROR`.

2. Should missing credentials for the active model be an `ERROR`?
   - Recommendation: yes, because `glue` startup would currently fail in `ServiceLocator.create()` after `config.validate()`.

3. Should `glue doctor` scan every session by default?
   - Recommendation: yes in v1 unless performance becomes an issue; session files are local and typically small.

4. Should local `./config.yaml` overrides also be checked?
   - The codebase currently has `/config init` creating local config for debugging, but `GlueConfig.load()` is still based on `~/.glue/config.yaml` unless separately taught otherwise.
   - Recommendation: v1 doctor focuses on active runtime paths only, and optionally notes if `./config.yaml` exists but is not part of current resolution semantics.

---

## Suggested first slice

If we want the smallest useful version first:

1. `glue doctor` CLI command
2. path existence report
3. strict parse checks for:
   - `config.yaml`
   - `preferences.json`
   - `credentials.json`
4. `GlueConfig.load()` + `validate()` reporting
5. summary + exit code

Then add session scanning in a second pass.

---

## Suggested test layout

- `test/doctor/doctor_test.dart`
- `test/doctor/file_diagnostics_test.dart`
- `test/doctor/session_diagnostics_test.dart`
- `test/bin/glue_doctor_command_test.dart` or similar CLI-focused tests

Use temp directories plus `Environment.test(home: ..., cwd: ...)` to isolate state.

---

## Recommendation

Implement `glue doctor` as a new top-level CLI subcommand backed by a dedicated diagnostic subsystem.
Do not route it through TUI or `ServiceLocator`.
Start with file/config diagnostics, then extend to strict session scanning.
