# Clean Architecture Layout

agent-tui's full Clean Architecture realization — the workspace layout,
the dependency rules, what each layer owns, and how the rules are
enforced. Companion to `agent-first-architecture.md`, which covers the
underlying principles. This file is the concrete artefact.

The interesting question for Glue isn't "should we mirror this" — Glue
is one Dart binary, not a Rust workspace — but rather "what's the right
shape of the same idea at Glue's scale?" That's discussed at the end.

## The eight crates

```text
cli/
├── Cargo.toml                 # workspace root; shared dep versions
└── crates/
    ├── agent-tui-common/      # shared primitives
    ├── agent-tui-domain/      # types + invariants
    ├── agent-tui-usecases/    # business logic + trait ports
    ├── agent-tui-adapters/    # CLI/RPC interface translation
    ├── agent-tui-infra/       # PTY, daemon, IPC implementations
    ├── agent-tui-app/         # composition root
    ├── agent-tui/             # facade — main.rs / bin/* only
    └── xtask/                 # tooling (architecture check, release)
```

The split exists so that the Cargo dependency rules below can be
enforced by the compiler. There is no other reason. A single 30k-LOC
crate would behave identically at runtime.

## The dependency matrix

This is the canonical rule, written into both `ARCHITECTURE.md` and a
test fixture (`cli/crates/agent-tui/tests/architecture.rs`):

| Crate                | May depend on                                        |
| -------------------- | ---------------------------------------------------- |
| `agent-tui-common`   | _(nothing internal)_                                 |
| `agent-tui-domain`   | `common`                                             |
| `agent-tui-usecases` | `domain`, `common`                                   |
| `agent-tui-adapters` | `usecases`, `domain`, `common`                       |
| `agent-tui-infra`    | `usecases`, `domain`, `common`                       |
| `agent-tui-app`      | `adapters`, `infra`, `usecases`, `domain`, `common`  |
| `agent-tui` (facade) | `app` (plus external crates for binary entry points) |

Reading the table: `usecases` cannot import from `infra` (that would be
an inward arrow turning into an outward one). `adapters` and `infra`
sit at the same layer and don't depend on each other — they each
depend on the usecase ports independently. The `app` crate is the only
place all five mid-tier crates meet.

Visualised as the standard Clean Architecture rings:

```text
                ┌────────────────────────────┐
                │  agent-tui  (facade)       │
                │  main.rs + bin/*           │
                └─────────────┬──────────────┘
                              │
                ┌─────────────▼──────────────┐
                │  agent-tui-app             │
                │  composition root          │
                └──┬──────────────────────┬──┘
                   │                      │
       ┌───────────▼────────┐  ┌──────────▼──────────┐
       │  agent-tui-adapters│  │  agent-tui-infra    │
       │  CLI / RPC / DTO   │  │  PTY / daemon / IPC │
       └───────────┬────────┘  └──────────┬──────────┘
                   │                      │
                   └──────────┬───────────┘
                              │
                ┌─────────────▼──────────────┐
                │  agent-tui-usecases        │
                │  orchestration + ports     │
                └─────────────┬──────────────┘
                              │
       ┌──────────────────────┴──────────────────────┐
       │                                             │
┌──────▼────────────┐                       ┌────────▼─────────┐
│  agent-tui-domain │                       │  agent-tui-common │
│  types + rules    │                       │  primitives       │
└───────────────────┘                       └──────────────────┘
```

## What each layer owns

### `common` — shared foundation

Truly cross-cutting primitives that everyone needs:

- `DaemonError`, `ErrorCategory` — the umbrella error type with a
  category for programmatic dispatch.
- `mutex_lock_or_recover`, `rwlock_read_or_recover` — poisoned-lock
  recovery helpers used across the codebase.
- Telemetry helpers around `tracing`.
- Color and ANSI escape constants.

