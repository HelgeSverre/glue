# `~/.glue/preferences.json` — Runtime Preferences Store

Machine-managed JSON file used by `ConfigStore` (`lib/src/storage/config_store.dart`).

- Not intended for manual editing.
- Internal format; may change between versions.

## Current Schema

```json
{
  "trusted_tools": ["read_file", "grep", "bash"]
}
```

## Fields

| Field | Type | Description |
| --- | --- | --- |
| `trusted_tools` | `string[]` | Tool names permanently approved by the user (skip confirmation prompts). |

## Behavior

- Missing file is treated as `{}`.
- Reads are cached and reloaded when file mtime/size changes.
- Writes are atomic (`.tmp` + rename).

## Relationship to `config.yaml`

- `config.yaml` is user-authored static configuration.
- `preferences.json` is runtime preference state updated by Glue during use.
- `preferences.json` does **not** provide provider/model overrides.
- Legacy fallback: if `preferences.json` is missing, Glue can read `config.json`
  from older versions, then writes back to `preferences.json`.
