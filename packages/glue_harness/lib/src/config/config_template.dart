String buildConfigTemplate() {
  return r'''# Glue config.yaml
#
# Path:
#   ~/.glue/config.yaml
#   or $GLUE_HOME/config.yaml when GLUE_HOME is set.
#
# Precedence for every setting below:
#   CLI flag → environment variable → this file → built-in default.
#
# Credentials do NOT belong here. Use environment variables or
# ~/.glue/credentials.json (created interactively by `/provider add`).
# Provider→env-var mapping lives in the model catalog
# (`glue catalog show` or docs/reference/models.yaml).
#
# Companion files:
#   ~/.glue/credentials.json        # API keys & OAuth tokens
#   ~/.glue/models.yaml             # local catalog overrides (optional)
#   ~/.glue/cache/models.yaml       # refreshed remote catalog (written by `glue catalog refresh`)
#
# ─── Models ────────────────────────────────────────────────────────────────

# Primary model for agent conversations.
# CLI `--model` and `GLUE_MODEL` override this.
# active_model: anthropic/claude-sonnet-4-6

# Cheap/fast model for session titles, summaries, and small subagent calls.
# Omit to use the catalog's default small_model.
# small_model: anthropic/claude-haiku-4-5

# Named model shortcuts. Reference with `/model @<name>`.
# Value must be a `<provider>/<model>` id — not a structured block.
# profiles:
#   fast: anthropic/claude-haiku-4-5
#   reasoning: openai/o3
#   local: ollama/qwen3-coder:30b

# Model catalog refresh.
# refresh: never | manual | daily | startup
# remote_url defaults to the bundled getglue.dev catalog; override for a
# private/internal catalog mirror.
# catalog:
#   refresh: manual
#   remote_url: https://getglue.dev/models.yaml

# ─── Behavior ──────────────────────────────────────────────────────────────

# Tool approval. `GLUE_APPROVAL_MODE` overrides.
#   confirm  → prompt for every tool call.
#   auto     → run anything not on the deny list without prompting.
approval_mode: confirm

# Background session-title generation. `GLUE_TITLE_GENERATION_ENABLED` overrides.
title_generation_enabled: true

# Anthropic prompt caching — adds `cache_control: ephemeral` to requests.
# Cuts cost dramatically on long agent loops. Disable for proxies that reject
# the field, or to measure baseline latency.
# `GLUE_ANTHROPIC_PROMPT_CACHE` overrides.
anthropic_prompt_cache: true

# Maximum tool-output lines surfaced to the model from a single `bash` call.
# Output beyond this is truncated; the model sees a "[output truncated]" tail.
# bash:
#   max_lines: 200

# Shell execution. `GLUE_SHELL` / `GLUE_SHELL_MODE` override.
#   executable: leave unset to auto-detect from $SHELL (then zsh/bash).
#   mode: non_interactive | interactive | login.
# shell:
#   executable: zsh
#   mode: non_interactive

# Extra skill search paths. `GLUE_SKILLS_PATHS` is prepended.
# skills:
#   paths:
#     - /opt/glue-skills
#     - ~/work/team-skills

# ─── Runtime (where shell + file tools execute) ────────────────────────────

# Active sandbox runtime. `GLUE_RUNTIME` overrides.
#   host    → run directly on this machine. Default. No isolation.
#   docker  → ephemeral container per session (needs `docker:` block below).
#   daytona → cloud sandbox (see `daytona:` block).
#   sprites → local persistent VMs via the `sprite` CLI (see `sprites:` block).
#   modal   → Modal.com sandboxes (see `modal:` block).
runtime: host

# Docker runtime. Activates when `runtime: docker` or `GLUE_DOCKER_ENABLED=1`.
# Env overrides: GLUE_DOCKER_IMAGE, GLUE_DOCKER_SHELL, GLUE_DOCKER_MOUNTS.
# docker:
#   enabled: false
#   image: ubuntu:24.04
#   shell: sh
#   fallback_to_host: true        # fall back to host runtime if docker is unavailable
#   mounts:
#     - /absolute/path            # bind mount, rw
#     - /absolute/path:ro         # bind mount, read-only

# Daytona cloud runtime. Activates when `runtime: daytona`.
# Env overrides: DAYTONA_API_KEY, DAYTONA_API_BASE_URL, DAYTONA_SNAPSHOT,
# DAYTONA_TOOLBOX_BASE_URL.
# daytona:
#   api_key: your-daytona-key
#   api_base_url: https://app.daytona.io/api     # use https://app-eu.daytona.io/api for EU
#   snapshot: null                                # null → org default snapshot
#   toolbox_base_url: null                        # only for staging / proxy testing

# Sprites runtime. Activates when `runtime: sprites`.
# Env overrides: SPRITES_CLI, SPRITES_NAME, SPRITES_DELETE_ON_CLOSE.
# sprites:
#   sprite_cli: sprite                           # path to the `sprite` binary
#   sprite_name: null                             # null → create+name on demand
#   delete_on_close: true

# Modal runtime. Activates when `runtime: modal`.
# Env overrides: MODAL_PYTHON, MODAL_CLI, MODAL_APP, MODAL_IMAGE,
# MODAL_SANDBOX_TIMEOUT, MODAL_DELETE_ON_CLOSE.
# modal:
#   python_path: null                            # null → auto-detect
#   modal_cli: modal
#   app_name: glue
#   image: null                                   # null → modal default
#   sandbox_timeout_seconds: 1800
#   delete_on_close: true

# ─── MCP servers ───────────────────────────────────────────────────────────

# Model Context Protocol servers. Stdio or HTTP/WebSocket transports.
# Use ${VAR} for env-var interpolation in commands, args, env, urls, and tokens.
# mcp:
#   call_timeout_seconds: 30        # default per-tool call timeout
#   subprocess_env: allowlist       # allowlist | full (env exposed to stdio servers)
#
#   tool_policy:
#     auto_approve:                 # exact `<server>.<tool>` patterns or `<server>.*`
#       - github.search_repositories
#     deny:
#       - github.delete_repository
#
#   reconnect:
#     enabled: true
#     initial_delay_ms: 500
#     max_delay_ms: 30000
#     max_attempts: 10
#
#   servers:
#     # Stdio server example.
#     github:
#       command: npx
#       args: [-y, "@modelcontextprotocol/server-github"]
#       env:
#         GITHUB_PERSONAL_ACCESS_TOKEN: ${GITHUB_TOKEN}
#       working_directory: null
#       enabled: true
#       call_timeout_seconds: 60     # per-server override
#
#     # HTTP server example with bearer auth.
#     internal-tools:
#       url: https://mcp.internal.example/v1
#       auth:
#         kind: bearer
#         token: ${INTERNAL_MCP_TOKEN}
#       enabled: true
#
#     # OAuth server example.
#     atlassian:
#       url: https://mcp.atlassian.com/v1/sse
#       auth:
#         kind: oauth

# ─── Web tools ─────────────────────────────────────────────────────────────

# web:
#   fetch:
#     jina_api_key: your-jina-key            # also: JINA_API_KEY
#     allow_jina_fallback: true              # fall back to Jina reader when direct fetch fails
#     timeout_seconds: 30
#     max_bytes: 5242880                     # hard cap on response size
#     max_tokens: 50000                      # default truncation for tool-result payload
#
#   search:
#     provider: brave                        # brave | tavily | firecrawl | duckduckgo
#     brave_api_key: your-brave-key          # also: BRAVE_API_KEY
#     tavily_api_key: your-tavily-key        # also: TAVILY_API_KEY
#     firecrawl_api_key: your-firecrawl-key  # also: FIRECRAWL_API_KEY
#     firecrawl_base_url: https://api.firecrawl.dev
#     timeout_seconds: 20
#     max_results: 8
#
#   pdf:
#     mistral_api_key: your-mistral-key      # falls back to credentials store
#     openai_api_key: your-openai-key        # falls back to credentials store
#     ocr_provider: mistral                  # mistral | openai. GLUE_OCR_PROVIDER overrides.
#     max_bytes: 20971520
#     timeout_seconds: 60
#     enable_ocr_fallback: true
#
#   browser:
#     backend: local                         # local | docker | steel | browserbase | browserless | anchor | hyperbrowser
#     headed: false                          # local backend only — show the browser window
#
#     docker:
#       image: browserless/chrome:latest
#       port: 3000
#
#     steel:
#       api_key: your-steel-key              # also: STEEL_API_KEY
#
#     browserbase:
#       api_key: your-browserbase-key        # also: BROWSERBASE_API_KEY
#       project_id: your-browserbase-project # also: BROWSERBASE_PROJECT_ID
#
#     browserless:
#       base_url: https://chrome.browserless.io
#       api_key: your-browserless-key        # also: BROWSERLESS_API_KEY
#
#     anchor:
#       api_key: your-anchor-key             # also: ANCHOR_API_KEY
#
#     hyperbrowser:
#       api_key: your-hyperbrowser-key       # also: HYPERBROWSER_API_KEY

# ─── Observability ─────────────────────────────────────────────────────────

# When debug is true, every outbound HTTP call is traced to
# ~/.glue/logs/http-YYYY-MM-DD.jsonl with redacted headers and bodies.
# Precedence: --debug flag > GLUE_DEBUG env > observability.debug YAML > default.
# observability:
#   debug: false
#   max_body_bytes: 65536          # per-request body cap before truncation
#   redact: true                   # mask api keys / bearer tokens in logged bodies
#
#   # OpenTelemetry trace export. Endpoint can also come from
#   # OTEL_EXPORTER_OTLP_TRACES_ENDPOINT, OTEL_EXPORTER_OTLP_ENDPOINT, or
#   # PHOENIX_COLLECTOR_ENDPOINT. Headers can also come from
#   # OTEL_EXPORTER_OTLP_TRACES_HEADERS or OTEL_EXPORTER_OTLP_HEADERS
#   # (comma-separated key=value). PHOENIX_API_KEY auto-fills `Authorization`.
#   otel:
#     enabled: false
#     endpoint: https://app.phoenix.arize.com/s/your-org
#     service_name: glue
#     timeout_milliseconds: 10000
#     headers:
#       Authorization: Bearer your-token
#     resource_attributes:
#       openinference.project.name: glue
''';
}
