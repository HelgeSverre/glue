# Version Numbering Strategy

## Glue CLI -- Version Numbering Strategy

### 1. Overview

Glue CLI is a terminal-native AI coding agent built in Dart, currently at `version: 0.1.0` in `cli/pubspec.yaml` (mirrored in `lib/src/config/constants.dart` as `AppConstants.version`). The project has 149 commits, 97 source files, 93 test files, and zero git tags. A large wave of features (web tools, browser automation, PDF extraction, skills framework, observability/OpenTelemetry, Mistral provider, Docker support, permissions system) has just landed on `main`. This document defines the versioning scheme going forward.

### 2. Semantic Versioning Scheme

Follow **Semantic Versioning 2.0.0** (`MAJOR.MINOR.PATCH`) with the 0.x conventions:

| Range     | Meaning                                                                                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **0.x.y** | Pre-stable. Public API may change between any minor bump. Each 0.MINOR.0 release can include breaking changes without ceremony.                                    |
| **1.0.0** | Stable. Public-facing CLI interface, config format, skill manifest schema, and LLM provider contract are considered stable. Breaking changes require a major bump. |

During the 0.x phase, treat **MINOR** as the significant release unit and **PATCH** for bug fixes and small improvements between feature releases.

### 3. Recommended Version RIGHT NOW: `0.2.0`

Rationale:

- `0.1.0` was the initial scaffold. It was never tagged or released.
- The 60+ commits just merged represent the first "real" feature-complete milestone: four LLM providers (Anthropic, OpenAI, Ollama, Mistral), tool infrastructure (bash, grep, glob, read, write, edit, web fetch, web search, browser, PDF, subagent), skills framework, observability pipeline, session storage v2, permissions system, and a polished terminal UI.
- This is not a patch on 0.1.0; it is a wholly new capability surface. A minor version bump to `0.2.0` is appropriate.
- Jumping to `0.3.0` or higher would waste version space. Jumping to `1.0.0` is premature (see section 6).

### 4. Tag Naming Convention

**Format:** `v{MAJOR}.{MINOR}.{PATCH}` -- e.g. `v0.2.0`, `v0.2.1`, `v1.0.0`

This is already what the `just release` command and the GitHub Actions release workflow expect:

- `justfile` line 60: `git tag "v{{version}}"`
- `release-tag-build.yml` line 6: triggers on `push.tags: "v*"`

No changes needed. The `v` prefix is mandatory.

### 5. Pre-release Version Convention

When testing a release candidate before cutting a stable minor/major:

```
0.3.0-beta.1    # First beta of the 0.3.0 release
0.3.0-beta.2    # Second beta iteration
0.3.0-rc.1      # Release candidate
1.0.0-beta.1    # First beta toward stable
```

Rules:

- Pre-release tags (`v0.3.0-beta.1`) will still trigger the release workflow since they match `v*`. The GitHub Release created by `softprops/action-gh-release` will automatically be marked as a pre-release if the tag contains a hyphen, which is the desired behavior.
- Pre-release versions sort correctly under SemVer: `0.3.0-beta.1 < 0.3.0-beta.2 < 0.3.0-rc.1 < 0.3.0`.
- Use pre-releases sparingly. For most 0.x releases, go straight to the release version since the 0.x contract already implies instability.

### 6. Roadmap to 1.0.0

The `1.0.0` release signals: "the CLI interface, configuration format, and extension points are stable; breaking changes will be rare and always bumped as 2.0.0."

**Gate criteria for 1.0.0:**

| Milestone                 | Description                                                                                                     |
| ------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Stable CLI contract**   | Command-line flags, exit codes, and output format are documented and unlikely to change.                        |
| **Config schema frozen**  | The `~/.config/glue/` configuration format (model registry, permissions, provider keys) has a versioned schema. |
| **Skill manifest v1**     | The `.glue/skills/` YAML format is documented and stable for third-party skill authors.                         |
| **Cross-platform parity** | Linux, macOS, and Windows binaries all pass the CI matrix (`ci-matrix-os.yml`) and e2e suite consistently.      |
| **Pub.dev readiness**     | If publishing to pub.dev is planned, package metadata, example code, and API docs meet pub conventions.         |
| **External users**        | At least one external user or team is running Glue in a real workflow and has validated the experience.         |

**Estimated timeline:** 1.0.0 is likely 2-4 minor releases away (0.3.0, 0.4.0, ...). Do not rush it.

### 7. Projected Version Sequence

| Version         | Likely Content                                                                    |
| --------------- | --------------------------------------------------------------------------------- |
| `v0.2.0`        | **Now.** Everything on main today. First tagged release.                          |
| `v0.2.1`        | Bug fixes and polish discovered after first real-user testing.                    |
| `v0.3.0`        | Next feature wave (e.g., MCP tool server, plugin system, streaming improvements). |
| `v0.4.0`        | Config schema stabilization, skill manifest v1, install scripts.                  |
| `v1.0.0-beta.1` | Feature-complete candidate. External user testing period.                         |
| `v1.0.0`        | Stable release.                                                                   |

### 8. Integration with Existing Tooling

#### `just release <version>` (in `cli/justfile`)

The existing command does exactly the right things:

1. Updates `pubspec.yaml` version via `sed`
2. Compiles the AOT binary
3. Commits as `release: v<version>`
4. Creates tag `v<version>`
5. Prints reminder to `git push && git push --tags`

**One gap to be aware of:** the version string in `lib/src/config/constants.dart` (`AppConstants.version = '0.1.0'`) is NOT updated by the `just release` command. It is hardcoded separately from `pubspec.yaml`. When cutting the release, either:

- (a) Add a second `sed` line to the justfile to update `constants.dart`, or
- (b) Refactor to read the version from pubspec.yaml at build time.

This is a known issue to address before tagging `v0.2.0`, but is outside the scope of this versioning strategy document.

#### GitHub Actions `release-tag-build.yml`

Triggers on any `v*` tag push. Builds Linux, macOS, and Windows binaries via `dart compile exe`. Uploads them as artifacts and creates a GitHub Release with the binaries attached via `softprops/action-gh-release@v2`.

This workflow requires no changes. It works for stable tags (`v0.2.0`) and pre-release tags (`v0.3.0-beta.1`) alike.

#### CI pipelines

- `ci-dart-checks.yml` runs format/analyze/test on every PR and main push -- unrelated to versioning, no changes needed.
- `ci-matrix-os.yml` runs cross-platform tests on PRs -- unrelated to versioning, no changes needed.
- `integration-e2e-nightly.yml` runs e2e tests nightly -- consider gating releases on a green nightly run, but this is process, not tooling.

### 9. Dual-Location Version String

The version currently lives in two places:

| Location                                   | Current Value | Updated By               |
| ------------------------------------------ | ------------- | ------------------------ |
| `cli/pubspec.yaml` line 3                  | `0.1.0`       | `just release` (via sed) |
| `cli/lib/src/config/constants.dart` line 6 | `'0.1.0'`     | **Nothing** (manual)     |

The `AppConstants.version` is displayed in the UI (`app.dart` line 478: `Glue v${AppConstants.version}`). These two values must stay in sync. The recommended fix is to extend the `just release` recipe to update both files, or to generate `constants.dart` from `pubspec.yaml` at build time. Until then, treat it as a manual checklist item.
