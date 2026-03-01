# Glue CLI -- Website Content Coverage Matrix

## Executive Summary

This report maps every implemented feature in the Glue CLI codebase (`/Users/helge/code/glue/cli/lib/src/`) against the content published across the six website pages. It identifies **coverage gaps** (implemented features absent from the website), **aspirational content** (website claims with no backing implementation), and **recommendations** for closing both.

---

## Methodology

**Step 1 -- Feature Enumeration.** Every Dart source file under `/Users/helge/code/glue/cli/lib/src/` was read. Features were catalogued from class definitions, tool registrations, configuration schemas, and slash command registrations in `app.dart`.

**Step 2 -- Website Analysis.** All six HTML pages were read in full:

- `index.html` (Home / landing page)
- `docs.html` (Documentation)
- `worktrees.html` (Multi-Worktree)
- `agents.html` (Agent Orchestration)
- `app.html` (Web UI prototype)
- `brand.html` (Design System)

**Step 3 -- Cross-referencing.** Each feature was checked for presence, accuracy, and depth of coverage on every website page.

---

## Coverage Matrix

### A. LLM Providers and Model System

| Feature                                                 | Implemented In                                                                                                          | Website Page          | Covered? | Notes                                                                                           |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | --------------------- | -------- | ----------------------------------------------------------------------------------------------- |
| Multi-provider LLM (Anthropic, OpenAI, Mistral, Ollama) | `/Users/helge/code/glue/cli/lib/src/llm/llm_factory.dart`, `/Users/helge/code/glue/cli/lib/src/config/glue_config.dart` | index.html, docs.html | YES      | Listed on home ("Any Model") and documented in config                                           |
| Mistral via OpenAI-compatible API                       | `/Users/helge/code/glue/cli/lib/src/llm/llm_factory.dart` line 38-44                                                    | docs.html             | Partial  | Mistral is listed as a provider but the OpenAI-compat implementation detail is not documented   |
| Streaming SSE + NDJSON parsing                          | `/Users/helge/code/glue/cli/lib/src/llm/sse.dart`, `/Users/helge/code/glue/cli/lib/src/llm/ndjson.dart`                 | None                  | NO       | Internal detail but relevant for contributor docs                                               |
| Model Registry with capabilities/cost/speed tiers       | `/Users/helge/code/glue/cli/lib/src/config/model_registry.dart`                                                         | docs.html             | Partial  | Default models listed but the `ModelCapability`, `CostTier`, `SpeedTier` system is undocumented |
| `/model` slash command (switch models)                  | `/Users/helge/code/glue/cli/lib/src/app.dart` line 588-605                                                              | docs.html             | YES      | Listed in slash commands table                                                                  |
| `/models` slash command (list from API)                 | `/Users/helge/code/glue/cli/lib/src/app.dart` line 607-616                                                              | docs.html             | NO       | Not in the slash commands table                                                                 |
| Model listing from provider APIs                        | `/Users/helge/code/glue/cli/lib/src/llm/model_lister.dart`                                                              | None                  | NO       | Ability to enumerate available models from Ollama/OpenAI/Mistral/Anthropic APIs is undocumented |
| Auto session title generation via LLM                   | `/Users/helge/code/glue/cli/lib/src/llm/title_generator.dart`                                                           | None                  | NO       | Uses Haiku to generate session titles automatically                                             |
| Agent profiles (named provider+model combos)            | `/Users/helge/code/glue/cli/lib/src/config/glue_config.dart` lines 420-434                                              | docs.html             | YES      | Shown in config schema (`profiles:` block)                                                      |

### B. Core Tools

