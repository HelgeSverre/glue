# Project Context

Glue automatically loads project-specific context files into the agent's system prompt, so it understands your codebase conventions without being told.

## Auto-Loaded Files

| File        | Purpose                                                            | Max Size |
| ----------- | ------------------------------------------------------------------ | -------- |
| `AGENTS.md` | Agent behavior guidelines — code style, conventions, what to avoid | 50 KB    |
| `CLAUDE.md` | Custom project context — architecture notes, important patterns    | 50 KB    |

## Discovery

Glue follows the [agents.md](https://agents.md) discovery model. Starting from the current working directory, Glue walks up parent directories until it reaches the workspace root (the first ancestor containing a `.git` directory). At every level, both `AGENTS.md` and `CLAUDE.md` are collected.

- Files are injected into the prompt **root-first**, so the closest file appears last and effectively overrides ancestors on conflict.
- The walk also stops at `$HOME` to prevent a personal `~/AGENTS.md` from leaking into project sessions.
- If no `.git` ancestor is reachable, only the current working directory is consulted (no walk).
- Each file is truncated to 50 KB with a note if it exceeds that limit.

### Monorepo example

```
my-repo/
├── .git/
├── AGENTS.md              # repo-wide rules
└── packages/
    └── api/
        └── AGENTS.md      # package-specific rules
```

Running `glue` inside `packages/api/` loads both files. The repo-level `AGENTS.md` is rendered first as `## Project Instructions (AGENTS.md)`, then the nested one as `## Project Instructions (packages/api/AGENTS.md)`.

## .glue/ Directory

Project-local extensions can live in a `.glue/` directory at your project root:

- `.glue/skills/` — project-local skill definitions (each skill has its own `SKILL.md`)

::: tip
Add `AGENTS.md` to your repo with code style guidelines. The agent will follow them automatically — no need to repeat instructions each session.
:::

## See also

- [Prompts](/api/agent/prompts)
- [GlueConfig](/api/config/glue-config)
