# Subagents

The main agent can spawn independent subagents for focused tasks. Each subagent gets its own conversation context and tool access, preventing context bloat in the main session.

## Single Subagent

The `spawn_subagent` tool creates one focused worker:

```json
{
  "task": "Read all files in lib/src/auth/ and summarize the authentication flow",
  "model_ref": "anthropic/claude-haiku-4.5"
}
```

## Parallel Subagents

The `spawn_parallel_subagents` tool runs multiple tasks concurrently:

```json
{
  "tasks": [
    "Analyze the auth module structure",
    "Analyze the payments module structure",
    "Analyze the notifications module structure"
  ],
  "model_ref": "anthropic/claude-haiku-4.5"
}
```

## Safety Rules

- **Read-only by default** — subagents can only use `read_file`, `list_directory`, and `grep`
- **Depth limited** — subagents can spawn sub-subagents, but only up to 2 levels deep
- **Model override** — pass `model_ref` (e.g. `"anthropic/claude-haiku-4.5"`) to use a cheaper/faster model for exploration; defaults to the active model
- **Fresh context** — each subagent starts clean, no conversation history inherited

## See also

- [SubagentTools](/api/tools/subagent-tools)
- [AgentManager](/api/agent/agent-manager)
