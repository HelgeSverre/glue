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
| `openai/o3` | ★ | chat, tools, json, reasoning, coding | 200000 | slower | high | Reasoning-specialized flagship. State of the art on Codeforces / SWE-bench / MMMU; use for hard debugging, proofs, and multi-step planning. |
| `openai/o4-mini` | ★ | chat, tools, json, reasoning, coding | 200000 | fast | low | Small + fast reasoning model. Best price/quality point for iterative coding with structured thinking. |
| `openai/gpt-5.2` |  | chat, tools, vision, files, json, reasoning, coding | 400000 | standard | high | Legacy frontier model — superseded by GPT-5.4. Kept for users with pinned configs. |
| `gemini/gemini-pro-latest` | ★ | chat, tools, vision, files, json, reasoning, coding | 1000000 | standard | medium | Stable alias for the current Pro-class model. Tracking the 3.1 Pro → 3 Pro transition as those exit preview; Gemini 2.5 Pro retires 2026-06-17. |
| `gemini/gemini-flash-latest` | ★ | chat, tools, vision, files, json, coding | 1000000 | fast | low | Fast model for summarization, extraction, and browser-heavy work. Gemini 3 Flash (preview) reports ~78% SWE-bench Verified — strong agentic-coding candidate once GA. Gemini 2.5 Flash retires 2026-06-17. |
| `mistral/devstral-latest` | ★ | chat, tools, json, coding | 262000 | standard | medium | Mistral's agentic coding model. Strong tool use. |
| `mistral/mistral-large-latest` | ★ | chat, tools, vision, json, coding | 262000 | standard | medium | Flagship multimodal general-purpose model. |
| `mistral/mistral-small-latest` | ★ | chat, tools, vision, json, reasoning, coding | 262000 | fast | low | Unified reasoning + coding + vision (Small 4, March 2026). Strong small-model default; cheaper than Medium with better agentic behavior. |
| `mistral/magistral-medium-latest` | ★ | chat, tools, json, reasoning | 262000 | standard | medium | Pure reasoning model. Use when you need explicit long-chain thinking; not a general chat pick. |
| `mistral/mistral-medium-latest` |  | chat, tools, vision, json | 128000 | standard | medium | Legacy middle tier — outclassed by Small 4 on cost/quality after the March 2026 unification. |
| `groq/llama-4-scout-17b-16e-instruct` | ★ | chat, tools, vision, json, coding | 128000 | fast | low | Native multimodal MoE in production on Groq. Strong speed/quality default as of 2026-04. |
| `groq/llama-4-maverick-17b-128e-instruct` | ★ | chat, tools, vision, json, coding | 128000 | fast | low | Larger Llama 4 variant — more capable, still Groq-fast. |
| `groq/gpt-oss-120b` | ★ | chat, tools, json, reasoning, coding | 131072 | fast | low | OpenAI's open-weight reasoning + coding model. 120B weights at Groq speed. |
| `groq/gpt-oss-20b` | ★ | chat, tools, json, coding | 131072 | fast | low | Coding-optimized, faster/cheaper than 120B. |
| `groq/llama-3.3-70b-versatile` |  | chat, tools, json | 131072 | fast | low | Previous-generation general-purpose. Superseded by Llama 4 Scout for most uses. |
| `groq/llama-3.1-8b-instant` |  | chat, tools, json | 131072 | fast | low | 8B floor. Fast but tool-loop fragile; use for summaries/titles, not the main agent. |
| `ollama/qwen3-coder:30b` | ★ | chat, tools, json, coding, local | 256000 | depends_on_hardware | local | Consensus local coding agent. 30B/3.3B MoE. ~20 GB VRAM at Q4_K_M. |
| `ollama/qwen3-coder-next:80b` | ★ | chat, tools, json, coding, local | 256000 | depends_on_hardware | local | 2026-04 flagship local coder. 3B/80B MoE; ~48 GB at Q4_K_M so needs a workstation GPU or Mac Studio. ~58% SWE-bench Verified. |
| `ollama/llama4:8b` | ★ | chat, tools, vision, json, local | 1048576 | depends_on_hardware | local | Massive (1M+) context with native multimodal and parallel tool calls. ~6 GB at Q4_K_M; fits laptops. Good general assistant, not a code specialist. |
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

