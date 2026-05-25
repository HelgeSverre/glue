// GENERATED — DO NOT EDIT.
// Source: docs/reference/models.yaml
// Regenerate with: dart run tool/gen_models.dart
// ignore_for_file: lines_longer_than_80_chars

import 'package:glue_core/glue_core.dart';

const String _bundledCatalogJson = r'''
{
  "version": 1,
  "updated_at": "2026-05-21",
  "defaults": {
    "model": "anthropic/claude-sonnet-4-6",
    "small_model": "openai/gpt-5.4-mini",
    "local_model": "ollama/qwen3-coder:30b"
  },
  "capabilities": {
    "chat": "Text chat.",
    "streaming": "Incremental token streaming.",
    "tools": "Tool calling or function calling.",
    "parallel_tools": "Parallel tool-call execution in a single turn.",
    "vision": "Image input.",
    "files": "File upload or file reference support.",
    "json": "Structured JSON output.",
    "reasoning": "Explicit reasoning effort or thinking controls.",
    "coding": "Strong code generation and code review behavior.",
    "local": "Runs locally or on a user-controlled endpoint.",
    "browser": "Suitable for browser/research workflows.",
    "binary_tool_results": "Accepts binary or multimodal tool-result payloads."
  },
  "providers": {
    "anthropic": {
      "id": "anthropic",
      "name": "Anthropic",
      "adapter": "anthropic",
      "auth": {
        "kind": "api_key",
        "env_var": "ANTHROPIC_API_KEY",
        "help_url": null
      },
      "models": {
        "claude-sonnet-4-6": {
          "id": "claude-sonnet-4-6",
          "name": "Claude Sonnet 4.6",
          "api_id": "claude-sonnet-4-6",
          "recommended": true,
          "default": true,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1000000,
          "max_output_tokens": 64000,
          "speed": "standard",
          "cost": "high",
          "notes": "Default high-quality coding model."
        },
        "claude-haiku-4-5": {
          "id": "claude-haiku-4-5",
          "name": "Claude Haiku 4.5",
          "api_id": "claude-haiku-4-5",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "coding"
          ],
          "context_window": 200000,
          "max_output_tokens": 64000,
          "speed": "fast",
          "cost": "low",
          "notes": "Good small_model candidate for titles, summaries, and quick checks."
        },
        "claude-opus-4-7": {
          "id": "claude-opus-4-7",
          "name": "Claude Opus 4.7",
          "api_id": "claude-opus-4-7",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1000000,
          "max_output_tokens": 128000,
          "speed": "slower",
          "cost": "premium",
          "notes": "Most capable Claude model — agentic coding and long-horizon work."
        }
      },
      "compatibility": null,
      "enabled": true,
      "base_url": "https://api.anthropic.com",
      "docs_url": "https://docs.anthropic.com/",
      "request_headers": {}
    },
    "openai": {
      "id": "openai",
      "name": "OpenAI",
      "adapter": "openai",
      "auth": {
        "kind": "api_key",
        "env_var": "OPENAI_API_KEY",
        "help_url": null
      },
      "models": {
        "gpt-5.5": {
          "id": "gpt-5.5",
          "name": "GPT-5.5",
          "api_id": "gpt-5.5",
          "recommended": true,
          "default": true,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1050000,
          "max_output_tokens": 128000,
          "speed": "standard",
          "cost": "high",
          "notes": "Frontier general-purpose and agentic coding model."
        },
        "gpt-5.5-pro": {
          "id": "gpt-5.5-pro",
          "name": "GPT-5.5 Pro",
          "api_id": "gpt-5.5-pro",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1050000,
          "max_output_tokens": 128000,
          "speed": "slower",
          "cost": "premium",
          "notes": "High-compute reasoning variant. Use for hard architecture, proofs, and long-horizon planning."
        },
        "gpt-5.4": {
          "id": "gpt-5.4",
          "name": "GPT-5.4",
          "api_id": "gpt-5.4",
          "recommended": false,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1050000,
          "max_output_tokens": 128000,
          "speed": "standard",
          "cost": "high",
          "notes": "Prior frontier model — kept for pinned configs."
        },
        "gpt-5.4-mini": {
          "id": "gpt-5.4-mini",
          "name": "GPT-5.4 Mini",
          "api_id": "gpt-5.4-mini",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "coding"
          ],
          "context_window": 400000,
          "max_output_tokens": 128000,
          "speed": "fast",
          "cost": "low",
          "notes": "Default small_model candidate."
        },
        "gpt-5.4-nano": {
          "id": "gpt-5.4-nano",
          "name": "GPT-5.4 Nano",
          "api_id": "gpt-5.4-nano",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "coding"
          ],
          "context_window": 400000,
          "max_output_tokens": 128000,
          "speed": "fast",
          "cost": "low",
          "notes": "Cheapest GPT-5.4-class model for high-volume tasks."
        },
        "o3": {
          "id": "o3",
          "name": "o3",
          "api_id": "o3",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 200000,
          "max_output_tokens": null,
          "speed": "slower",
          "cost": "high",
          "notes": "Reasoning-specialized flagship. Use for hard debugging, proofs, and multi-step planning."
        }
      },
      "compatibility": null,
      "enabled": true,
      "base_url": "https://api.openai.com/v1",
      "docs_url": "https://platform.openai.com/docs/",
      "request_headers": {}
    },
    "gemini": {
      "id": "gemini",
      "name": "Google Gemini",
      "adapter": "gemini",
      "auth": {
        "kind": "api_key",
        "env_var": "GEMINI_API_KEY",
        "help_url": null
      },
      "models": {
        "gemini-3.5-flash": {
          "id": "gemini-3.5-flash",
          "name": "Gemini 3.5 Flash",
          "api_id": "gemini-3.5-flash",
          "recommended": true,
          "default": true,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding",
            "browser"
          ],
          "context_window": 1000000,
          "max_output_tokens": 65536,
          "speed": "fast",
          "cost": "low",
          "notes": "GA Flash (May 2026). Most intelligent Flash-tier model for agentic and coding tasks. Supports Google Search grounding."
        },
        "gemini-3.1-pro-preview": {
          "id": "gemini-3.1-pro-preview",
          "name": "Gemini 3.1 Pro Preview",
          "api_id": "gemini-3.1-pro-preview",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding",
            "browser"
          ],
          "context_window": 1000000,
          "max_output_tokens": 65536,
          "speed": "standard",
          "cost": "medium",
          "notes": "Pro-class preview. Strongest Gemini model for complex reasoning, coding, and research. Supports Google Search grounding."
        },
        "gemini-3-flash-preview": {
          "id": "gemini-3-flash-preview",
          "name": "Gemini 3 Flash Preview",
          "api_id": "gemini-3-flash-preview",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "coding"
          ],
          "context_window": 1000000,
          "max_output_tokens": 65536,
          "speed": "fast",
          "cost": "low",
          "notes": "Fast, balanced, multimodal preview. Strong agentic-coding candidate."
        },
        "gemini-3.1-flash-lite": {
          "id": "gemini-3.1-flash-lite",
          "name": "Gemini 3.1 Flash-Lite",
          "api_id": "gemini-3.1-flash-lite",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "coding"
          ],
          "context_window": 1000000,
          "max_output_tokens": 65536,
          "speed": "fast",
          "cost": "low",
          "notes": "GA Flash-Lite (May 2026). Cost-efficient, fastest performance for high-frequency, lightweight tasks."
        },
        "deep-research-preview-04-2026": {
          "id": "deep-research-preview-04-2026",
          "name": "Deep Research Preview (Apr 2026)",
          "api_id": "deep-research-preview-04-2026",
          "recommended": false,
          "default": false,
          "enabled": false,
          "capabilities": [
            "chat",
            "reasoning",
            "tools",
            "browser"
          ],
          "context_window": 1000000,
          "max_output_tokens": 65536,
          "speed": "slower",
          "cost": "high",
          "notes": "Fast Deep Research agent — interactive use. Requires background runner (not yet wired up in Glue)."
        },
        "deep-research-max-preview-04-2026": {
          "id": "deep-research-max-preview-04-2026",
          "name": "Deep Research Max Preview (Apr 2026)",
          "api_id": "deep-research-max-preview-04-2026",
          "recommended": false,
          "default": false,
          "enabled": false,
          "capabilities": [
            "chat",
            "reasoning",
            "tools",
            "browser"
          ],
          "context_window": 1000000,
          "max_output_tokens": 65536,
          "speed": "slower",
          "cost": "high",
          "notes": "Maximum-comprehensiveness Deep Research agent. Requires background runner (not yet wired up in Glue)."
        }
      },
      "compatibility": null,
      "enabled": true,
      "base_url": null,
      "docs_url": "https://ai.google.dev/",
      "request_headers": {}
    },
    "mistral": {
      "id": "mistral",
      "name": "Mistral AI",
      "adapter": "openai",
      "auth": {
        "kind": "api_key",
        "env_var": "MISTRAL_API_KEY",
        "help_url": null
      },
      "models": {
        "devstral-latest": {
          "id": "devstral-latest",
          "name": "Devstral Latest",
          "api_id": "devstral-latest",
          "recommended": true,
          "default": true,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "coding"
          ],
          "context_window": 262000,
          "max_output_tokens": null,
          "speed": "standard",
          "cost": "medium",
          "notes": "Mistral's agentic coding model. Strong tool use."
        },
        "mistral-large-latest": {
          "id": "mistral-large-latest",
          "name": "Mistral Large Latest",
          "api_id": "mistral-large-latest",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "coding"
          ],
          "context_window": 262000,
          "max_output_tokens": null,
          "speed": "standard",
          "cost": "medium",
          "notes": "Flagship multimodal general-purpose model."
        },
        "mistral-small-latest": {
          "id": "mistral-small-latest",
          "name": "Mistral Small Latest",
          "api_id": "mistral-small-latest",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 262000,
          "max_output_tokens": null,
          "speed": "fast",
          "cost": "low",
          "notes": "Unified reasoning + coding + vision (Small 4, March 2026). Strong small-model default; cheaper than Medium with better agentic behavior."
        },
        "magistral-medium-latest": {
          "id": "magistral-medium-latest",
          "name": "Magistral Medium Latest",
          "api_id": "magistral-medium-latest",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "reasoning"
          ],
          "context_window": 262000,
          "max_output_tokens": null,
          "speed": "standard",
          "cost": "medium",
          "notes": "Pure reasoning model. Use when you need explicit long-chain thinking; not a general chat pick."
        },
        "mistral-medium-latest": {
          "id": "mistral-medium-latest",
          "name": "Mistral Medium Latest",
          "api_id": "mistral-medium-latest",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json"
          ],
          "context_window": 262000,
          "max_output_tokens": null,
          "speed": "standard",
          "cost": "medium",
          "notes": "Mistral Medium 3.5 (April 2026). Mid-tier general-purpose; multimodal with tool use."
        }
      },
      "compatibility": "mistral",
      "enabled": true,
      "base_url": "https://api.mistral.ai/v1",
      "docs_url": "https://docs.mistral.ai/",
      "request_headers": {}
    },
    "groq": {
      "id": "groq",
      "name": "Groq",
      "adapter": "openai",
      "auth": {
        "kind": "api_key",
        "env_var": "GROQ_API_KEY",
        "help_url": null
      },
      "models": {
        "llama-4-scout-17b-16e-instruct": {
          "id": "llama-4-scout-17b-16e-instruct",
          "name": "Llama 4 Scout (17B active / 109B MoE)",
          "api_id": "meta-llama/llama-4-scout-17b-16e-instruct",
          "recommended": true,
          "default": true,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "coding"
          ],
          "context_window": 128000,
          "max_output_tokens": null,
          "speed": "fast",
          "cost": "low",
          "notes": "Native multimodal MoE in production on Groq. Strong speed/quality default as of 2026-04."
        },
        "gpt-oss-120b": {
          "id": "gpt-oss-120b",
          "name": "GPT-OSS 120B",
          "api_id": "openai/gpt-oss-120b",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 131072,
          "max_output_tokens": null,
          "speed": "fast",
          "cost": "low",
          "notes": "OpenAI's open-weight reasoning + coding model. 120B weights at Groq speed."
        },
        "gpt-oss-20b": {
          "id": "gpt-oss-20b",
          "name": "GPT-OSS 20B",
          "api_id": "openai/gpt-oss-20b",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "coding"
          ],
          "context_window": 131072,
          "max_output_tokens": null,
          "speed": "fast",
          "cost": "low",
          "notes": "Coding-optimized, faster/cheaper than 120B."
        }
      },
      "compatibility": "groq",
      "enabled": true,
      "base_url": "https://api.groq.com/openai/v1",
      "docs_url": "https://console.groq.com/docs/",
      "request_headers": {}
    },
    "ollama": {
      "id": "ollama",
      "name": "Ollama",
      "adapter": "ollama",
      "auth": {
        "kind": "none",
        "env_var": null,
        "help_url": null
      },
      "models": {
        "qwen3-coder:30b": {
          "id": "qwen3-coder:30b",
          "name": "Qwen3 Coder 30B (MoE)",
          "api_id": "qwen3-coder:30b",
          "recommended": true,
          "default": true,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "coding",
            "local"
          ],
          "context_window": 256000,
          "max_output_tokens": null,
          "speed": "depends_on_hardware",
          "cost": "local",
          "notes": "Consensus local coding agent. 30B/3.3B MoE. ~20 GB VRAM at Q4_K_M."
        },
        "qwen3-coder-next:latest": {
          "id": "qwen3-coder-next:latest",
          "name": "Qwen3 Coder Next (MoE)",
          "api_id": "qwen3-coder-next:latest",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "coding",
            "local"
          ],
          "context_window": 256000,
          "max_output_tokens": null,
          "speed": "depends_on_hardware",
          "cost": "local",
          "notes": "2026-04 flagship local coder. Qwen3-Next-80B-A3B; ~52 GB at Q4_K_M, ~85 GB at Q8_0. Needs a workstation GPU or 64 GB+ Mac."
        },
        "qwen3.6:35b": {
          "id": "qwen3.6:35b",
          "name": "Qwen3.6 35B",
          "api_id": "qwen3.6:35b",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "reasoning",
            "coding",
            "local"
          ],
          "context_window": 256000,
          "max_output_tokens": null,
          "speed": "depends_on_hardware",
          "cost": "local",
          "notes": "Latest Qwen generalist with agentic coding upgrades. Vision + thinking + tools. ~24 GB at Q4_K_M."
        },
        "gemma4:26b": {
          "id": "gemma4:26b",
          "name": "Gemma 4 26B",
          "api_id": "gemma4:26b",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "coding",
            "local"
          ],
          "context_window": 256000,
          "max_output_tokens": null,
          "speed": "depends_on_hardware",
          "cost": "local",
          "notes": "Google's latest with native function-calling. Multimodal, 256K context. ~18 GB at Q4_K_M."
        },
        "devstral:24b": {
          "id": "devstral:24b",
          "name": "Devstral 24B",
          "api_id": "devstral:24b",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "coding",
            "local"
          ],
          "context_window": 128000,
          "max_output_tokens": null,
          "speed": "depends_on_hardware",
          "cost": "local",
          "notes": "Mistral's agentic coding model. ~14 GB at Q4_K_M."
        },
        "qwen2.5-coder:32b": {
          "id": "qwen2.5-coder:32b",
          "name": "Qwen2.5 Coder 32B",
          "api_id": "qwen2.5-coder:32b",
          "recommended": false,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "coding",
            "local"
          ],
          "context_window": 32768,
          "max_output_tokens": null,
          "speed": "depends_on_hardware",
          "cost": "local",
          "notes": "Previous-generation safe fallback. Prefer qwen3-coder:30b."
        },
        "qwen3:8b": {
          "id": "qwen3:8b",
          "name": "Qwen3 8B",
          "api_id": "qwen3:8b",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "local"
          ],
          "context_window": 128000,
          "max_output_tokens": null,
          "speed": "depends_on_hardware",
          "cost": "local",
          "notes": "Low-end floor for tool use. ~5 GB at Q4_K_M. Fits a 16 GB laptop."
        }
      },
      "compatibility": null,
      "enabled": true,
      "base_url": "http://localhost:11434",
      "docs_url": "https://ollama.com/",
      "request_headers": {}
    },
    "copilot": {
      "id": "copilot",
      "name": "GitHub Copilot",
      "adapter": "copilot",
      "auth": {
        "kind": "oauth",
        "env_var": null,
        "help_url": "https://github.com/login/device"
      },
      "models": {
        "claude-sonnet-4-6": {
          "id": "claude-sonnet-4-6",
          "name": "Claude Sonnet 4.6 (via Copilot)",
          "api_id": "claude-sonnet-4-6",
          "recommended": true,
          "default": true,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "coding"
          ],
          "context_window": 1000000,
          "max_output_tokens": 64000,
          "speed": "standard",
          "cost": "subscription",
          "notes": "Uses your GitHub Copilot subscription."
        },
        "claude-opus-4-7": {
          "id": "claude-opus-4-7",
          "name": "Claude Opus 4.7 (via Copilot)",
          "api_id": "claude-opus-4-7",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1000000,
          "max_output_tokens": 128000,
          "speed": "slower",
          "cost": "subscription",
          "notes": "Top-tier Anthropic model via Copilot subscription."
        },
        "claude-opus-4-6": {
          "id": "claude-opus-4-6",
          "name": "Claude Opus 4.6 (via Copilot)",
          "api_id": "claude-opus-4-6",
          "recommended": false,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1000000,
          "max_output_tokens": 128000,
          "speed": "slower",
          "cost": "subscription",
          "notes": "Kept available; superseded by Opus 4.7 for new work."
        },
        "gpt-5.5": {
          "id": "gpt-5.5",
          "name": "GPT-5.5 (via Copilot)",
          "api_id": "gpt-5.5",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1050000,
          "max_output_tokens": 128000,
          "speed": "standard",
          "cost": "subscription",
          "notes": "Uses your GitHub Copilot subscription."
        },
        "gpt-5.3-codex": {
          "id": "gpt-5.3-codex",
          "name": "GPT-5.3 Codex (via Copilot)",
          "api_id": "gpt-5.3-codex",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "json",
            "coding"
          ],
          "context_window": 400000,
          "max_output_tokens": 128000,
          "speed": "fast",
          "cost": "subscription",
          "notes": "OpenAI's agentic coding model via Copilot subscription."
        },
        "gemini-2.5-pro": {
          "id": "gemini-2.5-pro",
          "name": "Gemini 2.5 Pro (via Copilot)",
          "api_id": "gemini-2.5-pro",
          "recommended": false,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1000000,
          "max_output_tokens": null,
          "speed": "standard",
          "cost": "subscription",
          "notes": "Google option via Copilot subscription."
        }
      },
      "compatibility": null,
      "enabled": true,
      "base_url": "https://api.githubcopilot.com",
      "docs_url": "https://docs.github.com/copilot",
      "request_headers": {}
    },
    "openrouter": {
      "id": "openrouter",
      "name": "OpenRouter",
      "adapter": "openai",
      "auth": {
        "kind": "api_key",
        "env_var": "OPENROUTER_API_KEY",
        "help_url": null
      },
      "models": {
        "claude-sonnet-4-6": {
          "id": "claude-sonnet-4-6",
          "name": "Claude Sonnet 4.6 via OpenRouter",
          "api_id": "anthropic/claude-sonnet-4.6",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "reasoning",
            "coding"
          ],
          "context_window": 1000000,
          "max_output_tokens": 64000,
          "speed": "standard",
          "cost": "provider_routed",
          "notes": "Useful when users want one router key."
        },
        "gpt-5.4-mini": {
          "id": "gpt-5.4-mini",
          "name": "GPT-5.4 Mini via OpenRouter",
          "api_id": "openai/gpt-5.4-mini",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "json",
            "coding"
          ],
          "context_window": 400000,
          "max_output_tokens": null,
          "speed": "fast",
          "cost": "provider_routed",
          "notes": "Small-model fallback through a router."
        },
        "gemini-3.5-flash": {
          "id": "gemini-3.5-flash",
          "name": "Gemini 3.5 Flash via OpenRouter",
          "api_id": "google/gemini-3.5-flash",
          "recommended": true,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "tools",
            "vision",
            "files",
            "json",
            "browser"
          ],
          "context_window": 1000000,
          "max_output_tokens": null,
          "speed": "fast",
          "cost": "provider_routed",
          "notes": "Good for research and extraction workflows."
        }
      },
      "compatibility": "openrouter",
      "enabled": false,
      "base_url": "https://openrouter.ai/api/v1",
      "docs_url": "https://openrouter.ai/docs/",
      "request_headers": {
        "HTTP-Referer": "https://getglue.dev",
        "X-Title": "Glue"
      }
    },
    "local-vllm": {
      "id": "local-vllm",
      "name": "Local vLLM",
      "adapter": "openai",
      "auth": {
        "kind": "none",
        "env_var": null,
        "help_url": null
      },
      "models": {
        "local-model": {
          "id": "local-model",
          "name": "Local Model",
          "api_id": "local-model",
          "recommended": false,
          "default": false,
          "enabled": true,
          "capabilities": [
            "chat",
            "json",
            "local"
          ],
          "context_window": null,
          "max_output_tokens": null,
          "speed": "depends_on_hardware",
          "cost": "local",
          "notes": "Rename this entry to the model served by vLLM, LM Studio, or another local gateway."
        }
      },
      "compatibility": "vllm",
      "enabled": false,
      "base_url": "http://localhost:8000/v1",
      "docs_url": null,
      "request_headers": {}
    }
  }
}
''';

final ModelCatalog bundledCatalog = ModelCatalogMapper.fromJson(
  _bundledCatalogJson,
);
