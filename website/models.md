---
pageClass: page-marketing
title: Models and Providers
description: The providers and models Glue ships with, how configuration binds to them, and how to add an OpenAI-compatible endpoint.
sidebar: false
aside: false
outline: false
---

# Models and Providers

Glue ships with a curated catalog. Selected models are always written as
`provider/model` — for example `anthropic/claude-sonnet-4.6`. Credentials never
live in project config; they come from env vars, `~/.glue/credentials.json`, or
an OS keychain layer later.

Canonical source: [`docs/reference/models.yaml`](https://github.com/helgesverre/glue/blob/main/docs/reference/models.yaml).
<FeatureStatus status="shipping" />

## Recommended coding models

<ModelTable
  caption="Anthropic, OpenAI, Gemini, Mistral, Groq."
  :models="[
    { id: 'claude-opus-4-7', provider: 'anthropic', recommended: true, capabilities: ['chat','tools','vision','files','json','reasoning','coding'], notes: 'Most capable — agentic coding and long-horizon work.' },
    { id: 'claude-sonnet-4-6', provider: 'anthropic', recommended: true, capabilities: ['chat','tools','vision','files','json','reasoning','coding'], notes: 'Default. High-quality coding model.' },
    { id: 'claude-opus-4-6', provider: 'anthropic', capabilities: ['chat','tools','vision','files','json','reasoning','coding'], notes: 'Architecture and long investigations.' },
    { id: 'claude-haiku-4-5', provider: 'anthropic', recommended: true, capabilities: ['chat','tools','vision','json','coding'], notes: 'Fast small-model candidate.' },
    { id: 'gpt-5.4', provider: 'openai', recommended: true, capabilities: ['chat','tools','vision','files','json','reasoning','coding'], notes: 'Frontier agentic coding.' },
    { id: 'gpt-5.4-mini', provider: 'openai', recommended: true, capabilities: ['chat','tools','vision','json','coding'], notes: 'Default small_model candidate.' },
    { id: 'gpt-5.3-codex', provider: 'openai', capabilities: ['chat','tools','files','json','reasoning','coding'], notes: 'Coding-specialized.' },
    { id: 'gemini-pro-latest', provider: 'gemini', recommended: true, capabilities: ['chat','tools','vision','files','json','reasoning','coding'], notes: '1M context; stable Pro alias.' },
    { id: 'gemini-flash-latest', provider: 'gemini', recommended: true, capabilities: ['chat','tools','vision','files','json','coding'], notes: 'Fast; good for extraction and browser work.' },
    { id: 'mistral-large-latest', provider: 'mistral', recommended: true, capabilities: ['chat','tools','json','coding'], notes: 'Mistral default.' },
    { id: 'codestral-latest', provider: 'mistral', recommended: true, capabilities: ['chat','tools','json','coding'], notes: 'Coding-focused Mistral.' },
    { id: 'qwen/qwen3-coder', provider: 'groq', recommended: true, capabilities: ['chat','tools','json','coding'], notes: 'Fast coding via OpenAI-compatible endpoint.' },
  ]"
/>

## Local models

<ModelTable
  caption="Ollama runs on localhost; capability depends on hardware."
  :models="[
    { id: 'qwen2.5-coder:32b', provider: 'ollama', recommended: true, capabilities: ['chat','json','coding','local'], notes: 'Sensible local coding default.' },
    { id: 'devstral:latest', provider: 'ollama', recommended: true, capabilities: ['chat','tools','json','coding','local'], notes: 'Local agentic coding candidate.' },
    { id: 'llama3.2:latest', provider: 'ollama', capabilities: ['chat','json','local'], notes: 'General local fallback.' },
  ]"
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
