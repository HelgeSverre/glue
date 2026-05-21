# Sprites

Run Glue against a persistent [Sprites](https://sprites.dev/) sandbox
(Fly.io VMs). Sprites auto-sleep when idle and resume on demand, so a
named sprite can outlive several Glue sessions cheaply.

## Prerequisites

- The `sprite` CLI on `$PATH` (Sprites' install instructions).
- One-time login: `sprite login`.

Glue does not manage Sprites credentials — they live in your Fly.io
account via the CLI's keychain. `glue doctor` checks for both.

::: info Why the CLI?
The Sprites wire protocol (`control-ws`) is binary and in active RC
flux. Wrapping the CLI is the stable path today; a native client will
land when the API stabilizes.
:::

## Enable

```yaml
# ~/.glue/config.yaml
runtime: sprites
```

Or via env:

```bash
export GLUE_RUNTIME=sprites
```

## Persistent sprites

By default, Glue generates a unique sprite name per session and deletes
it on close. To reuse the same sandbox across sessions:

```yaml
sprites:
  sprite_name: my-sandbox
  delete_on_close: false
```

The sprite auto-sleeps when idle (no billing while asleep) and resumes
the next time you connect.

## What happens on session start

1. `sprite create <name>` (skipped if an existing sprite resumes).
2. Workspace bootstrap stages your working tree at `/workspace` —
   see [Bootstrap strategy](#bootstrap-strategy) below.
3. Tools and bash run via `sprite exec`.
4. On session close, the agent's changes are captured to
   `~/.glue/sessions/<id>/runtime.mbox`
   (see [Session Patches](/docs/using-glue/session-patches)) and the
   sprite is deleted unless `delete_on_close: false`.

## Bootstrap strategy

Sprites uses the **bundle path** for fresh sprites:

1. Glue builds a host-side git bundle of your working tree (uncommitted
   edits + untracked files included).
2. Uploads it into the sprite via `sprite exec` — capped at **3 MB**
   because base64-over-shell-exec is the bottleneck. Most application
   repos fit comfortably; vendored / monorepo-sized projects don't.
3. Sandbox clones from the bundle.

If the bundle exceeds 3 MB or host `git` isn't available, glue falls
back to **clone-from-remote** inside the sprite — that path requires
a reachable `origin` and credentials Sprites can use.

::: warning Resumed sprites with uncommitted changes are refused
When you resume a sprite (`sprite_name: my-box`) and the previous
session left uncommitted changes in `/workspace`, glue refuses to
start instead of producing a silently-broken diff baseline:

```
Sprite "my-box" has uncommitted changes from a previous session in
/workspace. Commit or export them inside the sandbox before resuming,
e.g.:
  sprite exec my-box -- bash -lc "cd /workspace && git add -A && \
    git commit -m 'resume baseline'"
```

This is a deliberate choice: a silent `null` baseline used to drop
_every_ change from the resumed session. If you want this session to
build on the previous one, commit the previous work inside the sandbox
first. If you don't, delete the sprite.
:::

## All Sprites options

| YAML key                  | Env var                   | Default            |
| ------------------------- | ------------------------- | ------------------ |
| `sprites.sprite_cli`      | `SPRITES_CLI`             | `sprite` (on PATH) |
| `sprites.sprite_name`     | `SPRITES_NAME`            | auto-generated     |
| `sprites.delete_on_close` | `SPRITES_DELETE_ON_CLOSE` | `true`             |

## See also

- [Runtimes overview](/runtimes)
- [Sprites docs](https://sprites.dev/)
