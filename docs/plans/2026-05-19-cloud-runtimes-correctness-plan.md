# Cloud Runtimes — Correctness & Round-Trip Plan

Status: **proposed**
Date: 2026-05-19
Owner: unassigned
Prerequisite: cloud runtimes feature (Daytona / Sprites / Modal) has shipped in 0.4.0

## Goal

Close the silent-data-loss bugs and wrong-state journeys that exist in glue's
cloud runtime feature today. The runtimes themselves work — they can run bash,
edit files, run background jobs in remote sandboxes — but the **bootstrap-in**
and **diff-out** layers make assumptions that don't hold for common user
journeys, and they fail in ways the user can't see.

This plan does not add new runtimes. It makes the runtimes we shipped behave
correctly across the journeys real users will hit.

## Why this plan exists

After shipping 0.4.0 (cloud runtimes + end-of-session diff-out), a user asked
"would the diff-out work for non-git projects?" That question opened a wider
investigation: are there other journeys where the feature silently does the
wrong thing?

We ran five parallel investigations (one per concern: working-tree mismatch,
repo topology, auth, lifecycle, round-trip). They found a lot. The most
dangerous failures share a property: **the user can't tell anything went
wrong.** The agent works on the wrong code. The patch is missing files.
The sandbox is leaked. There's no error.

The architectural root cause is that `WorkspaceBootstrap` conflates four
distinct concerns into one ("the origin remote at HEAD"):

