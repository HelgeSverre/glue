# Glue CLI -- Public Release Milestone

**Date:** 2026-02-28
**Current version:** 0.1.0 (no published tags)
**Branch:** `feat/pdf-browser-tools` (main branch: `main`)

---

## 1. What Is READY for Public Release

### 1.1 Core Agent Loop

- **ReAct agent loop** (`AgentCore`) with streaming LLM interaction, parallel tool calls, and token counting is fully implemented and tested.
- **Headless `AgentRunner`** enables programmatic use and testing without a terminal.
- **Subagent orchestration** (`AgentManager`) with depth-limited recursive spawning, single and parallel modes, collapsible grouped output.

### 1.2 LLM Providers (4 providers, 10+ models)

- **Anthropic** Messages API with SSE streaming.
- **OpenAI** Chat Completions API with SSE streaming.
- **Ollama** local inference with NDJSON streaming.
- **Mistral** via OpenAI-compatible API with Mistral-specific base URL.
- **`ModelRegistry`** with curated catalog, capability/cost/speed metadata.
- **`/model` picker** with fuzzy search and provider grouping.

### 1.3 Built-in Tools (12 tools)

All tools are implemented, tested, and documented:
`read_file`, `write_file`, `edit_file`, `bash`, `grep`, `list_directory`, `spawn_subagent`, `spawn_parallel_subagents`, `web_fetch`, `web_search`, `web_browser`, `skill`.

### 1.4 TUI

- 60fps async rendering with scroll regions.
- Readline-style input (Emacs keybindings, history, word navigation).
- Markdown table rendering, ANSI styling.
- Slash command system with tab-completing autocomplete.
- `@file` references with recursive fuzzy autocomplete.
- Bash mode (`!` prefix) with background job management.
- Inline confirmation modal, full-screen panel modal, split panel modal.
- Animated mascot splash with liquid physics simulation.
- Spinner animation during LLM streaming.
- Permission mode cycling (confirm / accept-edits / YOLO / read-only).

### 1.5 Shell Execution

- **Multi-shell support** -- bash, zsh, fish, pwsh with correct flag mapping.
- **Docker sandbox** -- ephemeral containers with configurable mounts and host fallback.
- Session-scoped mount persistence.

### 1.6 Web Tools

- **`web_fetch`** -- HTML-to-markdown pipeline, PDF text extraction with OCR fallback (Mistral/OpenAI vision).
- **`web_search`** -- Brave, Tavily, Firecrawl backends with auto-detection and fallback.
- **`web_browser`** -- CDP automation with 5 provider backends (local, Docker, Browserbase, Browserless, Steel).

### 1.7 Skills System

- agentskills.io-compatible discovery from project-local, global, and custom paths.
- YAML frontmatter parser with validation.
- `/skills` slash command with two-pane browser.

### 1.8 Observability

- **File sink** -- daily-rotating JSONL debug logs.
- **OpenTelemetry OTLP/HTTP sink** -- works with LLMFlow, Opik, Helicone, Laminar, Grafana Tempo, Jaeger.
- **Langfuse native sink** -- generation-level tracking with token usage and cost.
- **Three wrapper layers** -- `LoggingHttpClient`, `ObservedLlmClient`, `ObservedTool`.

### 1.9 Session Management

- Session persistence in `~/.glue/sessions/` with `meta.json`, `conversation.jsonl`, `state.json`.
- Rich `SessionMeta` (schema v2) with git context, metrics, PR lifecycle.
- `--resume` (session picker) and `--continue` (most recent).

### 1.10 Configuration

- Layered resolution: CLI flags -> env vars -> `~/.glue/config.yaml` -> defaults.
- Agent profiles for named provider+model pairs.
- Shell completions for bash, zsh, fish, PowerShell.

### 1.11 Test Suite

- **93 test files** covering **452+ test cases**.
- Coverage spans all modules: agent, LLM providers, tools, shell, config, storage, observability, skills, web, input, UI, rendering.
- E2E integration tests via `AgentRunner` + Ollama (`qwen2.5:7b`) with retry wrapper.

