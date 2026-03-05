# Release Strategy

## Version Scheme

Semantic Versioning 2.0.0 (`MAJOR.MINOR.PATCH`).

| Range     | Meaning                                                                                 |
| --------- | --------------------------------------------------------------------------------------- |
| **0.x.y** | Pre-stable. Public API may change between minor bumps.                                  |
| **1.0.0** | Stable. CLI interface, config format, skill manifest, and provider contract are frozen. |

Tags: `v{MAJOR}.{MINOR}.{PATCH}` (e.g., `v0.2.0`). Pre-releases: `v0.3.0-beta.1`.

## Current State

- Current version: `0.1.0` (never tagged or released)
- 149+ commits, 97 source files, 93 test files, zero git tags
- A large wave of features has landed on main since 0.1.0

## Next Release: v0.2.0

`0.1.0` was the initial scaffold. The current main represents the first real feature-complete milestone. Bump to `0.2.0`.

## Release Checklist

### Must-Have (Gate Release)

- [ ] Add LICENSE file (MIT) at repo root and `cli/`
- [ ] Add `repository`, `topics`, `executables` to `cli/pubspec.yaml`
- [ ] Fix version duplication (`pubspec.yaml` vs `bin/glue.dart` vs `constants.dart`) — see ISSUES.md DUP-004
- [ ] Merge open PRs and consolidate branches (see ISSUES.md MERGE-001 through MERGE-004)
- [ ] Fix remaining `dart analyze` info-level issues
- [ ] Reconcile `docs/bugs.md` with actual fix status (or delete in favor of ISSUES.md)
- [ ] Verify all tests pass on CI (Ubuntu, macOS, Windows)
- [ ] Run `dart pub publish --dry-run`
- [ ] Tag `v0.2.0` and verify GitHub Release workflow produces all 3 binaries

### Should-Have (First Week)

- [ ] Add `CONTRIBUTING.md`
- [ ] Add `SECURITY.md`
- [ ] Add `example/` directory with minimal usage example
- [ ] Collapse CHANGELOG `[Unreleased]` into `[0.2.0]`
- [ ] Add `homepage` URL to pubspec once website is finalized
- [ ] Screenshots/GIF in README

### Nice-to-Have (First Month)

- [ ] `CODE_OF_CONDUCT.md`
- [ ] Context window management / conversation summarization
- [ ] Real-time cost tracking display
- [ ] SHA256 checksums for release binaries
- [ ] Homebrew formula or other package manager distribution

## Release Tooling

### `just release <version>` (cli/justfile)

1. Updates `pubspec.yaml` version via `sed`
2. Compiles AOT binary
3. Commits as `release: v<version>`
4. Creates tag `v<version>`
5. Prints reminder to `git push && git push --tags`

**Known gap:** Does not update `lib/src/config/constants.dart` or `bin/glue.dart` version strings. Add a second `sed` line or read version from pubspec at build time.

### GitHub Actions (`release-tag-build.yml`)

Triggers on `v*` tag push. Builds Linux, macOS, Windows binaries via `dart compile exe`. Uploads as GitHub Release artifacts via `softprops/action-gh-release@v2`. Works for stable and pre-release tags.

### CI Pipelines

- `ci-monorepo-check.yml` — root monorepo gate (`just check`) + CLI format check on PRs/main
- `ci-matrix-os.yml` — cross-platform tests on PRs
- `integration-e2e-nightly.yml` — nightly E2E with Ollama

## Roadmap to 1.0.0

### Gate criteria

| Milestone             | Description                                                                         |
| --------------------- | ----------------------------------------------------------------------------------- |
| Stable CLI contract   | Command-line flags, exit codes, and output format documented and unlikely to change |
| Config schema frozen  | `~/.glue/` configuration format has a versioned schema                              |
| Skill manifest v1     | `.glue/skills/` format documented and stable for third-party authors                |
| Cross-platform parity | Linux, macOS, Windows all pass CI matrix and E2E suite                              |
| External users        | At least one external user/team running Glue in a real workflow                     |

### Projected sequence

| Version         | Content                                                                                   |
| --------------- | ----------------------------------------------------------------------------------------- |
| `v0.2.0`        | Current main + merged PRs. First tagged release.                                          |
| `v0.2.x`        | Bug fixes from first real-user testing                                                    |
| `v0.3.0`        | Non-PR branch features (history browser, multiline input, clickable links, docked panels) |
| `v0.4.0`        | Config schema stabilization, skill manifest v1, install scripts                           |
| `v1.0.0-beta.1` | Feature-complete candidate. External user testing.                                        |
| `v1.0.0`        | Stable release                                                                            |

Estimated: 1.0.0 is 2-4 minor releases away. Do not rush it.
