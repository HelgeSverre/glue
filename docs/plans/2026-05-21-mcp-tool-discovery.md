# MCP Tool Discovery Plan

**Status:** plan only - no code yet
**Date:** 2026-05-21
**Goal:** Keep large MCP tool catalogs out of the model context by exposing a small searchable discovery surface and dynamically revealing only the tools the agent needs.

## Summary

Implement Glue-owned progressive tool discovery for large MCP tool sets. V1 should use a portable local approach: keep native/core tools and a safe `tool_search` tool visible, index all connected MCP tools host-side, prewarm the top matches from each user prompt, and dynamically expose only the few real tools the model needs.

This is a good fit for the problem. Official MCP client guidance recommends progressive discovery once tool definitions consume a meaningful share of context, and describes the same pattern: fetch tools normally, defer injecting definitions, expose a lightweight search meta-tool, then load full definitions as needed. Anthropic and OpenAI now both expose native deferred-tool flows, but Glue should start provider-agnostic so Anthropic, OpenAI-compatible, Gemini, Ollama, and future adapters behave the same.

Research basis:

- MCP progressive discovery guidance: https://modelcontextprotocol.io/docs/develop/clients/client-best-practices
- MCP tool protocol, `tools/list`, `listChanged`, annotations: https://modelcontextprotocol.io/specification/2025-06-18/server/tools
- Claude Code MCP tool search defaults and `alwaysLoad`: https://code.claude.com/docs/en/mcp
- Anthropic tool search details: https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool
- OpenAI tool search / namespace guidance: https://openai.github.io/openai-agents-python/tools/

## Key Changes

Add `tool_discovery` config at top level, not under `mcp`, because the mechanism applies to any `Tool` even though MCP is the first driver:

```yaml
tool_discovery:
  mode: auto                  # off | on | auto
  threshold_percent: 5        # auto enables when estimated tool schemas exceed this share of context
  max_prewarm: 5
  max_search_results: 8
  max_active_tools: 32
  always_load:
    - read_file
    - write_file
    - edit_file
    - bash
    - grep
    - list_directory
    - web_fetch
    - web_search
    - web_browser
    - skill
    - spawn_subagent
    - spawn_parallel_subagents
  aliases:
    pdf_api__sign_contract: [pdf, document, contract, signature]
```

Create a small harness-layer discovery subsystem, likely under `packages/glue_harness/lib/src/tools/tool_discovery/`:

- `ToolDiscoveryIndex`: in-memory BM25-ish keyword scorer; no SQLite, embeddings, or LLM alias generation in v1.
- `ToolDiscoveryRegistry`: tracks all known tools, always-loaded names, active deferred names, LRU/sticky activation, and `listChanged` removals.
- `ToolSearchTool`: safe meta-tool with `query`, optional `max_results`, and optional `detail` (`summary | schema`). It searches, activates the top matches, and returns concise result cards.
- `ToolDiscoveryConfig`: parsed by `GlueConfig`, documented in the config template and reference docs.

Search fields and weighting are fixed for v1:

- Highest weight: exact namespaced tool name, bare name, title, and configured aliases.
- Medium weight: server id/name/instructions and tool description.
- Lower weight: input parameter names/descriptions and output schema field names.
- Tokenization splits snake_case, kebab-case, camelCase, punctuation, and lowercases terms.

Preserve real tool calls after discovery:

- Do not add a generic `call_tool(name,args)` proxy in v1.
- When a tool is discovered, expose the actual `Tool` on the next LLM iteration so provider schemas, permission prompts, observability, trusted-tool names, and MCP auto-approve policy still refer to the real tool name.
- Keep tool order stable: always-loaded tools first, then previously activated tools, then newly activated tools, then `tool_search`.

MCP descriptor support should be tightened while implementing this:

- Support `tools/list` pagination before indexing, so large servers do not silently drop tools.
- Extend `McpToolDescriptor` to parse `title`, `outputSchema`, `annotations`, and `_meta`.
- Override `McpTool.toSchema()` to preserve the original MCP `inputSchema` instead of flattening it through `ToolParameter`, so discovered tools retain enums and richer JSON Schema.
- Honor MCP `notifications/tools/list_changed` by refreshing the server's indexed entries and removing active tools that no longer exist.
- Treat MCP annotations as untrusted unless later tied to trusted-server policy; do not auto-approve based on annotations in this plan.

## Implementation Plan

1. Add config parsing and docs.
   - Add `ToolDiscoveryConfig` to `GlueConfig`.
   - Parse `tool_discovery.mode`, limits, `always_load`, and `aliases`.
   - Add commented examples to `config_template.dart` and `docs/reference/config-yaml.md`.
   - Default `mode: auto`, `threshold_percent: 5`, `max_prewarm: 5`, `max_search_results: 8`, `max_active_tools: 32`.

2. Add the discovery index.
   - Implement deterministic tokenization and scoring in pure Dart.
   - Index `Tool` data plus optional MCP metadata.
   - Return stable ordered results with name, source server, description, score reason, and schema when requested.
   - Add unit tests for aliases, fuzzy token splitting, parameter-name matches, and deterministic tie-breaking.

3. Add activation and filtering.
   - Introduce a registry object owned by `ServiceLocator` and shared with `AgentCore`.
   - Change `AgentCore.allowedTools` usage so `toolFilter` can delegate to discovery state without disabling native tools.
   - Before each new user turn, prewarm from the user message when discovery is enabled.
   - Ensure active tools stay sticky for the session until `max_active_tools` LRU pruning or MCP removal.

4. Add `tool_search`.
   - Register `tool_search` as a safe built-in tool whenever discovery is enabled.
   - `execute()` searches hidden and active tools, activates top matches, and returns concise results.
   - Update the system prompt with one short rule: before assuming a capability is unavailable, use `tool_search` for non-obvious external/MCP capabilities.

5. Wire MCP updates.
   - When MCP servers connect, add their tools to the discovery registry instead of blindly exposing all of them.
   - Keep native tools and configured `always_load` MCP tools visible immediately.
   - On MCP disconnect or `list_changed`, update both the agent tool map and discovery registry.
   - Preserve existing `/mcp tools` and `glue mcp tools` behavior as catalog inspection; discovery affects the model-facing tool list, not user diagnostics.

## Test Plan

- Config tests for defaults, `off/on/auto`, aliases, malformed values, and config-template parseability.
- Index tests with 1000 fake MCP tools proving `contract pdf signature` ranks the configured PDF-signing tool first via aliases.
- Agent loop tests proving the first LLM call receives only always-loaded tools plus prewarmed matches plus `tool_search`, not all MCP tools.
- Tool-search loop test: model calls `tool_search`, result activates a hidden tool, next LLM iteration receives that real tool and can call it.
- MCP tests for paginated `tools/list`, descriptor metadata parsing, and `notifications/tools/list_changed` refresh.
- Permission tests proving discovered MCP tools still prompt using their real names and trust levels.
- Regression tests proving `tool_discovery.mode: off` preserves today's behavior of loading all registered tools.

## Assumptions

- V1 chooses the portable local approach selected here; provider-native `defer_loading` / `tool_reference` support is deferred.
- V1 uses lexical search plus aliases, not embeddings or LLM-generated alias caches.
- Native Glue tools remain always loaded by default because there are few of them and they are part of the agent's normal operating loop.
- MCP tools are deferred by default unless explicitly listed in `always_load`.
- This document is the only requested change for now; implementation is intentionally deferred.
