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
2. Workspace bootstrap stages your working tree at `/workspace` —
   see [Bootstrap strategy](#bootstrap-strategy) below.
3. Tools and bash run against the sandbox via the per-sandbox toolbox URL.
4. On session close, the agent's changes are captured to
   `~/.glue/sessions/<id>/runtime.mbox`
   (see [Session Patches](/docs/using-glue/session-patches)) and the
   sandbox is stopped — no orphaned sandboxes left billing you.

## Bootstrap strategy

Daytona uses the **bundle path** by default:

1. Glue runs `git --git-dir=<temp> --work-tree=<your-cwd> init && add -A
   && commit -m "glue bootstrap"` on the **host** — your real `.git`
   is never touched.
2. The resulting bundle (≤200 MB cap for Daytona's multipart upload)
   is uploaded to the sandbox at `/tmp/glue-bootstrap.bundle`.
3. The sandbox clones from the bundle: `git clone /tmp/glue-bootstrap.bundle
   /workspace`.

What you get for free:

- **Uncommitted edits** ship to the sandbox — agent sees what's on
  your disk, not what's on `origin/HEAD`.
- **Unpushed commits** ship (the sandbox doesn't need the SHA to be
  reachable from `origin`).
- **Untracked files** ship (subject to your host `.gitignore`).
- **No-remote repos** work — no `origin` required.
- **Private repos** work without giving Daytona credentials — the
  sandbox never fetches.

What it doesn't ship:

- **Submodule contents** (only the gitlink pointer). Warning printed
  at bootstrap when `.gitmodules` is present.
- **`.gitignore`'d files** like `.env`, `node_modules`, lockfiles.
  If the agent needs them, un-ignore them temporarily.
- **Stashes**.

If host `git` isn't available, glue falls back to **clone-from-remote**
inside the sandbox — that path requires a reachable `origin` and
sandbox-accessible auth.

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
