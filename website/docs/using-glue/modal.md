# Modal

Run Glue against a [Modal](https://modal.com/) sandbox. Modal exposes
its sandbox primitive only through the Python SDK, so Glue ships a
small Python sidecar (embedded in the binary) that holds a long-lived
sandbox and services exec/file ops over JSON-RPC on stdin/stdout.

## Prerequisites

- The `modal` CLI on `$PATH`.
- The `modal` Python package importable from a Python interpreter
  Glue can find (system Python, a venv, or whatever you point
  `python_path` at).
- One-time auth: `modal token set --token-id ... --token-secret ...`.

`glue doctor` checks for the CLI, the Python package, and the auth
status.

## Enable

```yaml
# ~/.glue/config.yaml
runtime: modal
modal:
  app_name: glue
```

Or via env:

```bash
export GLUE_RUNTIME=modal
```

## Python interpreter

Glue auto-detects a Python interpreter that has `modal` importable:

1. `MODAL_PYTHON` env var, if set.
2. The shebang of the resolved `modal` CLI binary.

Override explicitly when modal lives in a venv Glue can't detect:

```yaml
modal:
  python_path: /opt/venvs/glue/bin/python
```

## Sandbox image

By default Modal uses its Debian-based image. Glue augments it with
`apt_install("git")` so workspace bootstrap can `git clone` into the
sandbox. To pin a different base image:

```yaml
modal:
  image: python:3.12-slim
```

## Billing cap

Modal sandboxes auto-terminate after `sandbox_timeout_seconds` (default
1800 = 30 min) regardless of whether glue shuts down cleanly. Lower it
for short-lived agent runs; raise it for long bake-offs:

```yaml
modal:
  sandbox_timeout_seconds: 600 # 10 minutes
```

This is a hard cap independent of `delete_on_close` — it's the
insurance against a crashed glue process leaving sandboxes billing.

## What happens on session start

1. The Python sidecar launches and calls `Sandbox.create("sleep",
   "infinity")` inside the configured Modal App.
2. Workspace bootstrap clones the current git repo (or uploads a
   tarball) into `/workspace`.
3. Tools and bash run via sidecar JSON-RPC.
4. On session close, the sandbox is terminated (unless
   `delete_on_close: false`).

## All Modal options

| YAML key                          | Env var                | Default                       |
| --------------------------------- | ---------------------- | ----------------------------- |
| `modal.python_path`               | `MODAL_PYTHON`         | auto-detected from `modal` CLI |
| `modal.modal_cli`                 | `MODAL_CLI`            | `modal` (on PATH)             |
| `modal.app_name`                  | `MODAL_APP`            | `glue`                        |
| `modal.image`                     | `MODAL_IMAGE`          | Modal's default image         |
| `modal.sandbox_timeout_seconds`   | `MODAL_SANDBOX_TIMEOUT` | `1800`                       |
| `modal.delete_on_close`           | `MODAL_DELETE_ON_CLOSE` | `true`                       |

## See also

- [Runtimes overview](/runtimes)
- [Modal docs](https://modal.com/docs)