### 1.12 CI/CD (6 workflows)

- **`ci-dart-checks.yml`** -- format, analyze, unit tests on every PR/push.
- **`ci-matrix-os.yml`** -- tests on Ubuntu, macOS, Windows.
- **`integration-e2e-nightly.yml`** -- nightly E2E with Ollama.
- **`docs-build-validate.yml`** -- VitePress devdocs build validation.
- **`release-tag-build.yml`** -- multi-platform AOT binary builds (Linux/macOS/Windows) + GitHub Release.
- **`auto-labeler-and-triage.yml`** -- PR labeling and stale issue management.
- **Dependabot** configured for both Dart pub and GitHub Actions.

### 1.13 Documentation

- Comprehensive README with features, install, usage, config, tools, architecture.
- Changelog (`CHANGELOG.md`) with detailed [Unreleased] and [0.1.0] sections.
- Internal docs: architecture glossary, agent-loop-and-rendering, config-yaml reference, session-storage reference, glue-home-layout reference.
- 30+ implementation plan documents in `docs/plans/`.
- VitePress devdocs site with CI build validation.
- Static website (`/website/`) with branding pages.

### 1.14 Build & Release Tooling

- `Justfile` with `build`, `install`, `test`, `analyze`, `check`, `docs`, `release` commands.
- AOT compilation to native binary.
- Release workflow: version bump, compile, tag, push.

### 1.15 Code Quality

- Strict `analysis_options.yaml`: `strict-casts`, `strict-raw-types`, `avoid_dynamic_calls`, `always_use_package_imports`, `unawaited_futures`, and 20+ additional lint rules.
- Only **3 info-level issues** (no errors, no warnings) from `dart analyze`.

---

## 2. What Is MISSING or Needs Work

### 2.1 Blocking Issues

| Issue                                                  | Severity     | Details                                                                                                                                                                                                                                                                                |
| ------------------------------------------------------ | ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **No LICENSE file**                                    | **Critical** | No `LICENSE` file exists at `/Users/helge/code/glue/cli/LICENSE` or repo root. Required for open-source release and pub.dev.                                                                                                                                                           |
| **pubspec.yaml incomplete for pub.dev**                | **Critical** | Missing `homepage`, `repository`, `issue_tracker`, `topics`, `screenshots`, and `funding` fields. pub.dev uses these for discoverability and scoring.                                                                                                                                  |
| **No `example/` directory**                            | **High**     | pub.dev expects an `example/` directory. Not strictly required for a CLI tool, but improves pub.dev score.                                                                                                                                                                             |
| **Mistral missing from `--provider` CLI allowed list** | **High**     | In `/Users/helge/code/glue/cli/bin/glue.dart` line 41, `allowed: const ['anthropic', 'openai', 'ollama']` does not include `'mistral'`. Running `glue -p mistral` will fail with a usage error despite the Mistral provider being fully implemented. The help text also omits mistral. |
| **`const version` hardcoded in `bin/glue.dart`**       | **Medium**   | Version is duplicated between `pubspec.yaml` (line 3) and `bin/glue.dart` (line 8). The `just release` command only updates `pubspec.yaml`, so the CLI `--version` output will drift. Consider using `build_runner` or reading from pubspec at build time.                             |

### 2.2 Known Bugs (from `docs/bugs.md`)

| Bug                                        | Impact                                                                                                                                                             |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `/model` command does not update `_config` | Low -- display uses `_modelName` but subagent spawning/session metadata may read stale config. (Partial fix noted in CHANGELOG but `docs/bugs.md` still lists it.) |
| `/skills` uses stale cached data           | Low -- skills loaded once at startup, not refreshed when user edits skill files mid-session.                                                                       |
| **Bash mode has no tab-completion**        | Medium UX gap -- Tab does nothing in bash mode. Documented with detailed fix approaches in `docs/bugs.md`.                                                         |

### 2.3 Missing Features for Competitive Parity

