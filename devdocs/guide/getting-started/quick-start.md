# Quick Start

This guide walks you through your first Glue session: setting an API key, launching the CLI, sending a prompt, and using common flags.

## Set Your API Key

Glue reads provider keys from environment variables. Export the key for your preferred provider:

```bash
# Anthropic (default provider)
export ANTHROPIC_API_KEY=sk-ant-...

# OpenAI
export OPENAI_API_KEY=sk-...

# Mistral
export MISTRAL_API_KEY=...
```

::: tip
Add the export to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.) so the key persists across terminal sessions.
:::

## Launch Glue

Navigate to a project directory and start an interactive session:

```bash
cd my-project
glue
```

Glue opens a conversational interface where you can describe tasks in plain language. It reads your project files, suggests edits, and runs commands on your behalf.

## Send Your First Prompt

You can pass a prompt directly when launching:

```bash
glue "add an auth endpoint"
```

Glue will analyze your project, propose changes, and ask for confirmation before applying them.

## CLI Flags

Common flags to customize your session:

| Flag | Description | Example |
|------|-------------|---------|
| `glue "prompt"` | Start with an initial prompt | `glue "add auth endpoint"` |
| `--model`, `-m` | Select a specific model | `glue -m gpt-5` |
| `--resume` | Open the session picker to resume a previous session | `glue --resume` |
| `--continue` | Resume the most recent session | `glue --continue` |

### Examples

Select a different model for a single session:

```bash
glue -m gpt-4.1 "refactor the database layer"
```

Pick up where you left off:

```bash
glue --resume
```

Continue your most recent conversation without the picker:

```bash
glue --continue
```

::: info
CLI flags take the highest precedence and override any values set in config files or environment variables. See the [Configuration](./configuration) guide for the full precedence order.
:::

## Next Steps

Now that you have run your first session, learn how to customize Glue for your workflow in the [Configuration](./configuration) guide.

## See also

- [Installation](./installation) -- prerequisites and install steps
- [Configuration](./configuration) -- config files, environment variables, and precedence
- [GlueConfig](/api/config/glue-config) -- programmatic configuration API
