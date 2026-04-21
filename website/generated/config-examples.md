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

# docker:
#   enabled: false
#   image: ubuntu:24.04
#   shell: sh
#   fallback_to_host: true
#   mounts:
#     - /absolute/path
#     - /absolute/path:ro

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

# debug: false

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
