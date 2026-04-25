# Cloud Runtimes — Research & Plan

Status: **proposed — deferred**
Date: 2026-04-19
Last revised: 2026-04-25 (post-`c1-turn` refactor: `service_locator` → `boot/wire.dart` references; `cli/lib/glue.dart` barrel removed; `backlog/` task IDs dropped — no such tracker exists in the repo)
Owner: unassigned
Prerequisite: the boundary-prep work in `2026-04-19-runtime-boundary-plan.md` must land first. None of it has shipped as of 2026-04-25.

## Goal

Add support for remote cloud sandbox runtimes so Glue can execute work
outside the user's host and Docker — on providers like E2B, Daytona, Modal,
Fly.io Sprites, Bunnyshell/hopx, Northflank.

## Status — why deferred

Research is complete. Workspace sync (Option D) and universal workspace
path (`/workspace`) are decided; remaining design decisions listed under
"Open questions" below. Implementation is **not scheduled**. Revisit when:

- The boundary-prep cleanups in `2026-04-19-runtime-boundary-plan.md` have
  landed — the `RunningCommandHandle` interface and JSONL runtime events
  make cloud adapter work substantially cheaper. As of 2026-04-25 none of
  those cleanups have shipped.
- A real workload demands a cloud runtime (GPU, untrusted code, long-running
  parallel agents).
- Daytona or E2B ships a Dart SDK — would collapse the biggest single cost
  driver for either adapter.

## Related work

- `docs/plans/2026-04-19-runtime-boundary-plan.md` — boundary prep plan.
  Must ship before this plan.
- `docs/reference/runtime-capabilities.yaml` — capability matrix source.
- `cli/lib/src/shell/command_executor.dart` — current abstraction.
- `cli/lib/src/boot/wire.dart` — composition root where a future
  `RuntimeFactory` would be wired (replaces the deleted `service_locator`).
- `website/.vitepress/theme/components/RuntimeMatrix.vue` — capability
  matrix renderer.

## Scope decisions (2026-04-19 brainstorming)

| Question                                | Decision                                                                                                                                                                                             |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Research scope                          | Breadth-first across 6 providers                                                                                                                                                                     |
| Implementation scope                    | Top 3 only                                                                                                                                                                                           |
| Top-3 selection criterion               | Blend of popularity and capability/coverage                                                                                                                                                          |
| Credentials (V1)                        | Env vars only (`E2B_API_KEY`, `DAYTONA_API_KEY`, etc.). Defer integration with the existing `CredentialStore` (`cli/lib/src/credentials/credential_store.dart`) to a follow-up.                      |
| Workspace sync model                    | **Option D — git-first bootstrap + per-provider persistence opt-in** (decided 2026-04-19; see §"Workspace sync" below). Aligns with VibeKit's `.withGithub({ token, repository })` + `branch` model. |
| Universal workspace path                | **`/workspace`** across all runtimes — Docker, host, cloud. Landed in Docker 2026-04-19. Matches VibeKit / E2B / Daytona / Sprites defaults.                                                         |
| Top-3 providers                         | **Undecided** — candidate shortlist proposed                                                                                                                                                         |
| Browser endpoint ownership              | **Undecided**                                                                                                                                                                                        |
| Per-session vs global runtime selection | **Undecided**                                                                                                                                                                                        |

---

## Provider landscape — April 2026

### Mindshare snapshot

**OpenAI Agents SDK built-in sandbox list (April 2026 update):**
Blaxel, Cloudflare, Daytona, E2B, Modal, Runloop, Vercel.
This is the strongest single popularity signal in the ecosystem.

**Top 4 by agent-developer mindshare:** E2B › Daytona › Modal › Fly.io Sprites.

**Also frequently cited:** CodeSandbox SDK (Together AI), Bunnyshell/hopx,
Northflank, Runloop.

### 6 providers evaluated in detail

#### E2B (e2b.dev)

- **Isolation:** Firecracker microVM, ~200ms cold start
- **SDK:** Python, JS/TS official; **no Dart**
- **Transport:** REST control plane (OpenAPI 3.0) + gRPC `envd` data plane
  for exec and filesystem