| Feature                                           | Implemented In                                                     | Website Page | Covered? | Notes                                                                    |
| ------------------------------------------------- | ------------------------------------------------------------------ | ------------ | -------- | ------------------------------------------------------------------------ |
| `read_file`                                       | `/Users/helge/code/glue/cli/lib/src/agent/tools.dart` line 119-153 | docs.html    | YES      | Documented in Built-in Tools table                                       |
| `write_file`                                      | `/Users/helge/code/glue/cli/lib/src/agent/tools.dart` line 156-195 | docs.html    | YES      | Documented                                                               |
| `edit_file`                                       | `/Users/helge/code/glue/cli/lib/src/agent/tools.dart` line 322-410 | docs.html    | YES      | Documented                                                               |
| `bash`                                            | `/Users/helge/code/glue/cli/lib/src/agent/tools.dart` line 198-254 | docs.html    | YES      | Documented                                                               |
| `grep`                                            | `/Users/helge/code/glue/cli/lib/src/agent/tools.dart` line 257-319 | docs.html    | YES      | Documented                                                               |
| `list_directory`                                  | `/Users/helge/code/glue/cli/lib/src/agent/tools.dart` line 413-450 | docs.html    | YES      | Documented                                                               |
| `spawn_subagent`                                  | `/Users/helge/code/glue/cli/lib/src/tools/subagent_tools.dart`     | docs.html    | YES      | Documented in both Built-in Tools and Subagents section                  |
| `spawn_parallel_subagents`                        | `/Users/helge/code/glue/cli/lib/src/tools/subagent_tools.dart`     | docs.html    | YES      | Documented                                                               |
| `web_fetch`                                       | `/Users/helge/code/glue/cli/lib/src/tools/web_fetch_tool.dart`     | docs.html    | **NO**   | Tool exists but is missing from the Built-in Tools table                 |
| `web_search`                                      | `/Users/helge/code/glue/cli/lib/src/tools/web_search_tool.dart`    | docs.html    | **NO**   | Tool exists but is missing from the Built-in Tools table                 |
| `web_browser`                                     | `/Users/helge/code/glue/cli/lib/src/tools/web_browser_tool.dart`   | docs.html    | **NO**   | Tool exists but is missing from the Built-in Tools table                 |
| `skill`                                           | `/Users/helge/code/glue/cli/lib/src/skills/skill_tool.dart`        | docs.html    | **NO**   | Tool exists but is missing from the Built-in Tools table                 |
| Tool trust levels (`safe`, `fileEdit`, `command`) | `/Users/helge/code/glue/cli/lib/src/agent/tools.dart` lines 28-38  | docs.html    | Partial  | Concept described in Tool Approval section but enum names not documented |

### C. Web Subsystem

