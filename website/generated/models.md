<!-- Generated from docs/reference/models.yaml. Do not edit by hand. -->
<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->

# Model catalog

Source: [`docs/reference/models.yaml`](https://github.com/helgesverre/glue/blob/main/docs/reference/models.yaml)

## Capabilities

| Capability | Meaning |
| --- | --- |
| `chat` | Text chat. |
| `streaming` | Incremental token streaming. |
| `tools` | Tool calling or function calling. |
| `parallel_tools` | Parallel tool-call execution in a single turn. |
| `vision` | Image input. |
| `files` | File upload or file reference support. |
| `json` | Structured JSON output. |
| `reasoning` | Explicit reasoning effort or thinking controls. |
| `coding` | Strong code generation and code review behavior. |
| `local` | Runs locally or on a user-controlled endpoint. |
| `browser` | Suitable for browser/research workflows. |
| `binary_tool_results` | Accepts binary or multimodal tool-result payloads. |

## Models

| ID | Recommended | Capabilities | Context | Speed | Cost | Notes |
| --- | :---: | --- | ---: | --- | --- | --- |
| `anthropic/claude-sonnet-4-6` | ★ | chat, tools, vision, files, json, reasoning, coding | 1000000 | standard | high | Default high-quality coding model. |
| `anthropic/claude-opus-4-6` | ★ | chat, tools, vision, files, json, reasoning, coding | 1000000 | slower | premium | Use for difficult architecture, debugging, and long investigations. |
| `anthropic/claude-haiku-4-5` | ★ | chat, tools, vision, json, coding | 200000 | fast | low | Good small_model candidate for titles, summaries, and quick checks. |
| `anthropic/claude-opus-4-7` | ★ | chat, tools, vision, files, json, reasoning, coding | 1000000 | slower | premium | Most capable Claude model — agentic coding and long-horizon work. |
| `openai/gpt-5.4` | ★ | chat, tools, vision, files, json, reasoning, coding | 400000 | standard | high | Frontier general-purpose and agentic coding model. |
| `openai/gpt-5.4-mini` | ★ | chat, tools, vision, json, coding | 400000 | fast | low | Default small_model candidate. |
| `openai/gpt-5.2` |  | chat, tools, vision, files, json, reasoning, coding | 400000 | standard | high | Keep visible only if users still rely on it. |
| `gemini/gemini-pro-latest` | ★ | chat, tools, vision, files, json, reasoning, coding | 1000000 | standard | medium | Stable alias for the current Pro-class Gemini model. |
| `gemini/gemini-flash-latest` | ★ | chat, tools, vision, files, json, coding | 1000000 | fast | low | Fast model for summarization, extraction, and browser-heavy work. |
| `mistral/devstral-latest` | ★ | chat, tools, json, coding | 262000 | standard | medium | Mistral's agentic coding model. Strong tool use. |
| `mistral/mistral-large-latest` | ★ | chat, tools, vision, json, coding | 262000 | standard | medium | Flagship multimodal general-purpose model. |
| `mistral/mistral-medium-latest` | ★ | chat, tools, vision, json | 128000 | standard | medium | Balanced cost/quality option. |
| `mistral/mistral-small-latest` | ★ | chat, tools, vision, json, reasoning | 262000 | fast | low | Fast with reasoning toggle; good for quick tasks. |
| `groq/gpt-oss-120b` | ★ | chat, tools, json, reasoning, coding | 131072 | fast | low | Groq's flagship reasoning + coding model. 120B weights at Groq speed. |
| `groq/gpt-oss-20b` | ★ | chat, tools, json, coding | 131072 | fast | low | Coding-optimized, faster/cheaper than 120B. |
| `groq/llama-3.3-70b-versatile` | ★ | chat, tools, json | 131072 | fast | low | General-purpose alternative. No reasoning mode. |
| `groq/llama-3.1-8b-instant` |  | chat, tools, json | 131072 | fast | low | 8B floor. Fast but tool-loop fragile; use for summaries/titles, not the main agent. |
| `ollama/qwen3-coder:30b` | ★ | chat, tools, json, coding, local | 256000 | depends_on_hardware | local | Consensus local coding agent. 30B/3.3B MoE. ~20 GB VRAM at Q4_K_M. |
| `ollama/qwen3.6:35b` | ★ | chat, tools, vision, json, reasoning, coding, local | 256000 | depends_on_hardware | local | Latest Qwen generalist with agentic coding upgrades. Vision + thinking + tools. ~24 GB at Q4_K_M. |
| `ollama/gemma4:26b` | ★ | chat, tools, vision, json, coding, local | 256000 | depends_on_hardware | local | Google's latest with native function-calling. Multimodal, 256K context. ~18 GB at Q4_K_M. |
| `ollama/devstral-small-2:24b` | ★ | chat, tools, json, coding, local | 128000 | depends_on_hardware | local | Mistral's agentic coding model (Dec 2025). 68% SWE-bench. ~14 GB at Q4_K_M. |
| `ollama/qwen2.5-coder:32b` | ★ | chat, tools, json, coding, local | 32768 | depends_on_hardware | local | Aider-verified 73.7% (GPT-4o class). Safe fallback. |
| `ollama/qwen3:8b` | ★ | chat, tools, json, local | 128000 | depends_on_hardware | local | Low-end floor for tool use. ~5 GB at Q4_K_M. Fits a 16 GB laptop. |
| `ollama/mistral:7b` |  | chat, tools, json, local | 32768 | depends_on_hardware | local | General-purpose, not code-specialized. Tool use works but weaker than Qwen3-Coder. |
| `ollama/gemma3:12b` |  | chat, json, local | 131072 | depends_on_hardware | local | No tools capability; superseded by Gemma 4. Use gemma4:26b instead. |
| `ollama/codellama:13b` |  | chat, json, coding, local | 16384 | depends_on_hardware | local | FIM-lineage code model. Narrates instead of calling tools. Not for agent use. |
| `ollama/codegemma:7b` |  | chat, json, coding, local | 8192 | depends_on_hardware | local | FIM-trained (80% FIM rate). Not designed for agent tool use. |
| `ollama/starcoder2:15b` |  | chat, json, coding, local | 16384 | depends_on_hardware | local | FIM-lineage (BigCode). Code completion, not agent tool use. |
| `ollama/deepseek-coder:33b` |  | chat, json, coding, local | 16384 | depends_on_hardware | local | Legacy DeepSeek code model (no tools). Use qwen3-coder or devstral-small-2 instead. |
| `copilot/claude-sonnet-4-6` | ★ | chat, tools, vision, json, coding | 1000000 | standard | subscription | Uses your GitHub Copilot subscription. |
| `copilot/gpt-4.1` | ★ | chat, tools, json, coding | 128000 | standard | subscription | Uses your GitHub Copilot subscription. |
| `openrouter/claude-sonnet-4-6` | ★ | chat, tools, vision, files, json, reasoning, coding | 1000000 | standard | provider_routed | Useful when users want one router key. |
| `openrouter/gpt-5.4-mini` | ★ | chat, tools, vision, json, coding | 400000 | fast | provider_routed | Small-model fallback through a router. |
| `openrouter/gemini-flash-latest` | ★ | chat, tools, vision, files, json, browser | 1000000 | fast | provider_routed | Good for research and extraction workflows. |
| `local-vllm/local-model` |  | chat, json, local | — | depends_on_hardware | local | Rename this entry to the model served by vLLM, LM Studio, or another local gateway. |