- **Persistence:** `pause()`/`resume(id)`; 14-day retention on paid tier;
  known multi-resume FS-loss bug (GH issue #884)
- **Session limits:** Hobby 1h, Pro 24h; concurrent 20/100 (up to 1100
  purchased)
- **Browser:** `browser` template with CDP, `desktop` template with VNC
- **GPU:** Not on public tier; BYOC AWS only
- **Pricing:** 2vCPU + 4GiB ≈ $0.165/hr
- **Popularity:** 11.7k GH stars, biggest agent ecosystem (LangChain,
  CrewAI, AutoGen, OpenAI SDK, Mastra, Dify); customers include Perplexity,
  Hugging Face, Manus, Salesforce
- **Dart implementation cost:** **High** — gRPC envd requires either a
  hand-written Dart gRPC client (protos in `e2b-dev/infra`) or a Node/Python
  sidecar.

#### Daytona (daytona.io)

- **Isolation:** Docker default; Kata/Sysbox for hardened runs
- **SDK:** Python, TS, Go, Ruby, Java; **no Dart**
- **Transport:** REST (`https://app.daytona.io/api/sandbox`)
- **Persistence:** **Persistent FS by default**; 15-min auto-stop default,
  7–30d auto-archive to cold storage
- **Session limits:** No per-session TTL; default org cap 4 vCPU / 8 GB RAM
  / 10 GB disk (contact sales to raise)
- **Browser:** No managed CDP; Computer Use (mouse/keyboard/screenshot) +
  VNC (Linux only GA). DIY Chrome via Preview URLs.
- **GPU:** 8/12/16/32-core variants listed; thin docs vs Modal/Beam
- **Pricing:** ~$0.083/hr (1 vCPU + 2 GB); pay-as-you-go per-second
- **Popularity:** **72.4k GH stars** (largest of the six),
  `@langchain/daytona` official package, MCP server, built-in provider in
  OpenAI Agents SDK; customers Writer, SambaNova, Turing; **$24M Series A
  Feb 2026** (FirstMark)
- **Dart implementation cost:** **Low** — clean REST, straightforward HTTP
  client.

#### Modal (modal.com)

- **Isolation:** gVisor (not Firecracker); 20–50% I/O overhead
- **SDK:** Python first-class; JS/TS and Go in **beta**; **no Dart**
- **Transport:** **gRPC only**; no public REST
- **Persistence:** `modal.Volume` (sync on terminate or explicit commit);
  filesystem/directory snapshots beta; memory snapshots alpha (7d TTL, no
  GPU, terminates source sandbox)
- **Session limits:** Default 5 min, max 24h; scales to 50k+ concurrent
- **Cold start:** Marketed sub-second; benchmarked 2–5s under load
- **Browser:** No CDP primitive; port tunneling via `w.modal.host`
- **GPU:** Strongest offering — T4/L4/A10/L40S/A100-40/A100-80/H100/H200/B200
  with per-second pricing
- **Pricing:** Sandboxes priced ~3× Modal Functions; ~$0.119/hr normalized
  (Superagent 2026 benchmark)
- **Popularity:** SDK 463 stars, customers Lovable, Scale AI, Ramp; in
  OpenAI Agents SDK
- **Dart implementation cost:** **Very high** — undocumented protobuf
  schema, no public REST, non-Python SDKs beta. Realistic paths: (a) shell
  out to `modal` CLI, (b) Python/Node sidecar. **Skip for V1.**

#### Fly.io Sprites (sprites.dev)

Note: the brainstorm's original "sprite.dev" was a typo — the actual
product is **sprites.dev** from Fly.io, launched January 2026.

- **Isolation:** Firecracker microVMs, persistent, hardware-isolated
- **SDK:** JS/TS, Go, Python, Elixir official; unofficial Rust; VS Code
  extension; `sprite` CLI; **no Dart**
- **Transport:** REST + per-sprite HTTP URLs with Bearer auth
- **Persistence:** **Always persistent**, 100GB NVMe per sprite; auto-sleep
  after 30s idle, auto-wake on inbound request (~1–2s)
- **Session limits:** No TTL; destroy only via explicit API call
- **Browser:** No built-in; expose port `*:8080` to bind a custom service
- **GPU:** **None** (Sprites are CPU-only; use Fly Machines for GPU)
- **Pricing:** $0.07/CPU-hr, $0.04375/GB RAM-hr; only billed while awake;
  ~$0.46 for a 4-hour session
- **Popularity:** Brand new (Jan 2026); strong HN/X/Simon Willison
  coverage; Claude/Gemini/Codex CLIs pre-installed; no enterprise customer
  logos yet
- **Dart implementation cost:** **Low** — clean REST + Bearer. Caveat:
  no first-class filesystem read/write API; all FS ops must pipe through
  `exec` + `cat`/`tar`. Functional but slower for many small reads.

#### Bunnyshell / hopx (bunnyshell.com/sandboxes, hopx.ai)

Dual branding: the enterprise-oriented Bunnyshell page markets the same
product that lives at hopx.ai. Docs at `bunnyshell.mintlify.app`.

- **Isolation:** Firecracker, ~100ms cold start
- **SDK:** TS, Python, Go, .NET, Java; CLI; MCP server (`hopx-mcp`);
  **no Dart**
- **Transport:** REST
- **Persistence:** Snapshot + fork/clone native, ~100ms; pause/resume
- **Session limits:** No TTL ("hours/days/weeks")
- **Browser:** **Built-in** — VNC + noVNC + XFCE + Chrome + Firefox +
  VS Code preloaded
- **GPU:** Not listed
- **Pricing:** $0.007/min/environment on Startup tier; sleeping = $0;
  free tier + $250 credit
- **Popularity:** Small (GH org ~25 repos, mostly <20 stars); dual
  Bunnyshell/hopx branding confuses the product story; dedicated Claude
  Code Skill shipped
- **Dart implementation cost:** **Low**

#### Northflank (northflank.com/product/sandboxes)

- **Isolation:** Kata + Cloud Hypervisor + Firecracker + gVisor (strongest
  lineup in the category); SOC 2 Type 2
- **SDK:** Node/TS client; CLI; **no Dart**
- **Transport:** REST with streaming Node streams for exec
- **Persistence:** Persistent volumes 4GB–64TB; no documented snapshot
  primitive
- **Session limits:** None ("seconds to weeks"); scales to 10k+
- **Browser:** BYO via port exposure
- **GPU:** L4 / A100 / H100 ($2.74/hr) / H200
- **Pricing:** $0.01667/vCPU-hr, $0.00833/GB-hr; egress $0.15/GB; free
  Developer Sandbox tier
- **Popularity:** Production since 2021; customers Sentry, Writer,
  Weights, Chai Discovery, cto.new; BYOC to AWS/GCP/Azure/Oracle/Civo/
  CoreWeave/bare-metal
- **Dart implementation cost:** **Low–Medium** — REST, but the sandbox-as-
  service model carries more config ceremony than E2B/Sprites/hopx.

### Providers not evaluated (flagged for next pass)

- **Runloop** — purpose-built for coding agents; in OpenAI Agents SDK
  built-in list. **Most notable omission** from the original shortlist.
- **CodeSandbox SDK (Together AI)** — microVM with sub-2s fork/snapshot;
  browser-era incumbent repositioning for agents.
- **Blaxel** — 25ms resumes; in OpenAI Agents SDK built-in list.
- **Cloudflare Sandbox SDK** — V8 isolates; 30–45min session cap.
- **Vercel Sandbox** — Firecracker; 45min cap; in OpenAI Agents SDK.

---

## VibeKit alignment

VibeKit (`docs.vibekit.sh`) ships a production TypeScript SDK that already
solves much of the abstraction Glue needs. We're not adopting VibeKit as a
dependency — they're TS, we're Dart, and their provider list only partially
overlaps ours — but their shape validates our direction and gives us a free
head-start on API ergonomics.

### Patterns we're stealing wholesale

1. **`executeCommand` as the single universal primitive.** VibeKit resists
   adding `readFile`/`writeFile`/`uploadDir` to the executor; everything
   routes through shell (`cat`, `tee`, `tar`). Glue's `CommandExecutor`
   already has this shape — keep it.
2. **Git as the workspace-sync protocol.** VibeKit's
   `.withGithub({ token, repository })` + `branch` parameter pushes git as
   the transport. This is Option A in our sync matrix and the foundation of
   Option D (the chosen model).
3. **Ephemeral-by-default, persistent-opt-in.** Only Northflank opts into
   persistence in VibeKit. Daytona, Sprites, E2B treat persistence as an
   explicit capability. Matches Option D's persistence-capability flag.
4. **Session ≡ warm sandbox handle.** VibeKit's `.withSession(id)` /
   `setSession(id)` reattaches to an existing sandbox; `sandboxId` flows
   out of every call. For Glue: `CaptureResult` should carry `runtimeId` +
   `sessionId` so clients can always reattach.
5. **`getHost(port)` as the escape hatch.** When the agent spawns a dev
   server in the sandbox, users need a URL. VibeKit returns a reachable
   host for any port. Bake into the future `RuntimeSession` interface.
6. **Provider factories in separate packages.** VibeKit ships
   `@vibe-kit/daytona`, `@vibe-kit/e2b`, etc. — core stays SDK-free. Glue
   should ship `glue_e2b`, `glue_daytona`, `glue_sprites` as separate pub
   packages depending only on the boundary interface.
7. **Ask Mode = read-only capability.** VibeKit's `mode: "ask"` disables
   filesystem writes. Single flag, high leverage. Add to Glue's capability
   table (see runtime-boundary plan §"Ask Mode").
8. **Three-tier image resolution (Dagger).** Local cache → registry → build.
   Good pattern for Glue's Docker executor too.

### Patterns we're **not** copying

- **Fluent builder API** (`new VibeKit().withAgent().withSandbox()...`).
  Dart cascades give us the same ergonomics, but our existing `GlueConfig`
  → `ExecutorFactory` flow is more testable than a method chain.
- **Per-provider-specific feature surfaces** (Cloudflare `hostname`,
  Northflank `billingPlan`). Glue keeps these in provider-local config
  sections; no polymorphic `spawnSandbox()` that ignores provider
  differences.
- **`generateCode()` higher-level agent primitive.** VibeKit is
  deprecating this in favor of `executeCommand + events` — signals we
  should not build a symmetric thing.

### Gaps VibeKit leaves us to fill

- **No browser/CDP integration story.** VibeKit expects the agent to run
  its own browser tooling inside the sandbox; our browser-provider layer
  is ahead of them here (the boundary plan's Cleanup §4 extends it with
  runtime-owned endpoints via `BrowserEndpointSource`).
- **No declarative resource limits.** CPU/memory caps are per-provider
  (`billingPlan` etc.). Glue should document this limitation, not
  abstract it.
- **CLI and SDK have divergent sandbox configs in VibeKit.** We should
  unify from day one — one config shape, whether invoked from
  `~/.glue/config.yaml`, env vars, or a programmatic API.

---

## Workspace sync — Option D chosen (other options kept for context)

### Today's baseline

- **HostExecutor:** cwd is the workspace; no sync needed.
- **DockerExecutor:** cwd mounted at `/workspace`; real-time shared FS.
- Tools (read/write/edit/shell) operate live, not on batched diffs.
- Sessions logged to JSONL for replay (planned, not on a tracker).

Remote runtimes break the shared-FS assumption. Bootstrap and in-session
operations are **separate** questions.

### Option A — Git-first bootstrap + remote-native ops

- Bootstrap: push HEAD (with uncommitted changes committed to a scratch
  ref like `refs/glue/session-<id>` on origin or a scratch remote). The
  sandbox clones that ref. Fall back to tarball upload if cwd is not a
  git repo.
- Ops: every tool call hits the runtime's exec/filesystem API in real
  time.
- End-of-session: `git diff <bootstrap-sha>`; surface as patch.

**Pros:** uniform default, replayable from a SHA, aligns with JSONL
replayability.
**Cons:** requires git + pushable remote for the primary path; every
session round-trips through git.

### Option B — Tarball bootstrap + remote-native ops

- Bootstrap: `tar czf` the workspace respecting `.gitignore`, upload via
  the provider's FS API, extract remotely.
- Ops: same remote-native model as A.
- End-of-session: download changed files.

**Pros:** no git dependency; captures uncommitted state natively.
**Cons:** each adapter must implement upload/download; reinvents change
tracking poorly; diffs opaque without git.

### Option C — Per-provider native

Each adapter uses its provider's best primitive — Daytona snapshot, E2B
pause/resume, Sprites persistent FS, Modal Volume.

**Pros:** most honest to each provider's primitives.
**Cons:** biggest abstraction surface; per-adapter config balloons; hard
to port sessions across providers.

### Option D — A + per-provider persistence opt-in (chosen 2026-04-19)

**Status: decided.** Default = A (git-first + tarball fallback). Providers
whose killer feature is persistence (Daytona, Sprites, E2B pause/resume)
declare a `persistent` capability. On session resume, Glue wakes the
existing sandbox instead of re-bootstrapping.

**Pros:** uniform debuggable default; escape hatch where persistence
materially beats re-bootstrap. Matches VibeKit's own design
(`.withGithub({ token, repository })` + `branch` parameter — see
"VibeKit alignment" below).
**Cons:** two code paths per adapter; users must understand which
mechanism is active.

### Per-provider mechanics under Option D

#### Bootstrap (once per new session):

| Step      | E2B                           | Daytona                    | Modal                        | Sprites                      | hopx                         | Northflank                 |
| --------- | ----------------------------- | -------------------------- | ---------------------------- | ---------------------------- | ---------------------------- | -------------------------- |
| Create    | `Sandbox.create(template)`    | `sandbox.create(snapshot)` | `Sandbox.create(image, app)` | `sprite create <name>`       | `sandbox.create()`           | `POST /services/sandboxes` |
| Git clone | `commands.run("git clone …")` | `fs.git.clone(…)` native   | `sb.exec("git","clone",…)`   | `sprite exec -- git clone …` | `sandbox.run("git clone …")` | `POST /exec`               |

Glue picks `/workspace` as the universal path convention.

#### In-session operations:

| Op         | E2B                                        | Daytona                 | Modal                     | Sprites              | hopx               | Northflank          |
| ---------- | ------------------------------------------ | ----------------------- | ------------------------- | -------------------- | ------------------ | ------------------- |
| Read       | `files.read(p)`                            | `fs.read_file(p)`       | `sb.open(p).read()`       | `exec -- cat p`      | `fs.read_file(p)`  | transfer-file API   |
| Write      | `files.write(p, bytes)`                    | `fs.upload_file(…)`     | `sb.open(p,'w').write(…)` | piped stdin via exec | `fs.write_file(…)` | transfer-file API   |
| Run        | `commands.run(cmd, on_stdout)`             | `process.exec(cmd)` PTY | `sb.exec(cmd)` streams    | `exec -- cmd`        | `sandbox.run(cmd)` | `POST /exec` stream |
| Background | `run(…, background=True)` + `connect(pid)` | PTY session             | detached exec             | service mgr          | async mode         | long-lived exec     |

**Outlier:** Sprites has no first-class FS API; reads/writes must pipe
through `exec` + `cat`/`tar`. Workable but slower for many small ops.

#### Persistence opt-in:

| Provider   | Primitive                                    | Resume cost  | Gotcha                                   |
| ---------- | -------------------------------------------- | ------------ | ---------------------------------------- |
| E2B        | `pause()`/`resume(id)`                       | ~1s          | 14d retention; multi-resume FS bug #884  |
| Daytona    | Persistent FS by default; 7–30d auto-archive | 0s when warm | 15-min auto-stop inflates idle cost      |
| Sprites    | Always persistent; 30s auto-sleep            | 1–2s wake    | Indefinite retention until destroy       |
| hopx       | Snapshot fork/clone                          | ~100ms       | Small ecosystem                          |
| Modal      | `modal.Volume` at `/workspace`               | seconds      | Memory snapshots alpha, GPU-incompatible |
| Northflank | Persistent volumes                           | seconds      | Service-oriented ceremony                |

Glue stores `sessionId → sandboxId` mapping. On session resume, if the
adapter declares the `persistent` capability, skip bootstrap and wake.

#### End-of-session diff-out (universal):

```
git -C /workspace diff <bootstrap-sha> > /tmp/session.patch
```

Read `/tmp/session.patch` via the provider's FS API (or `cat` on Sprites).
Glue applies the patch locally or surfaces it as a session summary.

---

## Dart implementation cost

| Provider   | Transport                    | Dart effort                            |
| ---------- | ---------------------------- | -------------------------------------- |
| E2B        | REST (control) + gRPC (envd) | **High** — gRPC client or Node sidecar |
| Daytona    | REST                         | **Low**                                |
| Sprites    | REST                         | **Low** (FS via exec-only)             |
| hopx       | REST                         | **Low**                                |
| Northflank | REST                         | **Low–Medium** (service ceremony)      |
| Modal      | gRPC only                    | **Very high** — skip V1                |

## Candidate top-3 (not yet confirmed)

Blended popularity + capability + Dart-fit:

1. **Daytona** — 72.4k stars, clean REST, native git SDK ops, persistent
   by default, OpenAI SDK built-in. Lowest implementation cost; highest
   leverage.
2. **E2B** — biggest agent ecosystem. Higher Dart cost (gRPC envd) but
   mindshare is non-negotiable.
3. **Fly.io Sprites** — complements E2B (ephemeral) and Daytona
   (workspace-oriented) with a third mode (persistent-always, auto-sleep).
   Fresh tech; low Dart cost.

### Alternative pivots

- **If GPU is a must-have:** drop Sprites, add Modal despite the Dart
  cost. (Recommendation against: a `modal` CLI sidecar can cover the rare
  GPU case without building a full adapter.)
- **If enterprise/BYOC is a must-have:** drop Sprites, add Northflank.
- **If the design needs to prove the abstraction generalizes:** drop
  Sprites, add hopx (distinct primitive: fork/clone from snapshot).

---

## Terminology (proposed, to be validated)

Working glossary. Align with the vocabulary in
`docs/plans/2026-04-19-runtime-boundary-plan.md` where it exists.

| Term                  | Meaning                                                                                                                                                                                            |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Runtime**           | The place where work executes: host, Docker, or a remote cloud provider.                                                                                                                           |
| **Adapter**           | A Dart class implementing the Runtime contract for one provider (e.g. `E2BAdapter`, `DaytonaAdapter`).                                                                                             |
| **Session**           | A Glue session maps 1:1 to one sandbox instance (`sessionId → sandboxId`).                                                                                                                         |
| **Sandbox**           | An individual, isolated unit of compute created by a runtime.                                                                                                                                      |
| **Bootstrap**         | Getting workspace state into a fresh sandbox (git-clone or tarball).                                                                                                                               |
| **Workspace path**    | Universal `/workspace` convention across providers.                                                                                                                                                |
| **Persistent resume** | Skipping bootstrap because an existing sandbox already holds our state.                                                                                                                            |
| **Capability**        | A declarative feature flag per adapter: `command_streaming`, `background_jobs`, `browser_cdp`, `gpu`, `persistent`, `snapshots`, etc. Matches the existing `runtime-capabilities.yaml` vocabulary. |

---

## Testing approach (sketch)

- **Unit:** mock each adapter's HTTP/gRPC transport; verify URL, method,
  headers, payload for bootstrap, exec, read, write, diff-out.
- **Integration (opt-in):** real provider credentials via env; tagged
  `@Tags(['cloud-e2b'])`, `@Tags(['cloud-daytona'])`, etc.; skipped by
  default like today's e2e suite.
- **Capability tests:** for each adapter, assert declared capabilities
  match actual behavior (e.g. `persistent: true` means resume-after-pause
  preserves a known file).
- **Golden session test:** run the same deterministic command list on
  host + Docker + each cloud adapter; diff transcripts. Tolerate timing
  differences.
- **Cost guard:** CI tests pin tiny sandboxes (1 vCPU, 512 MiB, 60s TTL)
  and include teardown; any leaked sandbox fails the build.

---

## Open questions (all deferred)

### Resolved since original draft

- **Workspace sync A/B/C/D final pick.** ✅ Decided 2026-04-19: **Option D**
  (git-first bootstrap + per-provider persistence opt-in). Validated by
  VibeKit's identical approach.
- **Universal workspace path.** ✅ Decided 2026-04-19: **`/workspace`**
  across all runtimes. Docker migration landed same day.

### Still open

1. **Browser endpoint ownership.** Today `BrowserEndpointProvider` is
   separate from executors. Cloud runtimes that bundle browsers (E2B
   `browser` template, hopx Chrome, Daytona Computer Use) — do they
   become browser providers too, or stay purely command executors?
   The runtime-boundary plan's Cleanup §4 sketches a `BrowserEndpointSource`
   abstraction that would accommodate both.
2. **Per-session vs global runtime selection.** Is the runtime picked
   once in config, or selectable per session / per tool call?
3. **Credentials beyond V1.** Integration with the existing
   `CredentialStore` (`cli/lib/src/credentials/credential_store.dart`)
   deferred.
4. **Non-git workspace handling.** Tarball fallback mechanics —
   compression, `.gitignore` semantics, size caps.
5. **Outbound network egress policy.** Allowlist, block-all, or inherit
   provider defaults per runtime.
6. **Artifact retention.** Where artifacts land locally when
   `collectArtifacts()` is called, and for how long.
7. **Cancel semantics.** Behavior for in-flight commands on session
   cancel; provider-specific cleanup races.

---

## When to pick this up

Triggers for revisiting:

- The boundary-prep cleanups in `2026-04-19-runtime-boundary-plan.md` land
  (`RunningCommandHandle`, `WorkspaceMapping`, JSONL runtime events,
  `BrowserEndpointSource`) — adapter work becomes much cheaper.
- A real workload demands it (GPU, untrusted code, parallel long-running
  agents).
- Daytona or E2B ships a Dart SDK — collapses the biggest cost driver.

### Next steps on resume

1. Refresh the 6-provider landscape — this space moves fast (Sprites
   launched Jan 2026; Daytona's Series A is Feb 2026; OpenAI's SDK
   sandbox list landed Apr 2026).
2. Confirm or revise the top-3.
3. Resolve the 7 remaining open questions above (workspace sync and
   universal path are already decided).
4. Draft the `ExecutionRuntime` interface, informed by actual adapter
   needs rather than speculation. Wire it through `cli/lib/src/boot/wire.dart`
   alongside the existing `ExecutorFactory` — no service locator.
5. Kick off the `writing-plans` skill using this document as input.

---

## Sources

Provider research:

- E2B: <https://e2b.dev/docs>, <https://github.com/e2b-dev/E2B>,
  <https://e2b.dev/pricing>, <https://e2b.dev/docs/sandbox/persistence>
- Daytona: <https://www.daytona.io/docs/en/>,
  <https://github.com/daytonaio/daytona>, <https://www.daytona.io/pricing>
- Modal: <https://modal.com/docs>,
  <https://github.com/modal-labs/modal-client>,
  <https://modal.com/docs/guide/sandbox>, <https://modal.com/pricing>
- Fly.io Sprites: <https://sprites.dev>, <https://docs.sprites.dev>,
  <https://fly.io/blog/design-and-implementation/>,
  <https://github.com/superfly/sprites-py>
- hopx/Bunnyshell: <https://hopx.ai>,
  <https://www.bunnyshell.com/sandboxes/>,
  <https://bunnyshell.mintlify.app>
- Northflank: <https://northflank.com/product/sandboxes>,
  <https://northflank.com/docs/v1/api>,
  <https://northflank.com/pricing>

Landscape context:

- Superagent 2026 sandbox benchmark:
  <https://www.superagent.sh/blog/ai-code-sandbox-benchmark-2026>
- OpenAI Agents SDK sandbox update (Apr 16, 2026):
  <https://www.helpnetsecurity.com/2026/04/16/openai-agents-sdk-harness-and-sandbox-update/>
- Daytona $24M Series A (Feb 2026):
  <https://www.prnewswire.com/news-releases/daytona-raises-24m-series-a-to-give-every-agent-a-computer-302680740.html>
- Fly.io Sprites launch coverage (Simon Willison, Jan 2026):
  <https://simonwillison.net/2026/Jan/9/sprites-dev/>
- Northflank sandbox comparisons:
  <https://northflank.com/blog/best-sandbox-runners>,
  <https://northflank.com/blog/daytona-vs-e2b-ai-code-execution-sandboxes>,
  <https://northflank.com/blog/e2b-vs-modal>
- Koyeb top sandbox platforms:
  <https://www.koyeb.com/blog/top-sandbox-code-execution-platforms-for-ai-code-execution-2026>