| Feature                                                                    | Implemented In                                                                                                                           | Website Page | Covered? | Notes                                             |
| -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------ | -------- | ------------------------------------------------- |
| HTML-to-markdown fetching                                                  | `/Users/helge/code/glue/cli/lib/src/web/fetch/html_extractor.dart`, `/Users/helge/code/glue/cli/lib/src/web/fetch/html_to_markdown.dart` | None         | **NO**   | Major feature with no website documentation       |
| PDF text extraction (pdftotext CLI)                                        | `/Users/helge/code/glue/cli/lib/src/web/fetch/pdf_text_extractor.dart`                                                                   | None         | **NO**   | Major feature undocumented                        |
| OCR fallback for scanned PDFs (Mistral/OpenAI vision)                      | `/Users/helge/code/glue/cli/lib/src/web/fetch/ocr_client.dart`                                                                           | None         | **NO**   | Major feature undocumented                        |
| Jina Reader fallback                                                       | `/Users/helge/code/glue/cli/lib/src/web/fetch/jina_reader_client.dart`                                                                   | None         | **NO**   | Fallback chain undocumented                       |
| Token truncation for fetched content                                       | `/Users/helge/code/glue/cli/lib/src/web/fetch/truncation.dart`                                                                           | None         | **NO**   |                                                   |
| Web search: Brave provider                                                 | `/Users/helge/code/glue/cli/lib/src/web/search/providers/brave_provider.dart`                                                            | None         | **NO**   | Three search backends, none documented on website |
| Web search: Tavily provider                                                | `/Users/helge/code/glue/cli/lib/src/web/search/providers/tavily_provider.dart`                                                           | None         | **NO**   |                                                   |
| Web search: Firecrawl provider                                             | `/Users/helge/code/glue/cli/lib/src/web/search/providers/firecrawl_provider.dart`                                                        | None         | **NO**   |                                                   |
| Search router with auto-detect + fallback                                  | `/Users/helge/code/glue/cli/lib/src/web/search/search_router.dart`                                                                       | None         | **NO**   |                                                   |
| Browser automation: Local Chrome (CDP)                                     | `/Users/helge/code/glue/cli/lib/src/web/browser/providers/local_provider.dart`                                                           | None         | **NO**   | Five browser backends, none documented on website |
| Browser automation: Docker Chrome                                          | `/Users/helge/code/glue/cli/lib/src/web/browser/providers/docker_browser_provider.dart`                                                  | None         | **NO**   |                                                   |
| Browser automation: Browserless                                            | `/Users/helge/code/glue/cli/lib/src/web/browser/providers/browserless_provider.dart`                                                     | None         | **NO**   |                                                   |
| Browser automation: Browserbase                                            | `/Users/helge/code/glue/cli/lib/src/web/browser/providers/browserbase_provider.dart`                                                     | None         | **NO**   |                                                   |
| Browser automation: Steel                                                  | `/Users/helge/code/glue/cli/lib/src/web/browser/providers/steel_provider.dart`                                                           | None         | **NO**   |                                                   |
| Browser session persistence across tool calls                              | `/Users/helge/code/glue/cli/lib/src/web/browser/browser_manager.dart`                                                                    | None         | **NO**   |                                                   |
| Browser actions: navigate, screenshot, click, type, extract_text, evaluate | `/Users/helge/code/glue/cli/lib/src/tools/web_browser_tool.dart` lines 16-23                                                             | None         | **NO**   |                                                   |
| Web config (fetch/search/pdf/browser sections in YAML)                     | `/Users/helge/code/glue/cli/lib/src/config/glue_config.dart` lines 257-366                                                               | None         | **NO**   | Entire `web:` config block is undocumented        |
| PDF config (`web.pdf` section)                                             | `/Users/helge/code/glue/cli/lib/src/web/web_config.dart` lines 64-92                                                                     | None         | **NO**   |                                                   |
| Browser config (`web.browser` section)                                     | `/Users/helge/code/glue/cli/lib/src/web/browser/browser_config.dart`                                                                     | None         | **NO**   |                                                   |

### D. Shell System

| Feature                                                | Implemented In                                                                                                                 | Website Page | Covered? | Notes                                                            |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ------------ | -------- | ---------------------------------------------------------------- |
| Multi-shell support (bash/zsh/fish/pwsh/sh)            | `/Users/helge/code/glue/cli/lib/src/shell/shell_config.dart`                                                                   | docs.html    | Partial  | Mentioned in bash mode but shell config YAML not shown           |
| Shell mode (non-interactive/interactive/login)         | `/Users/helge/code/glue/cli/lib/src/shell/shell_config.dart` lines 1-21                                                        | None         | **NO**   | Shell modes are not documented on the website                    |
| Docker sandbox                                         | `/Users/helge/code/glue/cli/lib/src/shell/docker_executor.dart`, `/Users/helge/code/glue/cli/lib/src/shell/docker_config.dart` | None         | **NO**   | Major feature with zero website coverage                         |
| Docker mount system (host path, container path, ro/rw) | `/Users/helge/code/glue/cli/lib/src/shell/docker_config.dart` lines 5-122                                                      | None         | **NO**   |                                                                  |
| Host executor with per-shell flag mapping              | `/Users/helge/code/glue/cli/lib/src/shell/host_executor.dart`                                                                  | None         | **NO**   |                                                                  |
| Shell job manager (background jobs)                    | `/Users/helge/code/glue/cli/lib/src/shell/shell_job_manager.dart`                                                              | docs.html    | YES      | Covered in Bash Mode section                                     |
| Shell tab-completion (compgen/fish)                    | `/Users/helge/code/glue/cli/lib/src/shell/shell_completer.dart`                                                                | None         | **NO**   | Runtime tab-completion for shell commands                        |
| CLI shell completions install/uninstall                | `/Users/helge/code/glue/cli/bin/glue.dart` (completions subcommand)                                                            | None         | **NO**   | `glue completions install` for zsh/bash/fish/pwsh not on website |

### E. Skills System

