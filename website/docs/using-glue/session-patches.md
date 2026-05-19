# Session Patches

When a session runs in a cloud runtime (Daytona, Sprites, Modal), every
change the agent made inside the sandbox is captured at shutdown and
saved to disk as `runtime.mbox` — a `git format-patch` mbox you can
apply back to your host workspace.

```
~/.glue/sessions/<session-id>/
├── conversation.jsonl
├── meta.json
├── runtime.mbox              ← agent's changes
└── runtime.mbox.meta.json    ← runtime + bootstrap context
```

## What's in the patch

Phase 1 of the cloud runtime correctness work moved capture from
`git diff` to `git format-patch --binary -M -C` plus a working-tree
diff on top. This means the patch preserves:

- **Untracked files** — anything the agent created without `git add`.
  (A `git add -N` intent-to-add runs first so untracked paths appear
  in the diff.)
- **Binary files** — byte-for-byte. Images, PDFs, fixtures all survive
  via `--binary`.
- **Renames and copies** — `-M -C` keeps a moved file as one rename
  hunk, not delete + add.
- **Agent commits** — if the agent ran `git commit` inside the
  sandbox, each commit appears as its own mbox entry with the
  original message and authorship.
- **Working-tree changes on top of HEAD** — uncommitted edits the
  agent made after its last commit.

If the agent didn't change anything, the patch isn't written and no
warning is printed.

## When no patch is captured

If the runtime couldn't produce a diff, you'll see a warning at session
shutdown instead of silence:

```
◆ Runtime workspace diff unavailable (noBootstrapSha): runtime did not
  record a bootstrap commit (resumed sandbox?); commit changes inside
  the sandbox before exiting to preserve them
```

Reasons surfaced today:

| Reason | Meaning |
|---|---|
| `noBootstrapSha` | Runtime never recorded a baseline (typically a resumed Sprites sandbox where `bootstrap` short-circuited) |
| `gitFailed` | `git` exited non-zero inside the sandbox (no repo, bad SHA, etc.) |
| `executorDead` | Sandbox transport died (Modal sandbox auto-terminated, network drop) |
| `runtimeNotGit` | Workspace isn't a git repo |
| `notSupported` | Host/Docker runtime — captured silently, not surfaced as a warning |

## The `runtime.mbox.meta.json` sidecar

Every saved patch has a companion metadata file:

```json
{
  "runtime_id": "daytona",
  "sandbox_id": "sb-abc123",
  "bootstrap_sha": "deadbeef…",
  "remote_url": "https://github.com/you/repo.git",
  "runtime_cwd": "/workspace",
  "format": "format-patch",
  "captured_at": "2026-05-19T10:24:00Z",
  "size_bytes": 4892,
  "truncated": false,
  "truncation_cap_bytes": 52428800
}
```

Apply tools — `glue session apply` and any third-party tooling — read
this so they don't have to re-infer context from the patch body.

## Size cap

Patches are capped at 50 MB. A larger diff is written to
`runtime.mbox.truncated` (note the suffix) with a visible warning, and
`glue session apply` refuses to apply the truncated file as-is. This
keeps a misbehaving agent (or a `node_modules` commit) from filling
your session directory with hundreds of MB you can't use.

## Working with patches

### List

```bash
glue session list
```

Shows every session with its runtime, patch availability, and size:

```
01HMA2EY9…  daytona  patch=4892 bytes   Refactor auth helpers
01HMA2C3K…  sprites  patch=-           Quick lookup
01HMA274X…  host     patch=-           Local dev
```

### Show

```bash
glue session show <id>
```

Prints the metadata plus the first 40 lines of the patch so you can
eyeball what the agent did before applying.

### Diff

```bash
glue session diff <id> | less
```

Streams the full mbox to stdout.

### Apply

```bash
glue session apply <id>
```

By default this creates a branch `glue/<session-id>` from your current
`HEAD` and runs `git am --3way` (the proper apply path for a
format-patch mbox — preserves commits with their original messages
and authorship). Falls back to `git apply --3way` for working-tree-only
patches.

Flags:

- `--branch <name>` — pick the branch name instead of the default
- `--in-place` — apply on the current branch, no new branch
- `--target <dir>` — apply to a directory other than the cwd

On conflicts, the `.rej` files are surfaced for you to resolve.

```
git am and git apply both failed. Inspect rejections or apply manually:
  rejection: /path/to/file.dart.rej
```

### Export

```bash
glue session export <id> --to /tmp/agent-work.mbox
```

Copies the patch + the meta sidecar to a destination — useful for
sending to a teammate or attaching to a PR.

## Workflow examples

**Land the agent's work as a branch you can PR:**

```bash
GLUE_RUNTIME=daytona glue "refactor the auth helpers to use the new
  CredentialStore API"
# ... session ends ...
glue session apply <id>
# → on branch glue/<id>; tests + push as usual
```

(You can also set `runtime: daytona` in `~/.glue/config.yaml` to make it
the default instead of passing the env var each time.)

**Inspect before applying:**

```bash
glue session show <id>          # quick look at metadata + first 40 lines
glue session diff <id> | less   # full patch
glue session apply <id>         # if it looks good
```

**Apply to a clean checkout instead of your working tree:**

```bash
git worktree add /tmp/review-branch HEAD
glue session apply <id> --target /tmp/review-branch
```

## Slash command

`/session` inside an interactive session shows the same metadata —
when running in a cloud sandbox, it tells you where the patch will land
on close:

```
Session Info
  …
  Runtime:      daytona
  Sandbox:      sb-abc123
  Patch on close: ~/.glue/sessions/01HMA2EY9…/runtime.mbox
```

## See also

- [Runtimes overview](/runtimes) — capability matrix
- [Daytona](/docs/using-glue/daytona) — REST sandbox, bundle bootstrap
- [Sprites](/docs/using-glue/sprites) — Fly.io persistent sandbox
- [Modal](/docs/using-glue/modal) — Python-sidecar sandbox
