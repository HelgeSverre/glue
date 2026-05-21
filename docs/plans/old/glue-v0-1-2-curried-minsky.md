# `glue doctor --verbose` — Provider Connectivity Section

## Context

`glue doctor` already validates files, parses configs, and runs the in-memory
`validate()` health check on the active model's provider. But it never tells the
user whether their *other* configured providers can actually talk to their APIs
right now. The recently-added `ProviderAdapter.probe()` (real `GET /models`
network check) is wired into `/provider test` and the `/provider add` flow, but
not into doctor.

We want: when the user runs `glue doctor --verbose`, doctor probes every
*configured* provider in parallel and renders a per-provider connectivity row
with a colored marker. This makes "is anything broken right now?" answerable in
one command instead of cycling through `/provider test <id>` for each.

The `--verbose` gate matters because probing is network-bound (up to ~5s per
provider, mitigated by `Future.wait`) and the existing fast-path for
`glue doctor` should stay sub-second.

## Approach

Make `runDoctor` async, append a new "Provider connectivity" section that only
runs under `verbose: true`. Iterate `config.catalogData.providers.values`,
filter to providers that are *configured* (`adapter.isConnected(def, store)`
returns true), call `adapter.probe(resolved)` for each one in parallel, and
emit a `DoctorFinding` per provider with severity mapped from `ProviderHealth`.

Reuse `wireProviderAdapters` (cli/lib/src/boot/providers.dart:10) to build the
registry, with a doctor-local plain-http factory (no observability needed for a
one-shot CLI run). Inject the registry-builder as an optional parameter so
tests can supply a fake registry of deterministic adapters.

## Severity mapping (the red/green/gray)

| `ProviderHealth`    | `DoctorSeverity` | Marker | Rationale                                        |
| ------------------- | ---------------- | ------ | ------------------------------------------------ |
| `ok`                | `ok`             | `✓` green | API accepted the credential.                     |
| `unauthorized`      | `error`          | `✗` red   | Server rejected the key — actionable.            |
| `unreachable`       | `info`           | `·` gray  | Couldn't determine (offline/5xx); not your fault. |
| `unknownAdapter`    | `warning`        | `!` yellow | Catalog points at a wire we don't ship — odd but recoverable. |
| `missingCredential` | `info`           | `·` gray  | Defensive: the `isConnected` filter should have skipped it. |

The user asked for red/green/gray — `unauthorized → error` is red, `ok → ok`
is green, `unreachable → info` is gray (already the gray marker in
`_marker()` at doctor.dart:122). `warning` (yellow) covers the unusual
`unknownAdapter` case so it doesn't masquerade as healthy.

## Files

### `cli/lib/src/doctor/doctor.dart`

- Change signature: `DoctorReport runDoctor(Environment env)` →
  `Future<DoctorReport> runDoctor(Environment env, { bool verbose = false, AdapterRegistry Function(CredentialStore)? adaptersBuilder })`.
- Existing sync checks stay sync; just `await` is unused for them.
- New helper `_probeConfiguredProviders(findings, environment, adaptersBuilder)`:
  - Loads `GlueConfig.load(environment: environment)` inside a try/catch — if
    the config is malformed, append a single info finding and return without
    probing (the existing `_checkConfigYaml` / `_checkConfigValidation` rows
    already surfaced the parse error).
  - Builds `AdapterRegistry` via the supplied builder, defaulting to
    `wireProviderAdapters(credentials: config.credentials, httpClient: (_) => http.Client())`.
  - For each `def` in `config.catalogData.providers.values`:
    - `adapter = registry.lookup(def.adapter)` — null → skip silently (catalog
      drift is reported by other doctor rows).
    - `if (!adapter.isConnected(def, config.credentials)) continue;` — only probe
      providers the user has set up.
    - Build `ResolvedProvider` via `config.resolveProviderById(def.id)` so we
      get the right credential map without re-implementing resolution.
    - Schedule `adapter.probe(resolved)` into a `List<Future<_ProbeRow>>`.
  - `await Future.wait(probes)`; sort results alphabetically by provider name
    (deterministic output); append findings.
  - Section name: `'Provider connectivity'`. Message format:
    `'<Provider name>: <short status>'` where status is one of
    `'ok'`, `'credentials rejected'`, `'unreachable'`, `'no adapter'`,
    `'not connected'`. (Match the tone/grammar of `_probeMessage` in
    `cli/lib/src/ui/actions/provider_actions.dart:459` but keep it terse — no
    trailing remediation hint, since doctor lists many providers; the user can
    run `/provider test <id>` for the full message.)
- Call from `runDoctor` only when `verbose == true`. Place after
  `_checkConfigValidation` so config errors render first.

### `cli/lib/src/cli/doctor.dart`

- `await runDoctor(...)` and pass `verbose: argResults!.flag('verbose')` so
  the probe runs only on `--verbose`.

### `cli/test/doctor/doctor_test.dart`

- Existing tests: prefix calls with `await` (signature change). Verify
  non-verbose runs do **not** include any "Provider connectivity" finding
  (no network calls in the test suite — important).
- Add `runDoctor … with verbose builds a Provider connectivity section`:
  inject a fake `adaptersBuilder` returning a registry of `_FakeAdapter`s
  (probe stubs — one returns `ok`, one `unauthorized`, one `unreachable`,
  one not-configured to assert it's filtered out). Assert findings contain
  the right severity per provider and skipped providers don't appear.

## Reused existing utilities

- `wireProviderAdapters` (cli/lib/src/boot/providers.dart:10) — single source
  of truth for which adapter classes Glue ships.
- `ProviderAdapter.isConnected` (provider_adapter.dart:119) — the existing
  "is this configured" predicate. Use as-is.
- `GlueConfig.resolveProviderById` (glue_config.dart:140) — already produces
  the `ResolvedProvider` shape `probe()` needs.
- `_marker(severity)` (doctor.dart:119) — already prints the green/yellow/red/gray
  markers we want.
- The fake-adapter pattern in
  `cli/test/providers/provider_adapter_test.dart:15` is the template for the
  new test fixture.

## Verification

```sh
# fast-path stays fast and offline
just check                                    # full quality gate
dart test test/doctor/doctor_test.dart        # incl. new verbose test

# end-to-end smoke (run from cli/, after `dart compile exe ...`)
glue doctor                                   # no Provider connectivity section
glue doctor --verbose                         # rows for every configured provider

# break a key and confirm red ✗
GLUE_HOME=$(mktemp -d) sh -c '
  echo "active_model: gemini/gemini-2.5-flash" > $GLUE_HOME/config.yaml
  echo "{\"providers\":{\"gemini\":{\"api_key\":\"not-a-real-key\"}}}" > $GLUE_HOME/credentials.json
  glue doctor --verbose | grep -E "Gemini:"
'

# offline → gray ·
# (disconnect network, then)
glue doctor --verbose | grep -E "(✓|✗|·)"
```

## Non-goals

- Probing on plain `glue doctor` (always-on probing would slow the common case
  for no benefit; opt-in via `--verbose` is enough).
- Adding a JSON output mode for doctor — the existing renderer is human-only
  and that's fine for v0.1.
- Caching probe results between runs.
