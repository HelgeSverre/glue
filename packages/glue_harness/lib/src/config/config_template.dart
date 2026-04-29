String buildConfigTemplate() {
  return r'''# Glue config.yaml
#
# Path:
#   ~/.glue/config.yaml
#   or $GLUE_HOME/config.yaml when GLUE_HOME is set.
#
# Credentials do not need to live here. Prefer environment variables or
# ~/.glue/credentials.json for API keys.

# Primary model for agent conversations. CLI --model and GLUE_MODEL override it.
# active_model: anthropic/claude-sonnet-4.6

# Cheap/fast model for session titles and other background tasks.
# When omitted, Glue uses the catalog default small model.
# small_model: anthropic/claude-haiku-4.5

# Named model shortcuts for /model and future profile-aware workflows.
# profiles:
#   fast: anthropic/claude-haiku-4.5
#   reasoning: openai/gpt-5.4

# Model catalog refresh behavior.
# catalog:
#   refresh: manual              # never | manual | daily | startup
#   remote_url: https://example.com/models.yaml

# Tool-output display defaults.
# bash:
#   max_lines: 200

# Shell execution. GLUE_SHELL and GLUE_SHELL_MODE override these.
# shell:
#   executable: zsh
#   mode: non_interactive        # non_interactive | interactive | login

# Docker command execution. Env overrides include GLUE_DOCKER_ENABLED,
# GLUE_DOCKER_IMAGE, GLUE_DOCKER_SHELL, and GLUE_DOCKER_MOUNTS.
# docker:
#   enabled: false
#   image: ubuntu:24.04
#   shell: sh
#   fallback_to_host: true
#   mounts:
#     - /absolute/path
#     - /absolute/path:ro

# Web tools.
# web:
#   fetch:
#     jina_api_key: your-jina-key
#     allow_jina_fallback: true
#     timeout_seconds: 30
#     max_bytes: 5242880
#     max_tokens: 50000
#
#   search:
#     provider: brave            # brave | tavily | firecrawl
#     brave_api_key: your-brave-key
#     tavily_api_key: your-tavily-key
#     firecrawl_api_key: your-firecrawl-key
#     firecrawl_base_url: https://api.firecrawl.dev
#     timeout_seconds: 20
#     max_results: 8
#
#   pdf:
#     mistral_api_key: your-mistral-key
#     openai_api_key: your-openai-key
#     ocr_provider: mistral      # mistral | openai
#     max_bytes: 20971520
#     timeout_seconds: 60
#     enable_ocr_fallback: true
#
#   browser:
#     backend: local             # local | docker | steel | browserbase | browserless | anchor | hyperbrowser
#     headed: false
#     docker:
#       image: browserless/chrome:latest
#       port: 3000
#     steel:
#       api_key: your-steel-key
#     browserbase:
#       api_key: your-browserbase-key
#       project_id: your-browserbase-project
#     browserless:
#       base_url: https://chrome.browserless.io
#       api_key: your-browserless-key
#     anchor:
#       api_key: your-anchor-key
#     hyperbrowser:
#       api_key: your-hyperbrowser-key

# observability: debug logging and http tracing.
# When debug is enabled, every outbound HTTP call is traced to
# ~/.glue/logs/http-YYYY-MM-DD.jsonl with redacted headers and bodies.
# Precedence: --debug flag > GLUE_DEBUG env > observability.debug YAML > default.
# observability:
#   debug: false           # or set GLUE_DEBUG=1, or run with --debug
#   max_body_bytes: 65536  # per-request body cap in bytes before truncation
#   redact: true           # mask api keys/bearer tokens in logged bodies
#   otel:
#     enabled: false
#     endpoint: https://app.phoenix.arize.com/s/your-org
#     headers:
#       Authorization: Bearer your-token
#     service_name: glue
#     resource_attributes:
#       openinference.project.name: glue

# Tool approval mode. GLUE_APPROVAL_MODE overrides this.
# approval_mode: confirm         # confirm | auto

# Disable background session-title generation when set to false.
# GLUE_TITLE_GENERATION_ENABLED overrides this.
# title_generation_enabled: true

# Extra skill search paths. GLUE_SKILLS_PATHS is prepended.
# skills:
#   paths:
#     - /opt/glue-skills
''';
}
