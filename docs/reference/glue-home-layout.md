# `~/.glue/` Directory Layout

The `~/.glue/` directory is the user's Glue home. It stores configuration, session history, and logs. Managed by `Environment` (`lib/src/core/environment.dart`).

## Directory Structure

```
~/.glue/
├── config.yaml          # User-edited configuration (provider, model, shell, docker, etc.)
├── preferences.json     # Machine-managed runtime state (trusted tools)
├── config.json          # Legacy runtime state file from older versions
├── sessions/
│   └── <session-id>/
│       ├── meta.json          # Session identity (immutable after creation)
│       ├── conversation.jsonl # Conversation log (append-only)
│       └── state.json         # Mutable session-scoped runtime state
└── logs/
    └── ...                    # Debug logs
```

## Files

### `config.yaml` — User Configuration

**Owner:** User (hand-edited or set via CLI flags).  
**Format:** YAML.  
**Schema:** See [config-yaml.md](config-yaml.md).

Loaded once at startup by `GlueConfig.load()`. Resolution order: CLI args → env vars → config.yaml → defaults.

### `preferences.json` — Runtime Configuration Store

**Owner:** Glue application (machine-written).  
**Format:** JSON.  
**Schema:** See [config-store-json.md](config-store-json.md).  
**Stability:** Internal; may change between versions.

Managed by `ConfigStore` (`lib/src/storage/config_store.dart`). Read on demand with filesystem-change detection (mtime + size). Written atomically via tmp-file rename.

On upgrade, Glue can still read legacy `config.json` if `preferences.json`
does not exist yet.

### `sessions/<id>/meta.json` — Session Identity

**Owner:** `SessionStore` (written once at creation, updated on close).  
**Format:** JSON.  
**Schema:** See [session-storage.md](session-storage.md).

Contains session metadata: id, project path, model, provider, git context (worktree, branch, remote, SHA), timestamps, tags, PR lifecycle, and metrics. See session-storage.md for the full schema.

### `sessions/<id>/conversation.jsonl` — Conversation Log

**Owner:** `SessionStore` (append-only during session).  
**Format:** JSONL (one JSON object per line).  
**Schema:** See [session-storage.md](session-storage.md).

Each line is a timestamped event record with a `type` field.

### `sessions/<id>/state.json` — Session Runtime State

**Owner:** Application (read/written during session).  
**Format:** JSON.  
**Schema:** See [session-storage.md](session-storage.md).  
**Lifecycle:** Created on first write. Missing file = empty/default state.

Stores mutable, session-scoped settings such as Docker mount whitelist. Survives session resume. Deleted when the session directory is garbage-collected.

## Lifecycle & Cleanup

- **Creation:** `Environment.ensureDirectories()` creates `sessions/`, `logs/`, and `cache/` on startup.
- **Session directories** accumulate over time. No automatic GC yet — future `/sessions prune` command.
- **Deletion:** Removing a session directory removes all its files (`meta.json`, `conversation.jsonl`, `state.json`).