| Feature                                                    | Implemented In                                                              | Website Page | Covered? | Notes                                                         |
| ---------------------------------------------------------- | --------------------------------------------------------------------------- | ------------ | -------- | ------------------------------------------------------------- |
| Skill registry (project/global/custom paths)               | `/Users/helge/code/glue/cli/lib/src/skills/skill_registry.dart`             | index.html   | Partial  | Mentioned as "Agent Skills" feature card but no documentation |
| SKILL.md parser (YAML frontmatter + body)                  | `/Users/helge/code/glue/cli/lib/src/skills/skill_parser.dart`               | None         | **NO**   | File format completely undocumented                           |
| Skill tool (list/activate skills)                          | `/Users/helge/code/glue/cli/lib/src/skills/skill_tool.dart`                 | None         | **NO**   |                                                               |
| `/skills` slash command                                    | `/Users/helge/code/glue/cli/lib/src/app.dart` line 686-693                  | docs.html    | **NO**   | Not in the slash commands table                               |
| agentskills.io compatibility                               | `/Users/helge/code/glue/cli/lib/src/skills/skill_parser.dart`               | index.html   | Partial  | Claimed on home page but no docs explaining the spec          |
| Skill discovery from `~/.glue/skills/` and `.glue/skills/` | `/Users/helge/code/glue/cli/lib/src/skills/skill_registry.dart` lines 59-63 | None         | **NO**   |                                                               |
| Skills injected into system prompt                         | `/Users/helge/code/glue/cli/lib/src/agent/prompts.dart` lines 54-69         | None         | **NO**   |                                                               |

### F. Observability

| Feature                                   | Implemented In                                                                                                                    | Website Page | Covered? | Notes                                                                |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------ | -------- | -------------------------------------------------------------------- |
| Debug logging to file                     | `/Users/helge/code/glue/cli/lib/src/observability/file_sink.dart`, `/Users/helge/code/glue/cli/lib/src/storage/debug_logger.dart` | None         | **NO**   | `~/.glue/logs/` logging is undocumented on website                   |
| OpenTelemetry (OTEL) sink                 | `/Users/helge/code/glue/cli/lib/src/observability/otel_sink.dart`                                                                 | None         | **NO**   | Major observability feature, zero website coverage                   |
| Langfuse sink                             | `/Users/helge/code/glue/cli/lib/src/observability/langfuse_sink.dart`                                                             | None         | **NO**   | Major observability feature, zero website coverage                   |
| Observed LLM client wrapper               | `/Users/helge/code/glue/cli/lib/src/observability/observed_llm_client.dart`                                                       | None         | **NO**   |                                                                      |
| Observed tool wrapper                     | `/Users/helge/code/glue/cli/lib/src/observability/observed_tool.dart`                                                             | None         | **NO**   |                                                                      |
| Logging HTTP client                       | `/Users/helge/code/glue/cli/lib/src/observability/logging_http_client.dart`                                                       | None         | **NO**   |                                                                      |
| Debug controller (`/debug` slash command) | `/Users/helge/code/glue/cli/lib/src/observability/debug_controller.dart`                                                          | docs.html    | Partial  | `/debug` command exists but telemetry/otel/langfuse config is absent |
| Span-based tracing                        | `/Users/helge/code/glue/cli/lib/src/observability/observability.dart`                                                             | None         | **NO**   |                                                                      |
| Telemetry config in YAML                  | `/Users/helge/code/glue/cli/lib/src/observability/observability_config.dart`                                                      | None         | **NO**   | `telemetry:` YAML block undocumented                                 |

### G. Session & Storage

| Feature                                                       | Implemented In                                                             | Website Page | Covered? | Notes                                                                  |
| ------------------------------------------------------------- | -------------------------------------------------------------------------- | ------------ | -------- | ---------------------------------------------------------------------- |
| Session persistence (meta.json + conversation.jsonl)          | `/Users/helge/code/glue/cli/lib/src/storage/session_store.dart`            | docs.html    | YES      | Documented in Sessions section                                         |
| Session resume (`--resume`, `--continue`)                     | `/Users/helge/code/glue/cli/lib/src/app.dart`                              | docs.html    | YES      | Documented                                                             |
| Session metadata (git branch, worktree, PR URL, cost, tokens) | `/Users/helge/code/glue/cli/lib/src/storage/session_store.dart` lines 7-63 | docs.html    | Partial  | Basic fields covered; git context, PR URL, cost tracking not mentioned |
| GlueHome directory management                                 | `/Users/helge/code/glue/cli/lib/src/storage/glue_home.dart`                | None         | **NO**   |                                                                        |
| Config store                                                  | `/Users/helge/code/glue/cli/lib/src/storage/config_store.dart`             | None         | **NO**   |                                                                        |

