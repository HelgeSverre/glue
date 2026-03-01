# Built-in Tools

The agent has access to these tools for interacting with your codebase. Tools run in parallel when independent.

## Tool Reference

| Tool                       | Description                                                                                                          | Approval |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------- | -------- |
| `read_file`                | Read file contents with optional line range. Handles binary detection and large files (max 1 MB).                    | Auto     |
| `write_file`               | Create or overwrite a file. Shows diff preview before writing.                                                       | Required |
| `edit_file`                | Search-and-replace within a file. Minimal diffs, preserves formatting.                                               | Required |
| `bash`                     | Run shell commands. Streams output in real-time. 30 second timeout.                                                  | Required |
| `list_directory`           | List directory contents with metadata. Respects `.gitignore`. Max 1,000 entries.                                     | Auto     |
| `grep`                     | Regex search across files. Uses ripgrep when available. 15 second timeout.                                           | Auto     |
| `spawn_subagent`           | Spawn a single focused subagent for an isolated task.                                                                | Auto     |
| `spawn_parallel_subagents` | Spawn multiple subagents to work concurrently on independent tasks.                                                  | Auto     |
| `web_fetch`                | Fetch URL content as markdown. Handles PDFs with OCR fallback via Mistral/OpenAI vision.                             | Auto     |
| `web_search`               | Search the web via Brave, Tavily, or Firecrawl. Auto-detects available provider from API keys.                       | Auto     |
| `web_browser`              | Browser automation via Chrome DevTools Protocol. Actions: navigate, screenshot, click, type, extract_text, evaluate. | Required |
| `skill`                    | List available skills (no args) or activate a skill by name.                                                         | Auto     |

## Approval Levels

Each tool has one of three approval levels:

- **Auto** — the tool runs without asking. Read-only tools like `read_file`, `list_directory`, and `grep` fall into this category.
- **Required** — Glue shows a confirmation modal before running the tool. Tools that modify your codebase (`write_file`, `edit_file`, `bash`) require explicit approval. See [Tool Approval](./tool-approval.md) for details.
- **Always** — the user has permanently trusted this tool. Any tool can be promoted to this level through the approval modal or by editing `~/.glue/config.yaml`.

::: tip
Tools that are independent of each other run in parallel automatically. For example, the agent can read multiple files or search across different directories at the same time.
:::

## See also

- [AgentCore](/api/agent/agent-core)
- [Tools](/api/agent/tools)
