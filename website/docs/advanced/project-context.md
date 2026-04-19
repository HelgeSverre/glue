# Project Context

Glue automatically loads project-specific context files into the agent's system prompt, so it understands your codebase conventions without being told.

## Auto-Loaded Files

| File        | Purpose                                                            | Max Size |
| ----------- | ------------------------------------------------------------------ | -------- |
| `AGENTS.md` | Agent behavior guidelines — code style, conventions, what to avoid | 50 KB    |
| `CLAUDE.md` | Custom project context — architecture notes, important patterns    | 50 KB    |

Both files are looked up in the current working directory. If found, their contents are appended to the system prompt. Files larger than 50 KB are truncated with a note.

## .glue/ Directory

Project-local extensions can live in a `.glue/` directory at your project root:

- `.glue/skills/` — project-local skill definitions (each skill has its own `SKILL.md`)

::: tip
Add `AGENTS.md` to your repo with code style guidelines. The agent will follow them automatically — no need to repeat instructions each session.
:::

## See also

- [Prompts](/api/agent/prompts)
- [GlueConfig](/api/config/glue-config)
