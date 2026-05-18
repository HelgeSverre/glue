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
2. Workspace bootstrap clones the current git repo (or uploads a
   tarball) into `/workspace` inside the sprite.
3. Tools and bash run via `sprite exec`.
4. On session close, the sprite is deleted unless `delete_on_close:
   false`.

## All Sprites options

| YAML key                  | Env var                      | Default              |
| ------------------------- | ---------------------------- | -------------------- |
| `sprites.sprite_cli`      | `SPRITES_CLI`                | `sprite` (on PATH)   |
| `sprites.sprite_name`     | `SPRITES_NAME`               | auto-generated       |
| `sprites.delete_on_close` | `SPRITES_DELETE_ON_CLOSE`    | `true`               |

## See also

- [Runtimes overview](/runtimes)
- [Sprites docs](https://sprites.dev/)
