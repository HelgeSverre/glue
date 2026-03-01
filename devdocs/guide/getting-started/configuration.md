# Configuration

Glue is configured through YAML config files, environment variables, and CLI flags. This page covers all three and explains how they interact.

## Config Files

Glue loads configuration from two locations:

| Scope       | Path                  | Purpose                                                 |
| ----------- | --------------------- | ------------------------------------------------------- |
| **Global**  | `~/.glue/config.yaml` | User-wide defaults shared across all projects           |
| **Project** | `.glue/config.yaml`   | Project-specific overrides checked into version control |

Project-level values override global values for any keys that are set in both files.

## Full Schema

Below is the complete YAML configuration schema with all supported keys:

```yaml
provider: "anthropic" # anthropic | openai | mistral | ollama
model: "claude-sonnet-4-6"

anthropic:
  api_key: "sk-ant-..."

openai:
  api_key: "sk-..."

bash:
  max_lines: 50

profiles:
  fast:
    provider: "openai"
    model: "gpt-4.1-nano"
  deep:
    provider: "anthropic"
    model: "claude-opus-4-6"
```

::: warning
Avoid committing API keys in config files. Use environment variables for secrets and keep config files for non-sensitive settings like `provider`, `model`, and `profiles`.
:::

### Profiles

Profiles let you define named presets that bundle a provider and model together. Switch between them with the `--profile` flag:

```bash
glue --profile fast "quick refactor on utils"
glue --profile deep "architect a new module"
```

## Environment Variables

Glue reads the following environment variables:

| Variable            | Description                   |
| ------------------- | ----------------------------- |
| `ANTHROPIC_API_KEY` | Anthropic API key             |
| `OPENAI_API_KEY`    | OpenAI API key                |
| `MISTRAL_API_KEY`   | Mistral API key               |
| `GLUE_PROVIDER`     | Override the default provider |
| `GLUE_MODEL`        | Override the default model    |

```bash
# Example: override the provider and model for a single shell session
export GLUE_PROVIDER=openai
export GLUE_MODEL=gpt-4.1
```

## Precedence

When the same setting is defined in multiple places, Glue resolves it using a **first-match-wins** order:

1. **CLI flags** (`--model`, `--provider`)
2. **Environment variables** (`GLUE_MODEL`, `GLUE_PROVIDER`, etc.)
3. **Project config** (`.glue/config.yaml`)
4. **Global config** (`~/.glue/config.yaml`)
5. **Built-in defaults**

::: tip
Use CLI flags for one-off overrides, environment variables for machine-level settings, project config for team-shared defaults, and global config for your personal preferences.
:::

## Default Models

When no model is explicitly configured, Glue uses the following defaults per provider:

| Provider  | Default Model          | Notes                         |
| --------- | ---------------------- | ----------------------------- |
| Anthropic | `claude-sonnet-4-6`    |                               |
| OpenAI    | `gpt-4.1`              |                               |
| Mistral   | `mistral-large-latest` |                               |
| Ollama    | `llama3.2`             | Connects to `localhost:11434` |

## See also

- [GlueConfig](/api/config/glue-config) -- the configuration object API
- [ModelRegistry](/api/config/model-registry) -- how models are registered and resolved
- [ConfigStore](/api/storage/config-store) -- persistence layer for configuration
- [Installation](./installation) -- prerequisites and install steps
- [Quick Start](./quick-start) -- first-session walkthrough
