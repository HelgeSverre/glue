<!-- Generated from docs/reference/models.yaml. Do not edit by hand. -->
<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->

# Model catalog

Source: [`docs/reference/models.yaml`](https://github.com/helgesverre/glue/blob/main/docs/reference/models.yaml)

## Capabilities

| Capability | Meaning |
| --- | --- |
| `chat` | Text chat. |
| `tools` | Tool calling or function calling. |
| `vision` | Image input. |
| `files` | File upload or file reference support. |
| `json` | Structured JSON output. |
| `reasoning` | Explicit reasoning effort or thinking controls. |
| `coding` | Strong code generation and code review behavior. |
| `local` | Runs locally or on a user-controlled endpoint. |
| `browser` | Suitable for browser/research workflows. |

## Models

| ID | Recommended | Capabilities | Context | Speed | Cost | Notes |
| --- | :---: | --- | ---: | --- | --- | --- |
| `anthropic/claude-sonnet-4.6` | ★ | chat, tools, vision, files, json, reasoning, coding | 200000 | standard | high | Default high-quality coding model. |
| `anthropic/claude-opus-4.6` | ★ | chat, tools, vision, files, json, reasoning, coding | 200000 | slower | premium | Use for difficult architecture, debugging, and long investigations. |
| `anthropic/claude-haiku-4.5` | ★ | chat, tools, vision, json, coding | 200000 | fast | low | Good small_model candidate for titles, summaries, and quick checks. |
| `openai/gpt-5.4` | ★ | chat, tools, vision, files, json, reasoning, coding | 400000 | standard | high | Frontier general-purpose and agentic coding model. |
| `openai/gpt-5.4-mini` | ★ | chat, tools, vision, json, coding | 400000 | fast | low | Default small_model candidate. |
| `openai/gpt-5.3-codex` | ★ | chat, tools, files, json, reasoning, coding | 400000 | standard | high | Coding-specialized model. |
| `openai/gpt-5.2` |  | chat, tools, vision, files, json, reasoning, coding | 400000 | standard | high | Keep visible only if users still rely on it. |
| `gemini/gemini-pro-latest` | ★ | chat, tools, vision, files, json, reasoning, coding | 1000000 | standard | medium | Stable alias for the current Pro-class Gemini model. |
| `gemini/gemini-flash-latest` | ★ | chat, tools, vision, files, json, coding | 1000000 | fast | low | Fast model for summarization, extraction, and browser-heavy work. |
| `mistral/mistral-large-latest` | ★ | chat, tools, json, coding | 128000 | standard | medium | General Mistral default. |
| `mistral/mistral-small-latest` | ★ | chat, tools, json | 128000 | fast | low | Good for quick tasks and summaries. |
| `mistral/codestral-latest` | ★ | chat, tools, json, coding | 256000 | standard | medium | Coding-focused Mistral model. |
| `groq/qwen/qwen3-coder` | ★ | chat, tools, json, coding | 262000 | fast | low | Fast coding model through an OpenAI-compatible endpoint. |
| `groq/llama-3.3-70b-versatile` | ★ | chat, tools, json | 128000 | fast | low | General fast hosted open model. |
| `ollama/qwen2.5-coder:32b` | ★ | chat, json, coding, local | 32768 | depends_on_hardware | local | Sensible local coding default if the machine can run it. |
| `ollama/devstral:latest` | ★ | chat, tools, json, coding, local | 128000 | depends_on_hardware | local | Local agentic coding candidate. |
| `ollama/llama3.2:latest` |  | chat, json, local | 128000 | depends_on_hardware | local | General local fallback. |
| `openrouter/anthropic/claude-sonnet-4.6` | ★ | chat, tools, vision, files, json, reasoning, coding | 200000 | standard | provider_routed | Useful when users want one router key. |
| `openrouter/openai/gpt-5.4-mini` | ★ | chat, tools, vision, json, coding | 400000 | fast | provider_routed | Small-model fallback through a router. |
| `openrouter/google/gemini-flash-latest` | ★ | chat, tools, vision, files, json, browser | 1000000 | fast | provider_routed | Good for research and extraction workflows. |
| `local-vllm/local-model` |  | chat, json, local | — | depends_on_hardware | local | Rename this entry to the model served by vLLM, LM Studio, or another local gateway. |

