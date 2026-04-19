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
    { id: 'devstral-latest', provider: 'mistral', recommended: true, capabilities: ['chat','tools','json','coding'], notes: 'Agentic coding — Mistral default.' },
    { id: 'mistral-large-latest', provider: 'mistral', recommended: true, capabilities: ['chat','tools','vision','json','coding'], notes: 'Flagship multimodal.' },
    { id: 'mistral-medium-latest', provider: 'mistral', recommended: true, capabilities: ['chat','tools','vision','json'], notes: 'Balanced cost/quality.' },
    { id: 'mistral-small-latest', provider: 'mistral', recommended: true, capabilities: ['chat','tools','vision','json','reasoning'], notes: 'Fast with reasoning toggle.' },
    { id: 'gpt-oss-120b', provider: 'groq', recommended: true, capabilities: ['chat','tools','json','reasoning','coding'], notes: 'Fast reasoning + coding at Groq speed.' },
  ]"
/>

## Local models

<ModelTable
  caption="Ollama runs on localhost; capability depends on hardware."
  :models="[
    { id: 'qwen3-coder:30b', provider: 'ollama', recommended: true, capabilities: ['chat','tools','json','coding','local'], notes: 'Local default. 30B/3.3B MoE, 256K context.' },
    { id: 'qwen3.6:35b', provider: 'ollama', recommended: true, capabilities: ['chat','tools','vision','json','reasoning','coding','local'], notes: 'Latest Qwen generalist. Agentic coding + thinking.' },
    { id: 'gemma4:26b', provider: 'ollama', recommended: true, capabilities: ['chat','tools','vision','json','coding','local'], notes: 'Google, native function-calling. 256K context.' },
    { id: 'devstral-small-2:24b', provider: 'ollama', recommended: true, capabilities: ['chat','tools','json','coding','local'], notes: 'Dense, fits 16 GB GPU. 68% SWE-bench.' },
    { id: 'qwen2.5-coder:32b', provider: 'ollama', recommended: true, capabilities: ['chat','tools','json','coding','local'], notes: 'Aider-verified 73.7%. Safe fallback.' },
    { id: 'qwen3:8b', provider: 'ollama', recommended: true, capabilities: ['chat','tools','json','local'], notes: 'Low-end floor, 16 GB laptops.' },
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