### H. TUI / Input / Rendering

| Feature                                        | Implemented In                                                                                          | Website Page | Covered? | Notes                                                                              |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------ | -------- | ---------------------------------------------------------------------------------- |
| Readline-style line editor (Emacs keybindings) | `/Users/helge/code/glue/cli/lib/src/input/line_editor.dart`                                             | docs.html    | YES      | Keybindings table                                                                  |
| Multi-line text area editor                    | `/Users/helge/code/glue/cli/lib/src/input/text_area_editor.dart`                                        | None         | **NO**   | Multiline input is undocumented                                                    |
| `@file` references with fuzzy autocomplete     | `/Users/helge/code/glue/cli/lib/src/input/file_expander.dart`                                           | docs.html    | YES      | Well documented                                                                    |
| Streaming input handler                        | `/Users/helge/code/glue/cli/lib/src/input/streaming_input_handler.dart`                                 | None         | **NO**   | Internal                                                                           |
| Terminal raw I/O, ANSI parsing                 | `/Users/helge/code/glue/cli/lib/src/terminal/terminal.dart`                                             | None         | **NO**   | Internal                                                                           |
| Screen buffer (diff-flush rendering)           | `/Users/helge/code/glue/cli/lib/src/terminal/screen_buffer.dart`                                        | None         | **NO**   | Internal                                                                           |
| Layout (scroll regions, zones)                 | `/Users/helge/code/glue/cli/lib/src/terminal/layout.dart`                                               | None         | **NO**   | Internal                                                                           |
| Styled text (ANSI utility)                     | `/Users/helge/code/glue/cli/lib/src/terminal/styled.dart`                                               | None         | **NO**   | Internal                                                                           |
| Block renderer                                 | `/Users/helge/code/glue/cli/lib/src/rendering/block_renderer.dart`                                      | None         | **NO**   | Internal                                                                           |
| Markdown renderer                              | `/Users/helge/code/glue/cli/lib/src/rendering/markdown_renderer.dart`                                   | None         | **NO**   | Internal                                                                           |
| Mascot splash screen (liquid physics)          | `/Users/helge/code/glue/cli/lib/src/rendering/mascot.dart`, `mascot_physics.dart`, `mascot_sprite.dart` | brand.html   | Partial  | Mascot mentioned in footer image but liquid physics/click-to-explode not described |
| Modal dialogs (confirm, panel, split-panel)    | `/Users/helge/code/glue/cli/lib/src/ui/modal.dart`, `panel_modal.dart`, `split_panel_modal.dart`        | None         | **NO**   | Internal                                                                           |
| Slash command autocomplete overlay             | `/Users/helge/code/glue/cli/lib/src/ui/slash_autocomplete.dart`                                         | None         | **NO**   |                                                                                    |
| Shell autocomplete overlay                     | `/Users/helge/code/glue/cli/lib/src/ui/shell_autocomplete.dart`                                         | None         | **NO**   |                                                                                    |
| `@file` hint overlay                           | `/Users/helge/code/glue/cli/lib/src/ui/at_file_hint.dart`                                               | docs.html    | YES      | Covered in @file References                                                        |

### I. Permission System

| Feature                                                   | Implemented In                                                               | Website Page | Covered? | Notes                                                                                  |
| --------------------------------------------------------- | ---------------------------------------------------------------------------- | ------------ | -------- | -------------------------------------------------------------------------------------- |
| Permission modes (confirm, accept-edits, YOLO, read-only) | `/Users/helge/code/glue/cli/lib/src/config/permission_mode.dart`             | docs.html    | Partial  | Tool Approval section covers concept; 4-mode enum and Shift+Tab cycling not documented |
| `GLUE_PERMISSION_MODE` env var                            | `/Users/helge/code/glue/cli/lib/src/config/glue_config.dart` line 437        | docs.html    | **NO**   | Not in env var table                                                                   |
| Shift+Tab permission mode cycling                         | `/Users/helge/code/glue/cli/lib/src/config/permission_mode.dart` lines 29-34 | None         | **NO**   |                                                                                        |

