# Daytona

Run Glue against a remote [Daytona](https://www.daytona.io/) sandbox. The
agent's shell, file tools, and background jobs all execute inside the
sandbox; your host stays untouched.

## Prerequisites

- A Daytona account and an API key (Daytona dashboard → Settings → API Keys).
- `DAYTONA_API_KEY` exported in the shell where you run `glue`.

`glue doctor` reports both.

## Enable

```yaml
# ~/.glue/config.yaml
runtime: daytona
daytona:
  api_key: env:DAYTONA_API_KEY
```

Or via env:

```bash
export GLUE_RUNTIME=daytona
export DAYTONA_API_KEY=sk-...
```

## Regions

Daytona runs a US and an EU control plane. The default is US:

```yaml
daytona:
  api_base_url: https://app-eu.daytona.io/api # EU
```

Or set `DAYTONA_API_BASE_URL`. The per-sandbox toolbox URL (e.g.
`https://proxy.app-eu.daytona.io/toolbox`) is returned by the create
call and used automatically — you don't configure it.

## Snapshots

By default Daytona uses your org's default snapshot. Pin a specific one
with:

```yaml
daytona:
  snapshot: my-snapshot-id
```

Or set `DAYTONA_SNAPSHOT`.

## What happens on session start

1. `POST /sandbox` creates a fresh sandbox.
2. Workspace bootstrap clones the current git repo (or uploads a tarball
   for non-repo directories) into `/workspace`.
3. Tools and bash run against the sandbox via the per-sandbox toolbox URL.
4. On session close, the sandbox is stopped — no orphaned sandboxes left
   billing you.

## All Daytona options

| YAML key                    | Env var                      | Default                          |
| --------------------------- | ---------------------------- | -------------------------------- |
| `daytona.api_key`           | `DAYTONA_API_KEY`            | required                         |
| `daytona.api_base_url`      | `DAYTONA_API_BASE_URL`       | `https://app.daytona.io/api`     |
| `daytona.toolbox_base_url`  | `DAYTONA_TOOLBOX_BASE_URL`   | per-sandbox; proxy override only |
| `daytona.snapshot`          | `DAYTONA_SNAPSHOT`           | org default                      |

## See also

- [Runtimes overview](/runtimes)
- [Daytona API docs](https://www.daytona.io/docs/)
