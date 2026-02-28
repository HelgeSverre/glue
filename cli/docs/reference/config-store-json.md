# `~/.glue/config.json` — Runtime Configuration Store

Machine-managed JSON file for runtime state. **Not user-edited.** Managed by `ConfigStore` (`lib/src/storage/config_store.dart`).

> **Stability:** Internal format; may change between Glue versions.

## Schema

```json
{
  "default_provider": "anthropic",
  "default_model": "claude-sonnet-4-6",
  "trusted_tools": ["bash", "write_file"],
  "debug": true
}
```

## Fields

| Field              | Type     | Default | Description                                                 |
| ------------------ | -------- | ------- | ----------------------------------------------------------- |
| `default_provider` | string?  | `null`  | Provider override (set via TUI, e.g. `/set provider`)       |
| `default_model`    | string?  | `null`  | Model override                                              |
| `trusted_tools`    | string[] | `[]`    | Tools the user has permanently approved (skip confirmation) |
| `debug`            | bool     | `true`  | Enable debug logging to `~/.glue/logs/`                     |

## Behavior

- **Read:** `ConfigStore.load()` — returns cached copy, re-reads from disk only if mtime/size changed.
- **Write:** `ConfigStore.save()` / `ConfigStore.update()` — atomic write via tmp-file rename.
- **File absence:** Treated as empty config (`{}`). No error.

## Relationship to `config.yaml`

- `config.yaml` is the **user's intent** — hand-edited, loaded once at startup.
- `config.json` is **runtime state** — machine-written, read on demand, mutable during session.
- `config.json` values can override `config.yaml` for fields like `default_provider` / `default_model` when set interactively.
