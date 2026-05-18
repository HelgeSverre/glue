<!-- Generated from docs/reference/config-yaml.md. Do not edit by hand. -->
<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->

# Config examples

Extracted from the `~/.glue/config.yaml` reference. Keep editing
the source file, not this one.

## Example 1

```yaml
# Primary model for agent conversations. CLI --model and GLUE_MODEL override it.
# active_model: anthropic/claude-sonnet-4-6

# Cheap/fast model for session titles and other background tasks.
# small_model: anthropic/claude-haiku-4-5

# Named model shortcuts.
# profiles:
#   fast: anthropic/claude-haiku-4-5
#   reasoning: openai/gpt-5.4

# catalog:
#   refresh: manual              # never | manual | daily | startup
#   remote_url: https://example.com/models.yaml

# bash:
#   max_lines: 200

# shell:
#   executable: zsh
#   mode: non_interactive        # non_interactive | interactive | login

# Runtime adapter selection. Defaults to host. Set to docker, daytona,
# sprites, or modal to route command + filesystem work elsewhere.
# Overridden by GLUE_RUNTIME.
# runtime: host

# docker:
#   enabled: false
#   image: ubuntu:24.04
#   shell: sh
#   fallback_to_host: true
#   mounts:
#     - /absolute/path
#     - /absolute/path:ro

# daytona:
#   api_key: env:DAYTONA_API_KEY
#   api_base_url: https://app.daytona.io/api    # US default; EU: https://app-eu.daytona.io/api
#   # toolbox_base_url: https://proxy.staging   # proxy override; usually omit
#   # snapshot: my-snapshot-id                  # org default if omitted

# sprites:
#   sprite_cli: sprite                          # path to the `sprite` binary
#   # sprite_name: my-sandbox                   # reuse a named sprite across sessions
#   delete_on_close: true                       # auto-sleep + delete on session end

# modal:
#   app_name: glue                              # Modal App that hosts the sandbox
#   # python_path: /opt/venvs/glue/bin/python   # interpreter with `modal` importable
#   modal_cli: modal                            # used only for `glue doctor` auth check
#   # image: python:3.12-slim                   # registry tag; default is Modal's Debian base
#   sandbox_timeout_seconds: 1800               # hard cap; sandbox terminates after this
#   delete_on_close: true                       # terminate on session end

# web:
#   fetch:
#     jina_api_key: your-jina-key
#     allow_jina_fallback: true
#     timeout_seconds: 30
#     max_bytes: 5242880
#     max_tokens: 50000
#
#   search:
#     provider: brave            # brave | tavily | firecrawl | duckduckgo
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

# observability:
#   debug: false
#   max_body_bytes: 65536
#   redact: true
#   otel:
#     enabled: true
#     endpoint: https://app.phoenix.arize.com/s/helge-sverre
#     headers:
#       Authorization: Bearer <token>
#     service_name: glue
#     resource_attributes:
#       openinference.project.name: glue

# approval_mode: confirm         # confirm | auto

# title_generation_enabled: true

# skills:
#   paths:
#     - /opt/glue-skills
```

## Example 2

```yaml
web:
  browser:
    anchor:
      api_key: your-anchor-key
    hyperbrowser:
      api_key: your-hyperbrowser-key
```