No internal dependencies. If something belongs in `common` but only
one other crate uses it, it doesn't belong in `common`.

### `domain` — types and invariants

The shapes of the world. No I/O, no side effects:

- `SessionId` — newtype over `String`, validated non-empty.
- `TerminalSize` — `(cols, rows)` with bounds checking via `try_new`.
  Constants `MIN_COLS=10`, `MAX_COLS=500`, `MIN_ROWS=2`,
  `MAX_ROWS=200`.
- `WaitConditionType` — closed enum (`Text | Stable | TextGone`) with
  string parsing.
- `SessionInfo` — read-only view of a session (id, command, pid,
  running, created_at, size).
- Request/response DTOs: `SnapshotInput/Output`, `WaitInput/Output`,
  `KeystrokeInput/Output`, etc. — one struct per use case.
- Core screen types: `ScreenSnapshot`, `ScreenCell`, `CellStyle`,
  `Color`, `CursorPosition`.

The validation pattern is consistent: `try_new` returns `Result<Self,
Error>`, `new_unchecked` is reserved for trusted callers that already
hold the invariant. `SessionId` parses from `&str` and `String` via
`TryFrom`.

### `usecases` — orchestration + ports

One file per business operation. Each has a trait + an `Impl` struct:

- `SnapshotUseCase` / `SnapshotUseCaseImpl`
- `KeystrokeUseCase`, `TypeUseCase`, `KeydownUseCase`, `KeyupUseCase`
- `WaitUseCase` (uses `Clock`, `SessionRepository`)
- `ShutdownUseCase`
- `DiagnosticsUseCase`

Plus the **port traits** — the boundary `infra` and `adapters` plug
into:

| Port                | Owns                                                                     |
| ------------------- | ------------------------------------------------------------------------ |
| `SessionRepository` | spawn / get / list / kill / restart sessions, set active                 |
| `SessionOps`        | per-session ops: read screen, send input, resize, stream subscribe       |
| `Clock`             | `now()`, `elapsed()`, `elapsed_ms()` — for wait timers                   |
| `ShutdownNotifier`  | signal daemon shutdown to the use cases                                  |
| `TerminalEngine`    | VT emulation behind a trait — `process_bytes`, `snapshot`, `plain_text`  |
| `StreamWaiter`      | "block until new bytes or timeout" handle returned by `stream_subscribe` |

The use cases write against these traits. They never import a concrete
PTY type, daemon struct, or IPC client. The whole point of the layer
is that you can construct mock implementations and exercise every code
path without spawning a single process.

### `adapters` — interface translation

The "how the outside world's shape becomes domain shape" layer:

- CLI command handlers (clap-derived structs → `*Input` DTOs).
- JSON-RPC presenters (DTOs → `serde_json::Value`).
- Request/response envelope handling.
- The router that maps incoming RPC method names to use-case calls.

Adapters know about both DTOs and external formats but **not** about
PTYs or sockets. They depend on `usecases` (to call) but not on
`infra`.

### `infra` — implementations

Where the use-case ports become real:

- `PtyHandle` — `portable-pty` wrapper, the read thread, the
  process-group kill ladder.
- `VirtualTerminal` — `tattoy-wezterm-term` wrapper implementing
  `TerminalEngine`.
- `Session`, `SessionManager` — concrete `SessionRepository` and
  `SessionOps`.
- IPC: `UnixSocketTransport`, `WsSocketTransport`, the auto-start
  logic, polling primitives.
- The session metadata persistence layer (`sessions.jsonl` reader/writer).

Infra knows how to do the real thing. It depends on the use-case
_traits_ but is never depended on by the use cases themselves — that
arrow only goes inward.

### `app` — composition root

Where everything meets. Wires up:

- Construct the `SessionManager` (concrete `SessionRepository`).
- Construct the `SystemClock` (concrete `Clock`).
- Construct each use case impl with its dependencies.
- Build the daemon HTTP/WS server, mount the RPC router.
- Build the CLI `Command` enum and dispatch.