| Feature                          | Priority | Notes                                                                                                                     |
| -------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------- |
| **`--prompt` / stdin pipe mode** | High     | No way to pass a prompt non-interactively (e.g., `echo "fix bug" \| glue` or `glue --prompt "..."`) for CI/scripting use. |
| **Context window management**    | High     | No visible conversation truncation or summarization strategy when approaching token limits.                               |
| **Cost tracking display**        | Medium   | `SessionMeta` has `cost` field but no evidence of real-time cost display or budget limits.                                |
| **`--provider mistral`**         | High     | (See blocking issue above.)                                                                                               |
| **Conversation export**          | Low      | No `--export` to markdown/JSON for sharing.                                                                               |
| **Plugin/extension API**         | Low      | Tools are hardcoded; no dynamic tool loading beyond skills.                                                               |

### 2.4 Documentation Gaps

| Gap                                                                                      | Priority                    |
| ---------------------------------------------------------------------------------------- | --------------------------- |
| No `CONTRIBUTING.md`                                                                     | High for open source        |
| No `SECURITY.md`                                                                         | Medium for open source      |
| No `CODE_OF_CONDUCT.md`                                                                  | Medium for open source      |
| Changelog `[Unreleased]` section is very large -- needs trimming into versioned releases | Medium                      |
| `docs/bugs.md` lists `/model` bug as open but CHANGELOG says it was fixed                | Low -- needs reconciliation |

### 2.5 pub.dev Readiness Analysis

Current `pubspec.yaml` analysis against pub.dev requirements:

| Criterion                  | Status      | Notes                                                                                                               |
| -------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------- |
| `name`                     | OK          | `glue` -- short, lowercase, valid                                                                                   |
| `description`              | OK          | 47 chars, under 180 limit                                                                                           |
| `version`                  | OK          | `0.1.0` semver                                                                                                      |
| `environment.sdk`          | OK          | `>=3.4.0 <4.0.0`                                                                                                    |
| `homepage` or `repository` | **MISSING** | Required for pub.dev scoring; at least one needed                                                                   |
| `issue_tracker`            | **MISSING** | Recommended                                                                                                         |
| `topics`                   | **MISSING** | Up to 5 topics for pub.dev categorization (e.g., `cli`, `ai`, `llm`, `agent`, `terminal`)                           |
| `LICENSE` file             | **MISSING** | pub.dev will show "unknown license"                                                                                 |
| `example/`                 | **MISSING** | Affects pub.dev score                                                                                               |
| Dart 3 / null safety       | OK          | Dart >=3.4 implies sound null safety                                                                                |
| No `publish_to: none`      | OK          | Package is publishable                                                                                              |
| `executables`              | **MISSING** | For CLI tools, `pubspec.yaml` should declare `executables: { glue: glue }` so `dart pub global activate glue` works |

**pub.dev score estimate:** ~90/160 points without fixes. With LICENSE + repository + topics + example, would reach ~130-140/160.

### 2.6 Static Analysis

- 3 info-level lint issues remain (no errors/warnings). These should be cleaned up before release for a zero-issue `dart analyze --fatal-infos` pass.

---

## 3. Minimum Viable Release Checklist

### Must-Have (Gate Release)

- [ ] Add LICENSE file (MIT or Apache-2.0 recommended)
- [ ] Add `repository` URL to `pubspec.yaml`
- [ ] Add `topics` to `pubspec.yaml` (e.g., `[cli, ai, llm, agent, terminal]`)
- [ ] Add `executables` to `pubspec.yaml` for `dart pub global activate`
- [ ] Add `mistral` to `--provider` allowed list in `bin/glue.dart`
- [ ] Fix version duplication (pubspec.yaml vs bin/glue.dart hardcoded const)
- [ ] Fix the 3 remaining `dart analyze` info-level issues
- [ ] Reconcile `docs/bugs.md` with actual fix status
- [ ] Verify all 452+ tests pass on CI (Ubuntu, macOS, Windows)
- [ ] Tag `v0.1.0` and verify GitHub Release workflow produces all 3 binaries
- [ ] Verify `dart pub publish --dry-run` succeeds

