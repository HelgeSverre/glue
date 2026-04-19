---
pageClass: page-marketing
title: Models and Providers
description: The providers and models Glue ships with, how configuration binds to them, and how to add an OpenAI-compatible endpoint.
sidebar: false
aside: false
outline: false
---

<script setup>
import recommended from './generated/models.recommended.json'

const hosted = recommended.filter((m) => m.provider !== 'ollama')
const local = recommended.filter((m) => m.provider === 'ollama')
</script>

# Models and Providers

Glue ships with a curated catalog. Selected models are always written as
`provider/model` — for example `anthropic/claude-sonnet-4.6`. Credentials never
live in project config; they come from env vars, `~/.glue/credentials.json`, or
an OS keychain layer later.

Canonical source: [`docs/reference/models.yaml`](https://github.com/helgesverre/glue/blob/main/docs/reference/models.yaml).
<FeatureStatus status="shipping" />

## Recommended coding models

<ModelTable
  caption="Anthropic, OpenAI, Gemini, Mistral, Groq, and other hosted providers."
  :models="hosted"
/>

## Local models

<ModelTable
  caption="Ollama runs on localhost; capability depends on hardware."
  :models="local"
/>

## OpenAI-compatible endpoints

Any endpoint that speaks the OpenAI wire format can be added with
`adapter: openai`. That includes Groq, Ollama, vLLM, LM Studio, and
OpenRouter — each listed separately in the catalog because their base URLs
and auth differ, not because the wire format does.

<ConfigSnippet title="~/.glue/config.yaml — OpenAI-compatible provider">

```yaml
provider: local-vllm
model: local-vllm/llama-3-70b

providers:
  local-vllm:
    adapter: openai
    base_url: http://localhost:8000/v1
    auth:
      api_key: none
```

</ConfigSnippet>

## Minimal config

<ConfigSnippet title="~/.glue/config.yaml — quickest path to a running agent">

```yaml
provider: anthropic
model: anthropic/claude-sonnet-4.6
```

</ConfigSnippet>

Credentials come from the environment in this example
(`ANTHROPIC_API_KEY`). To override any catalog entry or add a provider of
your own, drop a `models.yaml` into `~/.glue/` — it merges on top of the
bundled catalog.

<p><a href="/docs/using-glue/models-and-providers">Configuration reference →</a></p>