1. **Repo identity** (what is this project)
2. **Fetch source** (where do bytes come from)
3. **Commit reachability** (can we resolve `<sha>`)
4. **Working-tree snapshot** (what does the user's disk look like right now)

In practice these diverge constantly: a user with uncommitted changes has
(4) different from (3); a user with unpushed commits has (3) unreachable
from (2); a user inside a subdirectory has (1) different from cwd.

This plan separates them.

## Reference material

- `packages/glue_runtimes/lib/src/common/bootstrap.dart` — current bootstrap (clone + checkout)
- `packages/glue_runtimes/lib/src/common/diff.dart` — current diff capture (`git diff <sha>`)
- `cli/lib/src/app.dart` — `_captureRuntimePatch` (the host-side save path, around line 393)
- `packages/glue_runtimes/lib/src/{daytona,sprites,modal}/runtime.dart` — per-runtime `RuntimeSession` impls
- `docs/plans/2026-04-19-cloud-runtimes-plan.md` — original (now-shipped) feature plan
- `CHANGELOG.md` — 0.4.0 entry for context on what shipped

## Catalogued failure modes (the punch list)

Grouped by severity. Each entry: what breaks, where, and which phase addresses it.

### Silent data loss (highest severity)

| # | Failure | Where | Phase |
|---|---|---|---|
| S1 | Sprites resume with `bootstrapSha: null` → diff returns null, every change from this session lost | `sprites/runtime.dart`, `common/bootstrap.dart` | 0 |
| S2 | Untracked files (`new_test.dart` created but not `git add`'d) dropped from patch | `common/diff.dart` | 1 |
| S3 | Binary file changes written as `Binary files differ` placeholder — unapplyable | `common/diff.dart` | 1 |
| S4 | Modal sandbox auto-terminates mid-session → diff runs against dead executor → null | `modal/runtime.dart`, `app.dart` | 0 |
| S5 | Two glue sessions against same named Sprite share `/workspace` → concurrent writes corrupt files | `sprites/runtime.dart` | 3 |
| S6 | Hard crash (panic, OOM) before `_captureRuntimePatch` runs → patch lost, sandbox leaked | `app.dart` | 3 |
| S7 | Agent ran `git commit` inside sandbox → `git diff <sha>` squashes N commits into one (history + authorship lost) | `common/diff.dart` | 1 |

### Wrong-state at start (user's example)

| # | Failure | Where | Phase |
|---|---|---|---|
| W1 | Uncommitted working-tree changes invisible to sandbox | `common/bootstrap.dart` | 2 |
| W2 | Staged-but-uncommitted changes invisible | `common/bootstrap.dart` | 2 |
| W3 | Committed-but-unpushed local commits → `git checkout <sha>` fails inside sandbox | `common/bootstrap.dart` | 2 |
| W4 | `.gitignore`'d files the agent needs (`.env`, lockfiles) invisible | `common/bootstrap.dart` | 2 (allowlist) |
| W5 | Detached HEAD / local-only branches → SHA unreachable from origin | `common/bootstrap.dart` | 2 |
| W6 | Stash invisible | `common/bootstrap.dart` | out of scope |
| W7 | Submodules: clone doesn't `--recurse-submodules`, dirs empty | `common/bootstrap.dart` | 4 |
| W8 | LFS pointers not fetched (no git-lfs in sandbox) | sandbox image | 4 |

### Repo topology breaks

| # | Failure | Where | Phase |
|---|---|---|---|
| T1 | Subdir cwd in larger repo — sandbox clones full repo, agent loses subdir context | `common/bootstrap.dart` | 2 |
| T2 | Worktrees (`.git` is a file pointing into parent) — SHA exists only in main repo's reflog, not reachable from fresh clone | `common/bootstrap.dart` | 2 (bundle fixes) |
| T3 | No remote configured — bootstrap throws `UnimplementedError("Tarball bootstrap not yet implemented")` | `common/bootstrap.dart` | 2 |
| T4 | Multiple remotes (fork + upstream) — bootstrap hard-codes `origin`, may pick wrong source | `common/bootstrap.dart` | 2 |
| T5 | Sparse-checkout — sandbox sees full tree, agent edits files user can't see locally | `common/bootstrap.dart` | out of scope |
| T6 | Bare repo / mirror clone cwd — bootstrap path nonsensical | `common/bootstrap.dart` | 4 (refuse + clear msg) |
| T7 | macOS-host → Linux-sandbox case-sensitivity collisions, broken symlinks | sandbox image | out of scope |

### Auth & accessibility

| # | Failure | Where | Phase |
|---|---|---|---|
| A1 | Private repo, host uses SSH → HTTPS rewrite → 401 in sandbox | `common/bootstrap.dart` | 2 (bundle bypasses entirely) |
| A2 | Private repo, host uses HTTPS + credential helper (osxkeychain, gh) → sandbox can't reach helper | `common/bootstrap.dart` | 2 (bundle bypasses entirely) |
| A3 | Private GitLab / Bitbucket / Azure DevOps / self-hosted — no provider-aware token logic | `common/bootstrap.dart` | 2 (bundle bypasses entirely) |
| A4 | Corporate proxy / VPN-only git server unreachable from sandbox | `common/bootstrap.dart` | 2 (bundle bypasses entirely) |
| A5 | SAML / 2FA enforced — token rejected; error buried in `BootstrapException` output | `common/bootstrap.dart` | 4 (error legibility) |
| A6 | Sandbox network policy blocks outbound SSH (port 22) | runtime config | 4 (document in doctor) |

Note: Phase 2's bundle approach incidentally fixes A1–A4 by removing the
sandbox-reaches-remote requirement entirely — bytes are pushed *in*, not
pulled out.

### Lifecycle & resume

| # | Failure | Where | Phase |
|---|---|---|---|
| L1 | `/resume` on a cloud session — no sandboxId persisted, fresh runtime created, prior `runtime.patch` orphaned | `session_store`, `app.dart` | 3 |
| L2 | Ctrl-C during in-flight cloud tool call — local cancel, sandbox process orphaned | `app.dart` | 3 |
| L3 | Network drop + reconnect — no reconnect logic in any cloud transport, session errors out | `daytona/*`, `sprites/*`, `modal/*` | out of scope (future) |
| L4 | `runtimeClose` throws after agent work → sandbox leaked, no retry, no surfaced warning | `app.dart` | 3 (cleanup queue) |
| L5 | Daytona snapshot drift over time (user re-tags snapshot, sessions inherit silently) | bootstrap | out of scope |

### Diff-out / round-trip

| # | Failure | Where | Phase |
|---|---|---|---|
| R1 | No `glue session apply` / `diff` / `export` — patch saved to disk with no scaffolding | new `glue session` subcommand | 3 |
| R2 | Patch has no metadata header (bootstrap SHA, remote, runtime, format) → apply tool has no context | `app.dart`, `common/diff.dart` | 0 |
| R3 | `git apply` fails on dirty host workspace, no preflight, no 3-way fallback | future `glue session apply` | 3 |
| R4 | Host moved past bootstrap SHA → patch lands on wrong context (silent if hunks happen to apply) | future `glue session apply` | 3 |
| R5 | Plain `git diff` doesn't emit rename detection — renames look like delete+add, bloating patch | `common/diff.dart` | 1 |
| R6 | Sandbox is Linux, host is macOS/Windows → CRLF normalization pollutes diff | `common/diff.dart` | out of scope |
| R7 | Patch can be hundreds of MB (vendored deps, generated assets) — no cap, no warning | `app.dart` | 0 (cap + warn) |
| R8 | Lockfile changes in patch apply cleanly but produce inconsistent install (sandbox vs host platform) | apply UX | 3 (warn) |

## Phases

Each phase is independently mergeable and shippable. Phases stay small enough
to land in one PR per. Phase 0 is the cheapest highest-leverage safety net —
do it first regardless of what's prioritized after.

---

### Phase 0 — Stop silent data loss (safety net)

**Goal:** No more silent nulls. Every "we couldn't capture a diff" case
becomes a visible warning, with metadata, before the sandbox closes.

**Addresses:** S1, S4, R2, R7 (partial). Cheap and pure-defensive — no
architectural change.

**Changes:**

1. `packages/glue_runtimes/lib/src/common/diff.dart`
   - When `bootstrapSha == null`, return a typed `DiffUnavailable` reason
     instead of plain `null`. Reasons: `noBootstrapSha`, `gitFailed`,
     `executorDead`, `runtimeNotGit`. Caller can distinguish.
   - Add `DiffOutcome` sealed type: `DiffSuccess(String patch, DiffMeta meta)`,
     `DiffEmpty(DiffMeta meta)`, `DiffUnavailable(Reason reason, String? hint)`.

2. `packages/glue_runtimes/lib/src/sprites/runtime.dart`
   - When `bootstrap()` returns `resumed: true` with no `bootstrapSha`, the
     runtime re-baselines: `executor.runCapture('git -C /workspace rev-parse HEAD')`.
     That becomes the new `bootstrapSha`. If git fails (no `.git`), record
     `DiffUnavailable.runtimeNotGit` for later.
   - If user's last session left uncommitted changes in the worktree, log a
     warning and either auto-stash with a tracked ref name or refuse with a
     clear message (TBD — see Open question Q1).

3. `packages/glue_runtimes/lib/src/modal/runtime.dart`
   - Wrap `_sidecar.execCapture` calls with a "sidecar still alive" preflight.
     If the sidecar process is dead, surface that explicitly to the caller
     so the App can show "sandbox terminated mid-session" instead of a generic
     exec failure.

4. `cli/lib/src/app.dart` (`_captureRuntimePatch`)
   - Switch from `Future<String?>` to `Future<DiffOutcome>`.
   - On `DiffUnavailable`: print a single-line warning naming the reason and
     pointing at `glue doctor` (or a TBD remediation command).
   - On `DiffSuccess`: write the patch *plus* a `runtime.patch.meta.json`
     sidecar file containing `{runtimeId, sandboxId, bootstrapSha, remoteUrl,
     runtimeCwd, format: "diff", capturedAt, sizeBytes}`.
   - Enforce a size cap (default 50 MB) — on overflow, save first N bytes
     plus a truncation note, log path to full patch if user wants it.

**Tests:**

- `diff_test.dart` covers each `DiffUnavailable` reason.
- New `sprites/runtime_resume_test.dart` covers the re-baseline path with
  both clean-resume and dirty-resume.
- New `app/capture_runtime_patch_test.dart` covers DiffOutcome → sidecar
  metadata file + warning message + size cap truncation.

**Acceptance:**

- A Sprites session 2 that resumes after session 1 made changes produces
  either a valid baseline + diff OR a clear warning. Never silent null.
- A Modal sandbox that times out mid-session produces a visible "sandbox
  terminated" message at shutdown.
- `runtime.patch.meta.json` exists alongside every `runtime.patch`.

**Out of scope for this phase:** changing what's in the patch (Phase 1),
changing how bootstrap fetches code (Phase 2), wiring a `glue session apply`
command (Phase 3).

---

### Phase 1 — Capture the right diff (`git format-patch` not `git diff`)

**Goal:** Patches include untracked files, binary changes, renames, and full
commit history with authorship — suitable for `git am --3way` on the host.

**Addresses:** S2, S3, S7, R5. Highest leverage single change in the entire
plan — fixes most of the "I applied the patch and X is wrong/missing" class
of failures.

**Changes:**

1. `packages/glue_runtimes/lib/src/common/diff.dart`
   - Replace the single `git diff <sha>` call with a three-step capture:
     a. `git -C $cwd add -N -- .` (intent-to-add for untracked, so they
        appear in the patch). Suppress errors on .gitignore conflicts.
     b. `git -C $cwd format-patch --binary -M -C --stdout <bootstrapSha>..HEAD`
        if `HEAD != bootstrapSha` (multi-commit case).
     c. `git -C $cwd diff --binary -M -C <bootstrapSha>` for the working-tree
        delta on top of HEAD.
   - Concatenate (b) + (c) into a single mbox-formatted output. If both are
     empty, return `DiffEmpty`.

2. `cli/lib/src/app.dart` (`_captureRuntimePatch`)
   - Save as `runtime.mbox` (was `runtime.patch`). Update the breadcrumb
     line to mention `git am --3way runtime.mbox` as the suggested apply
     command.
   - Update `runtime.patch.meta.json` → `runtime.mbox.meta.json`,
     `format: "format-patch"`.

3. `docs/reference/runtime-capabilities.yaml` — add a `diff_format` column
   so the website matrix can show what's captured (commits + working tree
   vs just working tree).

**Tests:**

- `diff_test.dart` extended with fixture scenarios:
  - Sandbox with untracked file → patch includes it
  - Sandbox with binary file change → patch includes binary blob
  - Sandbox with rename → single rename hunk, not delete+add
  - Sandbox with `git commit` of N commits → mbox has N entries with
    preserved authorship/message
  - Sandbox with no changes → `DiffEmpty`
- Integration: round-trip test — generate patch in a temp git repo, apply
  with `git am` to another temp clone, assert tree equivalence.

**Acceptance:**

- A round-trip of `mkdir foo && echo bar > foo/baz.bin && git diff` →
  `mbox` → `git am` reproduces `foo/baz.bin` byte-for-byte on a fresh clone.
- The CHANGELOG entry for this phase calls out `git am --3way` as the
  recommended apply path.

**Out of scope:** the apply UX itself (Phase 3), bundling LFS pointers
(Phase 4), CRLF normalization across platforms (deferred).

---

### Phase 2 — Send the working tree, not just HEAD (git bundle)

**Goal:** Sandbox bootstrap captures the user's actual working state —
uncommitted, unpushed, untracked-but-needed, local-only branches, worktrees
with un-pushable SHAs. Bypasses sandbox-side auth entirely (bytes are pushed
in, not pulled out).

**Addresses:** W1, W2, W3, W4, W5, T1, T2, T3, T4, A1, A2, A3, A4. This is
the architectural fix.

**Approach:**

Pre-bootstrap, on the **host**, run:

```
git --git-dir=$tmp_git_dir --work-tree=$host_cwd init
git --git-dir=$tmp_git_dir --work-tree=$host_cwd add -A
git --git-dir=$tmp_git_dir --work-tree=$host_cwd commit \
    -m "glue bootstrap $sessionId" --allow-empty-message
git --git-dir=$tmp_git_dir bundle create $bundle_path --all
```

This produces a single bundle file containing one commit that snapshots the
host working tree (respecting host's `.gitignore` via `git add -A`). Upload
the bundle file via the runtime's writeFile primitive, then in the sandbox:

```
git clone $bundle_path /workspace
cd /workspace && git remote remove origin
```

`bootstrapSha` is the synthetic commit SHA. End-of-session diff against it
captures everything the agent did. `git am --3way` on the host applies
against the *real* host HEAD (not the synthetic one), so the user's history
on disk is unchanged.

**Per-runtime upload feasibility (verified):**

| Runtime | Path | Practical bundle size | Notes |
|---|---|---|---|
| Daytona | multipart `/files/upload` | hundreds of MB | works |
| Modal | base64-in-JSON to Python sidecar → `sb.filesystem.write_bytes` | ~30 MB before JSON parsing gets ugly | works; chunked upload deferred |
| Sprites | base64-in-shell-exec via `sprite exec` | a few MB before CLI/WebSocket buffering breaks | tight; document the cap, defer chunking |

A typical small project bundle is ~100 KB – 5 MB. All three runtimes handle
that. Large monorepos exceed Sprites' limit — for those, the existing
git-clone path remains available as a fallback (see "Hybrid logic" below).

**Changes:**

1. New `packages/glue_runtimes/lib/src/common/host_bundle.dart`
   - `Future<HostBundle> buildHostBundle({required String hostCwd, required String sessionId})`
   - Returns `HostBundle { File path, String bundleSha, int sizeBytes,
     String? originRemoteUrl }`.
   - Uses a temp git-dir under `~/.glue/sessions/<id>/bootstrap.git` so the
     user's actual `.git` is never touched.
   - Cleanup: bundle file deleted after upload succeeds; tmp git-dir retained
     for diagnostics (cheap).

2. `packages/glue_runtimes/lib/src/common/bootstrap.dart`
   - Add a new `BootstrapStrategy` enum: `bundle`, `cloneFromRemote`,
     `cloneFromRemoteThenApplyBundle` (hybrid for huge projects — clone
     reduces transfer; bundle applies dirty state on top).
   - Selection logic:
     - Host cwd is not a git repo → `bundle` (creates synthetic git in temp)
     - Host cwd is a git repo, bundle ≤ size cap for runtime → `bundle`
     - Host cwd is a git repo, bundle > cap → `cloneFromRemoteThenApplyBundle`
       (if remote reachable and SHA pushable) OR `bundle` with truncation
       warning OR refuse with clear message
   - Per-runtime caps: Daytona 200 MB, Modal 30 MB, Sprites 3 MB (tunable).

3. New `packages/glue_runtimes/lib/src/common/bundle_upload.dart`
   - `Future<void> uploadBundle({required Runtime runtime, required File bundle, required String runtimeDestPath})`
   - Per-runtime impl pluggable; uses each runtime's existing writeFile path.

4. `packages/glue_runtimes/lib/src/{daytona,sprites,modal}/runtime.dart`
   - Each runtime's `start()` switches on `BootstrapStrategy`. Bundle path
     calls into shared upload + sandbox-side `git clone <bundle>`.

5. `cli/lib/src/doctor/doctor.dart`
   - New check: probe upload-size cap for the active runtime, surface in
     `glue doctor` so users know the limit before they hit it.

**Tests:**

- `host_bundle_test.dart` covers:
  - Plain non-git directory → bundle created with synthetic init commit
  - Git directory with uncommitted edits → bundle includes edits as the
    commit
  - Git directory with submodules → bundle skips them (with warning) or
    includes (TBD — see Phase 4)
  - Empty directory → empty bundle vs refuse
- `bundle_upload_test.dart` per runtime with fake upload primitive
- Integration: e2e against Docker (proxy for cloud) — bundle a dirty
  workspace, bootstrap, verify sandbox sees uncommitted file

**Acceptance:**

- A user with uncommitted edits to `foo.dart` starts a cloud session; the
  agent sees the edited version, not HEAD.
- A user with no remote configured can start a cloud session (no
  `UnimplementedError`).
- A user with unpushed commits can start a cloud session without first
  pushing.
- `glue doctor` reports the upload cap for the active runtime.

**Out of scope:** chunked upload for Sprites (deferred), LFS through-bundle
(Phase 4), submodule handling (Phase 4), sparse-checkout (deferred).

---

### Phase 3 — Session persistence, lifecycle, and apply UX

**Goal:** `runtime.patch` becomes a first-class artifact a user can list,
inspect, and apply through `glue session …`. Session resume understands
cloud runtimes. Sandbox leaks are detected and cleaned up.

**Addresses:** L1, L2, L4, R1, R3, R4, R8, S5, S6.

**Changes:**

1. Session-meta extension (`packages/glue_harness/lib/src/storage/session_store.dart`)
   - Add fields: `runtimeId`, `sandboxId`, `bootstrapSha`, `remoteUrl`,
     `patchPath`, `runtimeClosedAt`.
   - Write at session start (after bootstrap) and on session close (with
     `patchPath` filled).

2. New `cli/lib/src/commands/session_command.dart` (`glue session …`):
   - `glue session list` — list sessions with patch availability + size
   - `glue session show <id>` — print metadata + first-screen of patch
   - `glue session diff <id>` — print full patch
   - `glue session apply <id> [--3way] [--branch <name>]` — apply via
     `git am --3way` (Phase 1's format-patch output); `--branch` creates
     and switches to a new branch at the host's current HEAD first
   - `glue session export <id> --to <path>` — copy patch + meta out

3. `/session` slash command sibling — read-only versions of the above.

4. Mid-session checkpoint (`cli/lib/src/app.dart`)
   - Every N tool calls (default 10) or M minutes (default 5), capture
     a checkpoint diff to `runtime.patch.partial`. Recovery sweep on
     glue startup picks up partials and offers to apply.

5. Cleanup queue
   - Persist active sandboxId per session in session-meta when bootstrap
     succeeds. On glue startup, sweep meta for sessions whose `runtimeClosedAt`
     is null but session timestamp > 24h → offer to stop the sandbox via
     the matching adapter.
   - New `glue runtime cleanup` command exposes the same sweep on demand.

6. Sprites concurrent-attach guard (`packages/glue_runtimes/lib/src/sprites/runtime.dart`)
   - File-lock under `~/.glue/runtime-locks/sprites/<sprite-name>.lock`.
     Second attach refuses with "another glue session is using this sprite
     in `<other-cwd>`; close it first."

**Tests:**

- `session_command_test.dart` for the new command surface
- `cleanup_sweep_test.dart` with synthetic stale session-meta entries
- `sprites/concurrent_attach_test.dart` simulates two startups against the
  same sprite

**Acceptance:**

- `glue session apply <id> --branch glue/<id>` creates a branch from the
  user's current HEAD, applies the agent's patch via `git am --3way`,
  leaves conflicts as `.rej` files for the user to resolve.
- `glue runtime cleanup` lists and offers to stop any sandboxes glue has
  abandoned. Daytona / Sprites / Modal supported.
- A second `glue` against the same Sprites sprite name refuses with a
  clear message.

**Out of scope:** automatic conflict resolution, automatic dependency
re-install (R8 — warn only), full reattach-on-network-drop (L3, deferred).

---

### Phase 4 — Auth legibility, repo edge cases, defensive sanding

**Goal:** When something does fail, the user knows immediately what failed
and what to do. Handle the remaining repo topology cases that aren't worth
their own phase.

**Addresses:** A5, A6, W7, W8, T6, error legibility throughout.

**Changes:**

1. Bootstrap error classification (`packages/glue_runtimes/lib/src/common/bootstrap.dart`)
   - Replace bare `BootstrapException(exit=128)` with typed subclasses:
     `BootstrapAuthError`, `BootstrapNetworkError`, `BootstrapNotAGitRepo`,
     `BootstrapMissingBinary`, `BootstrapSamlError`, `BootstrapUnknown`.
   - Pattern-match git's stderr to assign the right type. Each carries a
     `remediationHint` field.

2. Submodule handling
   - Bundle path (Phase 2): `git submodule foreach git add -A` then bundle
     each submodule separately (or recursive bundle if git supports it)
   - Clone path: `git clone --recurse-submodules`
   - Sandbox: ensure git-submodule is in the base image (probably already
     is — verify per runtime)

3. LFS handling
   - Modal/Daytona/Sprites: probe for git-lfs in `glue doctor` per runtime
   - When present, run `git lfs install` post-bootstrap
   - When absent, warn that LFS files will be pointer-only

4. Bare repo / mirror clone refusal
   - Host-side check before bootstrap: if `git rev-parse --is-bare-repository`
     is true, refuse with "cloud runtimes need a working tree, not a bare
     repo".

5. `glue doctor` runtime section
   - Add: bundle upload cap, git-lfs availability in sandbox image, network
     egress (probe outbound https/ssh from sandbox), credential helper on host

**Tests:** existing test patterns extended per change.

**Acceptance:**

- Attempting to clone a private repo from a sandbox without forwarded auth
  produces "authentication failed for `<remote>` — try Phase 2's bundle
  bootstrap or set up an HTTPS token" instead of `BootstrapException(exit=128)`.
- Submodules work end-to-end in Daytona (e2e test).
- `glue doctor` reports green/yellow/red per cloud-runtime auth + network
  check.

**Out of scope:** Phase 5+ items.

---

### Phase 5+ — Deferred / future

Tracked but not scheduled. Each is a real journey but lower frequency or
higher cost:

- **Reattach on network drop** (L3) — needs reconnect logic in all three
  cloud transports + reclaiming RunningCommands. Significant.
- **Cross-platform line endings / filemode** (R6) — needs `.gitattributes`
  awareness through the bundle/diff pipeline.
- **Sparse-checkout mirroring** (T5) — requires translating host sparse
  cone into the sandbox clone.
- **Macros / case-sensitivity collision detection** (T7) — host fs probe
  + sandbox warning.
- **Auto-rerun `npm install` / `pip install` on apply when lockfile changes** (R8) — opinionated, opt-in.
- **Multi-cloud parallelism / fanout** — running the same prompt across
  Daytona + Modal for comparison.

## Non-goals

Explicitly off the table for this plan:

- New cloud runtime adapters (E2B, hopx, etc.) — separate effort.
- Refactoring the `RuntimeSession` interface — current shape is fine.
- Changing the model interaction layer or tool definitions — the agent's
  prompt is unaffected by everything here.
- A web UI for session inspection — `glue session …` is CLI-only.
- Stash transfer (W6) — too niche; users who stash and want it in the
  sandbox can `git stash pop` before starting.

## Open questions (must resolve before each phase)

| # | Question | Phase | Default |
|---|---|---|---|
| Q1 | Sprites dirty-resume: auto-stash to a tracked ref, or refuse with clear message? | 0 | refuse — explicit safer than implicit |
| Q2 | What's the default size cap for `runtime.patch` saving (truncation threshold)? | 0 | 50 MB |
| Q3 | Should Phase 1's mbox include the agent's working-tree state (uncommitted in sandbox) as a final implicit commit, or only real commits? | 1 | final implicit commit — captures everything the agent did |
| Q4 | For Phase 2's host-side temp git-dir, do we respect the host's `core.excludesFile` and a `.glueignore`, or just use `git add -A` defaults? | 2 | `git add -A` only — keep it simple; revisit if users ask |
| Q5 | Phase 2 hybrid logic threshold: when do we choose `cloneFromRemoteThenApplyBundle` vs pure `bundle`? | 2 | bundle ≤ runtime cap, else hybrid if remote reachable |
| Q6 | `glue session apply` default behaviour — apply to current HEAD, or always create a new branch? | 3 | new branch by default; `--in-place` for current HEAD |
| Q7 | Mid-session checkpoint cadence — every N tool calls, every M minutes, or both? | 3 | both, OR'd; tunable in config |
| Q8 | LFS: ship `git-lfs` in our wrapped runtime images, or document the dep? | 4 | ship — invisible to user |

## Verification across the full plan

After all phases land, the user's original example should "just work":

> "I was working on glue locally with uncommitted changes, started a cloud
> session, and the agent started working on an old version of the code."

End state:
1. User starts `glue --runtime daytona` in a dirty working tree.
2. Glue host-side bundles the dirty tree (Phase 2).
3. Sandbox starts at the bundle commit — agent sees uncommitted edits.
4. Agent makes changes, possibly commits inside sandbox.
5. Session ends. Phase 1's `git format-patch + diff` captures everything
   including untracked / binary / renames.
6. Patch + meta saved (Phase 0).
7. User runs `glue session apply <id> --branch glue/<id>` (Phase 3) — a
   new branch is created at host HEAD, agent's commits and worktree changes
   are applied via `git am --3way`, conflicts surface as `.rej` files for
   review.
8. If anything went wrong during the session, the user got a visible
   warning at shutdown (Phase 0) and a typed error (Phase 4).

## Implementation order — recommended sequencing

1. **Phase 0** first (1 PR, ~1 day). Pure safety net, no user-visible
   workflow change beyond clearer warnings. Ship and observe.
2. **Phase 1** next (1 PR, ~1 day). Highest leverage; round-trip becomes
   correct. Ship and test on a real cloud session.
3. **Phase 2** (1–2 PRs, ~3–5 days). Architectural; the bundle approach
   needs careful per-runtime testing. Most code volume.
4. **Phase 3** (2–3 PRs, ~5 days). Lots of small surface area; the
   `glue session …` subcommand is the bulk.
5. **Phase 4** (1–2 PRs, ~2–3 days). Mostly classification + doctor +
   image deps. Lower urgency, can land anytime after Phase 2.

Phases 0 and 1 together close the silent-data-loss class. Phase 2 closes
the wrong-state-at-start class. After Phases 0–2 ship, the feature is
*correct* (no silent failures, no wrong starting state). Phases 3 and 4
make it *useful* (apply UX, error messages).

## References

- This plan was produced from a five-agent parallel investigation on
  2026-05-19. The agent reports are not preserved as files but were
  synthesized into the "Catalogued failure modes" section above.
- Original cloud runtimes plan: `docs/plans/2026-04-19-cloud-runtimes-plan.md`
  (status: shipped 0.4.0).
- 0.4.0 CHANGELOG entry for context on what's in scope today.