The `app/lib.rs` re-exports every other crate's modules under a
namespace (`pub mod common { pub use agent_tui_common::common::*; }`,
etc.), so `app`-level code can refer to everything from one place
without 7 explicit `use` statements per file. This is a deliberate
ergonomics choice for the only crate where reaching across all layers
is correct.

### `agent-tui` (facade) — entry points only

Just `main.rs`, `lib.rs`, and `bin/*.rs`. No production logic. The
architecture test in `tests/architecture.rs` actively asserts that the
old layout (`crates/agent-tui/src/{common,domain,usecases,…}`) has
been deleted, to prevent regression to the pre-split structure.

### `xtask` — tooling

Separate from production code entirely. Owns:

- `xtask architecture check` — validates the dependency matrix from
  `cargo metadata` JSON.
- `xtask version`, `xtask release` — release engineering.
- `xtask ci` — runs the full CI gate locally.
- `xtask tui-explorer` — the discovery agent for the tui-explorer skill.

External-deps-only. Cannot be confused with production code because
the binary is never shipped.

## How enforcement works

There are three independent enforcement layers. Each catches different
violations:

### 1. Cargo crate boundaries (compile time)

If `usecases/Cargo.toml` doesn't list `agent-tui-infra` as a
dependency, `use agent_tui_infra::...` doesn't compile. This is the
strongest check — no human in the loop. An agent that puts code in
the wrong layer gets a build error within seconds.

### 2. Architecture test (test time)

`cli/crates/agent-tui/tests/architecture.rs` runs `cargo metadata
--format-version 1`, parses the resolved dependency graph, and asserts
the matrix above:

```rust
let allowed: HashMap<&str, HashSet<&str>> = HashMap::from([
    ("agent-tui-common", HashSet::from([])),
    ("agent-tui-domain", HashSet::from(["agent-tui-common"])),
    ("agent-tui-usecases",
        HashSet::from(["agent-tui-domain", "agent-tui-common"])),
    // ...
]);

for node in resolve_nodes {
    for dep in deps {
        assert!(
            allowed_targets.contains(target),
            "forbidden internal dependency: {source} -> {target}"
        );
    }
}
```

This catches dependencies that were added to a `Cargo.toml` but
shouldn't have been. The Cargo build doesn't object to _adding_ a
dependency that was previously absent — the test does.

It also asserts that **the legacy single-crate layout is gone**: the
test fails if `crates/agent-tui/src/{common,domain,usecases,...}`
exists. This is the "no half-migrated state" guard — once the split
is done, undoing it requires deleting the test, not just moving
files.

### 3. Clippy denials (lint time)

The workspace `clippy.toml` denies:

- `std::thread::sleep` — would block shutdown signals; use
  `park_timeout` or channel `recv_timeout`.
- `tokio::sync::mpsc::unbounded_channel` and
  `crossbeam_channel::unbounded` — silent unbounded memory growth on
  slow consumers.
- `std::sync::mpsc::channel` — superseded by `crossbeam_channel`.
- `std::process::exit` outside `main.rs` — forces exit through proper
  shutdown.

`cargo clippy --workspace --all-targets --all-features -- -D warnings`
is part of the CI gate.

### 4. xtask architecture check (CI gate)

`cargo run -p xtask -- architecture check --verbose` does the same
analysis as the test but in a form usable from CI scripts (writes a
`dependencies.json` artefact for inspection, fails non-zero on
violations). The artefact (committed at
`cli/docs/architecture/dependencies.json`) acts as a snapshot — diffs
against it surface architectural changes during code review.

The full CI gate is then:

```text
1. cargo fmt --all -- --check
2. cargo clippy --workspace --all-targets --all-features -- -D warnings
3. cargo run -p xtask -- architecture check --verbose
4. cargo test --workspace
```

## The Sessions example, end to end

