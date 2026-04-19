# Models & Providers

Glue supports four LLM providers. Set your preferred provider and model in config or via environment variables.

## Providers

### Anthropic (default)

Set `ANTHROPIC_API_KEY`. Default model: `claude-sonnet-4-6`.

### OpenAI

Set `OPENAI_API_KEY`. Default model: `gpt-4.1`.

### Mistral

Set `MISTRAL_API_KEY`. Default model: `mistral-large-latest`.

### Ollama

Local inference, no API key needed. Default model: `llama3.2`. Runs on `localhost:11434`.

## Default Models

| Provider  | Default Model                |
| --------- | ---------------------------- |
| Anthropic | `claude-sonnet-4-6`          |
| OpenAI    | `gpt-4.1`                    |
| Mistral   | `mistral-large-latest`       |
| Ollama    | `llama3.2` (localhost:11434) |

## Switching Models at Runtime

```bash
/model              # show current model
/model gpt-5        # switch model
/models             # list available models
```

Or via CLI flag:

```bash
glue -m claude-opus-4-6
```

## Profiles

Named profiles let you assign different models to subagents:

```yaml
profiles:
  fast:
    provider: "openai"
    model: "gpt-4.1-nano"
  deep:
    provider: "anthropic"
    model: "claude-opus-4-6"
```

::: info
Profiles are defined in your Glue config file. Each subagent can reference a profile by name to use its provider and model settings.
:::

## See also

- [ModelRegistry](/api/config/model-registry)
- [LlmFactory](/api/llm/llm-factory)
- [AnthropicClient](/api/llm/anthropic-client)
- [OpenAiClient](/api/llm/openai-client)
- [OllamaClient](/api/llm/ollama-client)
