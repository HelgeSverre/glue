# `~/.glue/config.yaml` — User Configuration

Primary user-edited configuration file loaded by `GlueConfig.load()`.

Resolution order:

1. CLI overrides (currently `--model`)
2. Environment variables
3. `config.yaml`
4. Defaults

## Example

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
    backend: local       # execution backend: local | docker | steel | browserbase | browserless
    docker_image: browserless/chrome:latest
    docker_port: 3000
    steel_api_key: your-key
    browserbase_api_key: your-key
    browserbase_project_id: your-project
    browserless_api_key: your-key
    browserless_base_url: https://chrome.browserless.io

debug: false

approval_mode: confirm # confirm | auto

skills:
  paths:
    - /opt/glue-skills
```

## Top-Level Fields

| Field | Type | Description |
| --- | --- | --- |
| `provider` | string | Active provider (`anthropic`, `openai`, `mistral`, `ollama`) |
| `model` | string | Active model ID |
| `title_model` | string | Model used for background session title generation |
| `profiles` | map | Named provider/model pairs for subagents |
| `approval_mode` | string | Tool approval policy (`confirm`, `auto`) |
| `skills.paths` | list | Extra skill search paths |

## Environment Overrides (selected)

- Provider/model: `GLUE_PROVIDER`, `GLUE_MODEL`
- API keys: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `MISTRAL_API_KEY`, `GLUE_*`
- Ollama URL: `GLUE_OLLAMA_BASE_URL`, `OLLAMA_BASE_URL`
- Shell: `GLUE_SHELL`, `GLUE_SHELL_MODE`
- Docker: `GLUE_DOCKER_ENABLED`, `GLUE_DOCKER_IMAGE`, `GLUE_DOCKER_SHELL`, `GLUE_DOCKER_MOUNTS`
- Search provider: `GLUE_SEARCH_PROVIDER`
- Skills paths: `GLUE_SKILLS_PATHS`
- Approval mode: `GLUE_APPROVAL_MODE`
- Glue home: `GLUE_HOME` (overrides the default `~/.glue`)

For exact parsing logic, see `lib/src/config/glue_config.dart`.