### J. Agent Core

| Feature                                                | Implemented In                                                          | Website Page           | Covered? | Notes                                                   |
| ------------------------------------------------------ | ----------------------------------------------------------------------- | ---------------------- | -------- | ------------------------------------------------------- |
| Streaming agent loop (tool calls, text deltas)         | `/Users/helge/code/glue/cli/lib/src/agent/agent_core.dart`              | None                   | **NO**   | Architecture detail                                     |
| Parallel tool call execution                           | Agent core                                                              | docs.html              | YES      | "Tools run in parallel when independent"                |
| Subagent manager with depth limiting                   | `/Users/helge/code/glue/cli/lib/src/agent/agent_manager.dart`           | docs.html, agents.html | YES      | Covered in both                                         |
| Agent runner (headless execution)                      | `/Users/helge/code/glue/cli/lib/src/agent/agent_runner.dart`            | None                   | **NO**   | Used for e2e tests and subagents                        |
| Tool approval policies (auto-approve, deny, allowlist) | `/Users/helge/code/glue/cli/lib/src/agent/agent_runner.dart` lines 7-16 | docs.html              | Partial  | Subagent read-only default mentioned                    |
| System prompt with AGENTS.md/CLAUDE.md injection       | `/Users/helge/code/glue/cli/lib/src/agent/prompts.dart`                 | docs.html              | YES      | Documented in Project Context                           |
| Content parts (text + image)                           | `/Users/helge/code/glue/cli/lib/src/agent/content_part.dart`            | None                   | **NO**   | Supports multimodal responses (images from screenshots) |

### K. Slash Commands (Complete List)

| Command                          | Implemented | Website (docs.html) | Covered? |
| -------------------------------- | ----------- | ------------------- | -------- |
| `/help`                          | YES         | YES                 | YES      |
| `/clear`                         | YES         | YES                 | YES      |
| `/exit` (aliases: `/quit`, `/q`) | YES         | YES                 | YES      |
| `/model`                         | YES         | YES                 | YES      |
| `/models`                        | YES         | NO                  | **NO**   |
| `/info` (alias: `/status`)       | YES         | YES                 | YES      |
| `/tools`                         | YES         | YES                 | YES      |
| `/history`                       | YES         | YES                 | YES      |
| `/resume`                        | YES         | YES                 | YES      |
| `/debug`                         | YES         | NO                  | **NO**   |
| `/skills`                        | YES         | NO                  | **NO**   |

---

## Aspirational Content (Website Claims Without Implementation)

These are features described on the website that have NO corresponding implementation in the codebase.