### Should-Have (First Week)

- [ ] Add `CONTRIBUTING.md`
- [ ] Add `SECURITY.md` with vulnerability reporting process
- [ ] Add `example/` directory with a minimal usage example
- [ ] Add `issue_tracker` URL to `pubspec.yaml`
- [ ] Collapse `[Unreleased]` CHANGELOG into `[0.1.0]` and structure for future releases
- [ ] Add `--prompt` / stdin pipe mode for non-interactive use
- [ ] Add `homepage` URL once website/landing page is finalized

### Nice-to-Have (First Month)

- [ ] `CODE_OF_CONDUCT.md`
- [ ] Bash mode tab-completion (approach 2 from `docs/bugs.md`)
- [ ] Context window management / conversation summarization
- [ ] Real-time cost tracking display
- [ ] GitHub Releases with SHA256 checksums for binaries
- [ ] Homebrew formula or other package manager distribution
- [ ] Screenshots/GIF in README for visual impact

---

## 4. Recommended Release Phases

### Phase 0: Pre-release Cleanup (1-2 days)

Fix all "Must-Have" items. This is a small, well-scoped batch:

- Add LICENSE, update pubspec.yaml fields, fix the Mistral CLI flag, resolve version duplication, clean lint issues.
- Run `dart pub publish --dry-run` to catch any remaining pub.dev blockers.
- Tag `v0.1.0-rc.1` for internal validation.

### Phase 1: Soft Launch v0.1.0 (Day 3)

- Tag `v0.1.0`, push tag to trigger release build workflow.
- Publish to pub.dev via `dart pub publish`.
- GitHub Release with Linux/macOS/Windows binaries.
- Announce in limited channels (personal network, Dart/Flutter communities).
- Monitor for crash reports, API compatibility issues across providers.

### Phase 2: Harden v0.1.x (Weeks 1-2)

- Address feedback from soft launch.
- Add "Should-Have" items: CONTRIBUTING.md, SECURITY.md, example/, --prompt mode.
- Patch releases (v0.1.1, v0.1.2) for bugs discovered in the wild.
- Improve README with screenshots/GIFs.

### Phase 3: Feature Release v0.2.0 (Weeks 3-6)

- Context window management and conversation summarization.
- Bash mode tab-completion.
- Cost tracking display.
- Homebrew formula or Scoop manifest for easier installation.
- Consider broader announcement (HN, Reddit, X).

### Phase 4: Stability Release v0.3.0+ (Months 2-3)

- Plugin/extension API for custom tools.
- MCP (Model Context Protocol) server support.
- Conversation export.
- Performance profiling and optimization.
- Move toward v1.0.0 based on user feedback.

---

## 5. Summary

The Glue CLI is remarkably feature-complete for a v0.1.0 pre-release: 97 source files, 93 test files, 452+ tests, 4 LLM providers, 12 tools, full observability stack, Docker sandbox, skills system, web tools with browser automation, and 6 CI workflows. The architecture is clean, well-documented internally, and has strict static analysis enforced.

The **critical blockers** for public release are small and mechanical: no LICENSE file, incomplete `pubspec.yaml` metadata, and the Mistral provider missing from the CLI flag's allowed list. These can be resolved in a single focused session. The codebase itself is release-ready.

**Key files referenced in this analysis:**

- `/Users/helge/code/glue/cli/pubspec.yaml`
- `/Users/helge/code/glue/cli/bin/glue.dart`
- `/Users/helge/code/glue/cli/lib/glue.dart`
- `/Users/helge/code/glue/cli/CHANGELOG.md`
- `/Users/helge/code/glue/cli/README.md`
- `/Users/helge/code/glue/cli/docs/bugs.md`
- `/Users/helge/code/glue/cli/analysis_options.yaml`
- `/Users/helge/code/glue/.github/workflows/` (all 6 workflow files)
- `/Users/helge/code/glue/.github/dependabot.yml`
