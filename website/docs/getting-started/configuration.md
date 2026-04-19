# Configuration

Glue resolves configuration from CLI flags → environment variables → your
personal config file → defaults. This page covers all four and — most
importantly — tells you **where those files actually live** on your machine.

## Where configuration lives

Everything Glue stores on your machine lives under a single home directory we
call `GLUE_HOME`. By default that's `~/.glue`.

| Purpose                            | Path (default)                     | Written by       | Safe to commit? |
| ---------------------------------- | ---------------------------------- | ---------------- | --------------- |
| Personal YAML config               | `~/.glue/config.yaml`              | You              | Usually no — may hold defaults only |
| Provider credentials               | `~/.glue/credentials.json`         | You              | **No**        |
| Machine-managed preferences        | `~/.glue/preferences.json`         | Glue             | No — internal state |
| Session logs (append-only JSONL)   | `~/.glue/sessions/<id>/`           | Glue             | No              |
| Debug logs                         | `~/.glue/logs/`                    | Glue             | No              |
| Cache (bundled catalogs, etc.)     | `~/.glue/cache/`                   | Glue             | No              |
| Optional: per-user model overrides | `~/.glue/models.yaml`              | You              | Yes if curated  |

### Platform specifics

`~` expands to your user home directory, so the full path depends on your OS:

| OS              | `~/.glue/` resolves to           |
| --------------- | -------------------------------- |
| macOS           | `/Users/<you>/.glue/`            |
| Linux           | `/home/<you>/.glue/`             |
| Windows (WSL)   | `/home/<you>/.glue/`             |
| Windows (native)| `C:\Users\<you>\.glue\`          |

::: tip Point Glue somewhere else
Set the `GLUE_HOME` environment variable to use a different directory — handy
for keeping per-project config in the project itself, or for dotfiles-managed
setups.

```sh
export GLUE_HOME="$HOME/.config/glue"
```

Everything else (sessions, logs, cache) moves with it.
:::

## `config.yaml` — your personal config

The main file you edit is `~/.glue/config.yaml`. Minimal example:

```yaml
active_model: anthropic/claude-sonnet-4.6
```

That's enough to start. Credentials come from the environment in this
example (`ANTHROPIC_API_KEY`).

A fuller example with shell, Docker, and web tools:

```yaml
active_model: anthropic/claude-sonnet-4-6

# Optional cheap/fast model used for things like session-title generation.
small_model: anthropic/claude-haiku-4-5

approval_mode: confirm   # confirm | auto

shell:
  executable: zsh
  mode: non_interactive  # non_interactive | interactive | login

docker:
  enabled: false
  image: ubuntu:24.04
  fallback_to_host: true
  mounts:
    - /Users/<you>/code/shared

web:
  search:
    provider: brave
  browser:
    backend: local       # local | docker | steel | browserbase | browserless | anchor

skills:
  paths:
    - /opt/glue-skills
```

The full schema is tracked in the canonical reference at
[`docs/reference/config-yaml.md`](https://github.com/helgesverre/glue/blob/main/docs/reference/config-yaml.md).

::: warning Keep secrets out of `config.yaml`
Glue never requires API keys in `config.yaml`. Use env vars or
`~/.glue/credentials.json` (see below). If you commit `~/.glue/config.yaml`
as part of your dotfiles, scrub it for keys first.
:::

## `credentials.json` — API keys

Credentials live in their own file so they stay out of any config you
version-control:

```json
{
  "anthropic": { "api_key": "sk-ant-..." },
  "openai":    { "api_key": "sk-..." },
  "openrouter":{ "api_key": "sk-or-..." }
}
```

Permissions are set to `0600` (owner read/write only) on write.

Alternative: environment variables. Glue reads the standard names without
any config:

| Variable              | Purpose              |
| --------------------- | -------------------- |
| `ANTHROPIC_API_KEY`   | Anthropic            |
| `OPENAI_API_KEY`      | OpenAI               |
| `GEMINI_API_KEY`      | Google Gemini        |
| `MISTRAL_API_KEY`     | Mistral              |
| `GROQ_API_KEY`        | Groq                 |
| `OPENROUTER_API_KEY`  | OpenRouter           |

## `sessions/` — one directory per run

```
~/.glue/sessions/<session-id>/
├── meta.json          # identity: model, cwd, git context, timestamps
├── conversation.jsonl # append-only event log (what the agent did)
└── state.json         # mutable per-session state (docker mounts, etc.)
```

Safe to read, grep, and `tail -f`. See [Sessions](/sessions) for the event
schema.

## Environment overrides

Most config keys can be overridden by an env var prefixed with `GLUE_`:

| Variable                         | Override                          |
| -------------------------------- | --------------------------------- |
| `GLUE_HOME`                      | Root config directory             |
| `GLUE_MODEL`                     | Active model (`provider/model`)   |
| `GLUE_SHELL` / `GLUE_SHELL_MODE` | Shell binary and mode             |
| `GLUE_DOCKER_ENABLED` etc.       | Docker runtime toggles            |
| `GLUE_SEARCH_PROVIDER`           | Web search backend                |
| `GLUE_APPROVAL_MODE`             | `confirm` or `auto`               |
| `GLUE_DEBUG=1`                   | Enables verbose debug logging     |
| `GLUE_SKILLS_PATHS`              | Extra skill discovery roots       |

Full list in the [canonical config reference](https://github.com/helgesverre/glue/blob/main/docs/reference/config-yaml.md).

## Resolution order

When the same setting is defined in multiple places, Glue uses the **first**
match:

1. CLI flags (e.g. `--model`, `--resume`)
2. Environment variables (e.g. `GLUE_MODEL`)
3. `~/.glue/config.yaml`
4. Built-in defaults

::: tip
Use CLI flags for one-off overrides, env vars for machine-level
defaults, and `config.yaml` for personal preferences.
:::

## Finding everything on a fresh install

```sh
# Show where Glue will read from.
glue --where      # prints GLUE_HOME and resolved paths

# Open the config directory in Finder / Explorer / xdg-open.
open "$GLUE_HOME"  # macOS
xdg-open "$GLUE_HOME"  # Linux
explorer "%USERPROFILE%\.glue"  # Windows
```

## See also

- [Installation](./installation) — prerequisites and install steps
- [Quick Start](./quick-start) — first-session walkthrough
- [Models & Providers](/docs/using-glue/models-and-providers) — how
  `provider/model` IDs and adapters work
- Canonical reference:
  [`docs/reference/config-yaml.md`](https://github.com/helgesverre/glue/blob/main/docs/reference/config-yaml.md)
  and
  [`docs/reference/glue-home-layout.md`](https://github.com/helgesverre/glue/blob/main/docs/reference/glue-home-layout.md)