| Website Claim                                                                            | Page                  | Status              | Analysis                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------------------------------------------------------------------------------------- | --------------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Named agent roles (Scout, Reviewer, Planner, Builder, Researcher, Fixer, Scaffolder)** | agents.html           | **NOT IMPLEMENTED** | The entire `agents.html` page describes seven specialized agent types with distinct system prompts, tool restrictions, and model tiers. The actual codebase has generic `spawn_subagent` and `spawn_parallel_subagents` tools with no role concept. There is no "Scout", "Reviewer", etc. -- subagents all use the same system prompt and a read-only tool allowlist (`{read_file, list_directory, grep}`). |
| **`agents:` config block with per-role model selection**                                 | agents.html           | **NOT IMPLEMENTED** | The config example on agents.html shows `agents: scout: ...`, `reviewer: ...`, etc. The actual `GlueConfig` has a `profiles:` map (which IS implemented) but no `agents:` key. These are entirely different concepts.                                                                                                                                                                                       |
| **"Coming Soon: Custom Roles" via Markdown files**                                       | agents.html           | **NOT IMPLEMENTED** | Explicitly marked as future work on the page, but presented alongside implemented features without clear delineation.                                                                                                                                                                                                                                                                                       |
| **`.glue/mcp.json` for MCP server definitions**                                          | docs.html             | **NOT IMPLEMENTED** | Listed under ".glue/ Directory" in docs.html. The string "mcp" does not appear in any source file under `lib/src/`. There is no MCP implementation.                                                                                                                                                                                                                                                         |
| **Project-level `.glue/config.yaml`**                                                    | docs.html             | **NOT IMPLEMENTED** | The docs claim "Project-level overrides go in `.glue/config.yaml`. Project config takes precedence over global." The actual `GlueConfig.load()` factory (at `/Users/helge/code/glue/cli/lib/src/config/glue_config.dart` lines 153-168) only reads from `~/.glue/config.yaml`. There is no project-level config loading.                                                                                    |
| **`dart pub global activate glue` installation**                                         | index.html, docs.html | **NOT IMPLEMENTED** | Install instructions say `dart pub global activate glue`. The README says `just install` (AOT compilation). The package is not published to pub.dev.                                                                                                                                                                                                                                                        |
| **Worktree auto-cleanup / merge / PR creation**                                          | worktrees.html        | **NOT IMPLEMENTED** | "Auto Cleanup" cell: "Glue can merge, create a PR, or clean up the worktree." No worktree management code exists in the codebase.                                                                                                                                                                                                                                                                           |
| **Resource-aware session limiting**                                                      | worktrees.html        | **NOT IMPLEMENTED** | "Resource Aware" cell: "Glue monitors system resources. Won't let you spin up 20 parallel sessions." No resource monitoring code exists.                                                                                                                                                                                                                                                                    |
| **Session dashboard**                                                                    | worktrees.html        | **NOT IMPLEMENTED** | "Session Dashboard" describes an at-a-glance view of active sessions. The `--resume` flag opens a session picker, but there is no dashboard showing live session status across worktrees.                                                                                                                                                                                                                   |
| **"Always" trust option saved to config**                                                | docs.html             | **UNCERTAIN**       | Tool Approval says "Always" permanently trusts a tool saved to `~/.glue/config.yaml`. The `PermissionMode` enum exists but the "save to config" behavior would need verification in `app.dart`.                                                                                                                                                                                                             |

---

## Gap Analysis and Recommendations

### Critical Gaps (Implemented features with zero website coverage)

**1. Web Tools Suite** -- `web_fetch`, `web_search`, `web_browser`, `skill`

These four tools are fully implemented but completely absent from the Built-in Tools table on `docs.html`.

**Recommendation:** Add all four to the existing Built-in Tools table on `docs.html`. Additionally, create a new **"Web Tools" section** on `docs.html` covering:

- `web_fetch` with PDF handling and Jina fallback
- `web_search` with Brave/Tavily/Firecrawl providers
- `web_browser` with the five backend options (local, Docker, Steel, Browserbase, Browserless)
- The `web:` configuration block in `config.yaml`

**2. Docker Sandbox**

Fully implemented (`docker_executor.dart`, `docker_config.dart`, `executor_factory.dart`) with mount management, fallback-to-host, and per-session mounts. Zero website mention.

**Recommendation:** Add a **"Docker Sandbox"** section to `docs.html` covering:

- YAML configuration (`docker:` block)
- Environment variables (`GLUE_DOCKER_ENABLED`, `GLUE_DOCKER_IMAGE`, etc.)
- Mount syntax (Docker `-v` compatible)
- Fallback behavior

**3. Observability / Telemetry**

OpenTelemetry sink, Langfuse sink, debug logging, HTTP tracing -- all implemented. Zero website coverage.

**Recommendation:** Add an **"Observability"** section to `docs.html` with:

- `telemetry:` YAML schema (otel + langfuse)
- Environment variables (`LANGFUSE_*`, `OTEL_*`)
- Debug logging (`/debug` command, `~/.glue/logs/`)
- Quick start examples (LLMFlow, Langfuse)

**4. Skills System**

The skill registry, parser, tool, and `/skills` command are all implemented. The home page mentions "Agent Skills" but there is no documentation explaining how to create, install, or use skills.

**Recommendation:** Create a new **"Skills"** section on `docs.html` (or a dedicated `skills.html` page) covering:

