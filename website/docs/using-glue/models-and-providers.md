# Models & Providers

Glue talks to LLMs through two wire protocols: **Anthropic native** and **OpenAI-compatible**. The OpenAI-compatible adapter covers OpenAI itself plus everything that speaks its API (Mistral, Ollama, Groq, OpenRouter, Gemini, vLLM, …). The full list of providers and models lives in the bundled catalog (browse it at [/models](/models)) and can be extended with a `~/.glue/models.yaml` overlay.

Set credentials with the standard env vars (e.g. `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) or in `~/.glue/credentials.json`. See [Configuration](/docs/getting-started/configuration) for the full list.

## Picking the active model

Set it once in `~/.glue/config.yaml`:

```yaml
active_model: anthropic/claude-sonnet-4-6
```

Override per-invocation with the CLI flag:

```bash
glue -m openai/gpt-4.1
glue -m ollama/qwen3-coder:30b
```

For local Ollama, `ollama/qwen3-coder:30b` is the current recommended coding
model in the bundled catalog.

Or switch interactively:

```text
/model              # open the model picker (browse all models in the catalog)
/model gpt-5        # fuzzy-switch by name
```

## Profiles (model shortcuts)

Profiles are named shortcuts for model refs. They make `/model` switching faster — they do **not** assign models to subagents (subagents take a `model_ref` argument directly when spawned).

Define them in `~/.glue/config.yaml` as a flat map of `name: provider/model`:

```yaml
profiles:
  fast: openai/gpt-4.1-nano
  deep: anthropic/claude-opus-4-6
  local: ollama/qwen3-coder:30b
```

Then switch with the `@` prefix:

```text
/model @fast
/model @deep
```

## Adding a model the catalog doesn't know about

Drop a `models.yaml` into `~/.glue/` with your provider/model entry — it merges on top of the bundled catalog. Or, for any OpenAI-compatible endpoint, define a provider with `adapter: openai` and a custom `base_url`. See [Troubleshooting → "The model I want isn't in the catalog"](/docs/advanced/troubleshooting).

## Catalog CLI

The catalog is layered: **bundled snapshot** (compiled into the binary) → **remote refresh** (cached at `~/.glue/cache/models.yaml`) → **local overlay** (`~/.glue/models.yaml`). Use `glue catalog` to inspect and refresh those layers without starting a session:

```sh
glue catalog refresh          # fetch the canonical models.yaml into the cache
glue catalog show             # print the active merged catalog (yaml)
glue catalog show --json      # same, as JSON
glue catalog path             # report where each layer is resolved from
glue catalog open             # open the canonical URL in your browser
glue catalog open --print     # print the URL instead of launching a browser
glue catalog edit             # open the cached models.yaml in $EDITOR
```

`refresh` writes YAML (not a one-line JSON dump) and preserves comments and key order from the upstream document, so the cached file stays readable in `glue catalog edit`. The canonical URL is `catalog.remote_url` in `~/.glue/config.yaml` if set, otherwise the bundled default. `GLUE_CATALOG_CACHE` overrides the cache path used by `edit`.

## See also

- [Configuration](/docs/getting-started/configuration) — credentials and config keys
- [LlmFactory](/api/agent/llm-factory) — adapter dispatch
- [AnthropicClient](/api/llm/anthropic-client)
- [OpenAiClient](/api/llm/openai-client)
- [OllamaClient](/api/llm/ollama-client)
