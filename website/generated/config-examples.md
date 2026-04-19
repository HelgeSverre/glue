<!-- Generated from docs/reference/config-yaml.md. Do not edit by hand. -->
<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->

# Config examples

Extracted from the `~/.glue/config.yaml` reference. Keep editing
the source file, not this one.

## Example 1

```yaml
provider: anthropic
model: claude-sonnet-4-6

anthropic:
  api_key: sk-ant-...

openai:
  api_key: sk-...

mistral:
  api_key: mk-...

ollama:
  base_url: http://localhost:11434

title_model: claude-haiku-4-5-20251001

profiles:
  fast:
    provider: anthropic
    model: claude-haiku-3-5

bash:
  max_lines: 50

shell:
  executable: zsh
  mode: non_interactive # non_interactive | interactive | login

docker:
  enabled: false
  image: ubuntu:24.04
  shell: sh
  fallback_to_host: true
  mounts:
    - /abs/path
    - /abs/path:ro

web:
  fetch:
    jina_api_key: your-key
  search:
    provider: brave      # brave | tavily | firecrawl
    brave_api_key: your-key
    tavily_api_key: your-key
    firecrawl_api_key: your-key
    firecrawl_base_url: https://api.firecrawl.dev
  pdf:
    enabled: true
    ocr_provider: mistral # mistral | openai
    mistral_api_key: your-key
    openai_api_key: your-key
  browser:
    backend: local       # execution backend: local | docker | steel | browserbase | browserless | anchor
    docker_image: browserless/chrome:latest
    docker_port: 3000
    steel_api_key: your-key
    browserbase_api_key: your-key
    browserbase_project_id: your-project
    browserless_api_key: your-key
    browserless_base_url: https://chrome.browserless.io
    anchor_api_key: your-key

debug: false

approval_mode: confirm # confirm | auto

skills:
  paths:
    - /opt/glue-skills
```