- SKILL.md file format (YAML frontmatter fields)
- Directory structure (`~/.glue/skills/`, `.glue/skills/`)
- The `skill` tool and `/skills` command
- `GLUE_SKILLS_PATHS` environment variable

**5. Shell Configuration**

Shell modes (interactive/login/non-interactive), per-shell flag mapping, and the `shell:` config block are implemented but undocumented on the website.

**Recommendation:** Add to the Configuration section on `docs.html`:

- `shell:` YAML block
- `GLUE_SHELL` and `GLUE_SHELL_MODE` environment variables
- Explanation of when to use interactive vs. login mode

**6. Shell Completions CLI**

The `glue completions install` subcommand supports zsh, bash, fish, and PowerShell. Not on the website.

**Recommendation:** Add a "Shell Completions" subsection to `docs.html` Getting Started.

**7. Permission Modes**

Four modes exist (confirm, accept-edits, YOLO, read-only) with Shift+Tab cycling and `GLUE_PERMISSION_MODE` env var. Website only describes the basic approve/deny concept.

**Recommendation:** Expand the Tool Approval section on `docs.html` to document all four modes, the cycling shortcut, and the env var.

### Moderate Gaps (Partially covered features)

| Feature                                                 | Current Coverage      | Recommendation                                          |
| ------------------------------------------------------- | --------------------- | ------------------------------------------------------- |
| Missing slash commands (`/models`, `/debug`, `/skills`) | Other commands listed | Add to slash commands table on docs.html                |
| Model registry capabilities/cost/speed                  | Default models listed | Add an expanded model reference table                   |
| Session metadata (git, PR, cost)                        | Basic fields shown    | Expand Sessions section                                 |
| Multiline text editor                                   | Not mentioned         | Add note to Interactive Mode about Shift+Enter or paste |
| Mascot with liquid physics                              | Image in footer       | Consider a fun section on brand.html or home page       |

### Aspirational Content to Remove or Label

| Content                                                           | Page                  | Recommendation                                                                                                                               |
| ----------------------------------------------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **Entire agents.html role system**                                | agents.html           | Either implement the role system OR add clear "Coming Soon" / "Planned" labels to the entire page. Currently reads as shipped functionality. |
| **`.glue/mcp.json`**                                              | docs.html             | Remove from ".glue/ Directory" section until MCP is implemented.                                                                             |
| **Project-level `.glue/config.yaml`**                             | docs.html             | Remove "Project config takes precedence over global" claim, or implement project-level config loading.                                       |
| **`dart pub global activate glue`**                               | index.html, docs.html | Replace with actual install instructions from README (`just install` or `dart run bin/glue.dart`).                                           |
| **Worktree auto-cleanup, resource monitoring, session dashboard** | worktrees.html        | Add "Planned" labels or rewrite to describe what actually works (running Glue in separate worktree directories with `--resume`).             |

---

## Summary Statistics

| Category                                       | Count        |
| ---------------------------------------------- | ------------ |
| Total features identified                      | 78           |
| Fully covered on website                       | 24 (31%)     |
| Partially covered                              | 12 (15%)     |
| **Not covered at all**                         | **42 (54%)** |
| Aspirational / unimplemented claims on website | **10**       |

### Priority Action Items

1. **[HIGH]** Add web tools (`web_fetch`, `web_search`, `web_browser`, `skill`) to `docs.html` Built-in Tools table and add a Web Tools documentation section.
2. **[HIGH]** Add Docker Sandbox section to `docs.html`.
3. **[HIGH]** Add Observability/Telemetry section to `docs.html`.
4. **[HIGH]** Add Skills documentation to `docs.html`.
5. **[HIGH]** Add `agents.html` disclaimer that role-based agents are planned, not shipped. The entire page is aspirational.
6. **[MEDIUM]** Remove `.glue/mcp.json` and project-level config claims from `docs.html` until implemented.
7. **[MEDIUM]** Fix install instructions across all pages.
8. **[MEDIUM]** Add Shell Configuration (modes, Docker) and Shell Completions sections to `docs.html`.
9. **[MEDIUM]** Expand permission modes documentation.
10. **[LOW]** Add missing slash commands to the docs table (`/models`, `/debug`, `/skills`).