To make the layering concrete, here's how `agent-tui screenshot`
flows through the layers:

```text
1. user runs:  agent-tui screenshot --json
                        │
                        ▼
2. facade `main()` parses argv via clap
                        │
                        ▼
3. app dispatches to ScreenshotHandler in adapters
                        │
                        ▼
4. adapter builds SnapshotInput (domain DTO) from CLI args
                        │
                        ▼
5. adapter calls SnapshotUseCase::execute(input)
   (use case lives in usecases, takes a &dyn SessionRepository)
                        │
                        ▼
6. use case calls repo.resolve(session_id) -> SessionHandle
   then handle.update() and handle.screen_text()
                        │
                        ▼
7. The repo is SessionManager (in infra), the handle wraps a
   concrete Session, which holds a VirtualTerminal, which is fed
   from a PtyHandle reader thread.
                        │
                        ▼
8. SnapshotOutput (domain DTO) flows back to the adapter, which
   formats JSON via the presenter and prints.
```

At every step the caller depends only on traits and DTOs from inner
layers. Replacing the PTY with a mock (for tests) means
constructing a different `SessionRepository`. Nothing else changes.

## What this would look like in Glue

Glue is one Dart binary, ~few-thousand-LOC, and the cost of multiple
`pubspec.yaml` files is real. The rules below are the same in spirit
without the workspace machinery:

- **Use `lib/src/<layer>/` directories**, not packages. `lib/src/domain`,
  `lib/src/usecases`, `lib/src/infra`, `lib/src/adapters`,
  `lib/src/app`. Today Glue mostly has this shape implicitly; making
  it explicit (and naming directories after the layers, not the
  features) is the change.
- **Define ports in `lib/src/usecases/ports/`** as abstract Dart
  classes. Concrete implementations live in `lib/src/infra/`. Use
  cases construct against ports, never against concrete types.
- **Enforce import rules with `import_lint`** (or a custom
  `analysis_options.yaml` rule). The Dart equivalent of the cargo
  matrix is "files in `lib/src/usecases` cannot import
  `lib/src/infra`."
- **Keep one composition file** (`lib/src/app/wire.dart` or similar)
  where everything is constructed. That's the only place that knows
  about every layer.
- **Add a CI test** that walks `lib/src/` and asserts the import rules,
  same as agent-tui's `architecture.rs`. ~50 lines of Dart.
- **Don't bother with multiple packages.** The compiler-enforces-it
  benefit is real for Rust because crates are the natural Cargo unit.
  In Dart, lints + a test give 90% of the value at 10% of the cost.
- **The Clippy denials list is portable.** The Dart equivalents:
  - Avoid `Future.delayed` for synchronization (use `Completer`).
  - Avoid `StreamController` without backpressure on hot streams.
  - Reserve `exit()` for `bin/main.dart`.

The core takeaway: agent-tui's Clean Architecture isn't valuable
because it has eight crates. It's valuable because the dependency rule
is **mechanically checked**, not stylistically encouraged. Replicate
the _checking_; the eight-crate shape is incidental.

## Where this lives in agent-tui

| Concern                          | File                                                      |
| -------------------------------- | --------------------------------------------------------- |
| Top-level architecture statement | `ARCHITECTURE.md` (root)                                  |
| Target-state manifesto           | `cli/docs/architecture/clean_arch_target.md`              |
| Frozen dependency snapshot       | `cli/docs/architecture/dependencies.json`                 |
| Architecture test fixture        | `cli/crates/agent-tui/tests/architecture.rs`              |
| xtask validator                  | `cli/crates/xtask/src/main.rs` — `Commands::Architecture` |
| Workspace + pinned external deps | `cli/Cargo.toml`                                          |
| Shared lint policy               | `cli/clippy.toml`                                         |
| Port definitions                 | `cli/crates/agent-tui-usecases/src/usecases/ports/`       |
