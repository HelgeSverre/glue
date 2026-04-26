# Agent-First Architecture Notes

agent-tui is built on a stated set of "core beliefs" about working with
LLM agents as primary contributors. The full text is in the upstream
`docs/design-docs/core-beliefs.md`. The principles worth thinking
through for Glue are below.

These are not prescriptions for Glue. Some apply directly, some are
Rust-only, some are over-engineered for Glue's current scale. The point
is to surface the choices and let Glue make its own call.

## 1. The compiler is the first reviewer

Boundaries that can be enforced at compile time should be — not by
convention, not by code review. agent-tui uses Cargo crate boundaries
to enforce its Clean Architecture rings:

```
common ← domain ← usecases ← adapters/infra ← app ← facade
```

If `usecases` tries to `use crate::infra::pty`, the build fails.
There's no human in the loop. An agent that puts code in the wrong
layer gets immediate feedback from `cargo build`.

**Dart equivalent.** Dart doesn't have crate-level visibility, but
`pub` packages plus strict `import` lints (`avoid_relative_imports`,
custom `import_lint` rules) get most of the way. The cost is multiple
`pubspec.yaml` files per concern, which is not Glue's current shape.

**Glue applicability.** Probably overkill at current size. The
_principle_ — make architectural drift fail loudly — is worth keeping.
The _mechanism_ (split into seven packages) is not.

## 2. Prefer boring, agent-legible technology

Pick libraries with stable APIs and large training-data presence over
the latest cutting-edge alternative. Agents pattern-match against what
they've seen many times before; obscure libraries cause subtle errors.

agent-tui's choices: `clap` for CLI, `axum` for HTTP, `thiserror` /
`anyhow` for errors, `tracing` for observability, `serde` for
serialization. None of these are exciting; all of them are unambiguous
to an LLM.

**Glue applicability.** Already aligned. Dart's std lib + `package:args`

- `package:logging` are the boring, well-documented stack. Don't
  introduce niche packages without a reason agents can read off the code.

## 3. Forward-only dependencies

The dependency graph flows in one direction. Cross-cutting concerns
(logging, errors) enter through explicit interfaces, not ambient
imports. An agent working in the inner layers never has to understand
the outer-layer details.

The reasoning: an agent's effective context is the _transitive closure_
of types it touches. If `usecases` imports a concrete PTY type, every
agent task that touches usecases now needs to understand PTYs.
Forward-only dependencies bound the context required for any one task.

**Glue applicability.** Fully applicable, regardless of language. The
test is: can an agent change the conversation logic without reading
the rendering code? If yes, the boundary is right.

## 4. Trait ports over concrete dependencies

Define what you need (`SessionRepository`, `Clock`, `SessionOps` —
trait ports owned by usecases) and let infra provide implementations.
Lets business logic be tested without spinning up real PTY children or
daemon processes.

agent-tui's port set is small and stable:

| Port                | Owns                                 |
| ------------------- | ------------------------------------ |
| `SessionRepository` | Spawn, get, list, kill sessions      |
| `SessionOps`        | Per-session: read screen, send input |
| `Clock`             | `now()` and `elapsed()` — for waits  |
| `ShutdownNotifier`  | Daemon shutdown signal               |
| `TerminalEngine`    | VT emulation behind a trait          |

**Dart equivalent.** Abstract classes with concrete implementations.
Glue already does this in places (`ShellRunner`, `ApiClient`); the
discipline could be extended to interactive-process orchestration.

## 5. Structured errors are agent context

Errors are not just for humans — they're context that agents read to
decide what to do next. Every error in agent-tui carries:

- A `category` for programmatic handling.
- A human-readable message with specifics (the session id, the path,
  the bytes that didn't parse).
- A source error chain, preserved through `thiserror` `#[source]`.

Generic errors like "something went wrong" or "operation failed" are
useless. Specific errors like `SessionError::SessionNotFound { id }`
let an agent self-correct (refresh session list, retry, surface to
user) without trial-and-error.

**Glue applicability.** Already partially in place. Worth auditing
Glue's error types for "what would an agent do with this?" — if the
answer is "nothing useful," the error needs more structure.

## 6. Repository-local is the only real

If knowledge isn't in the repo, it doesn't exist for an agent run that
starts cold. Architecture decisions, team conventions, domain rules —
all encoded as versioned artifacts.

agent-tui has:

- `ARCHITECTURE.md` (the ring diagram, dependency rules).
- `docs/design-docs/core-beliefs.md`.
- `docs/audits/` (longitudinal record of what was reviewed and why).
- `docs/exec-plans/` (current and completed work plans).
- `.harness/` and `skills/` directories (instructions for the agent).

**Glue applicability.** Glue's `docs/reference/` already plays this
role for runtime behavior. The companion files in this directory
extend that pattern into "things we learned from other projects" —
which is what these notes are.

## 7. Small crates, clear ownership

Each crate owns one concept at one architectural layer. agent-tui
keeps each crate around 3k LOC and splits when one crosses ~5k. The
overhead of an extra crate (a few `Cargo.toml` lines) is far lower
than the cost of an agent misunderstanding a 10k-LOC module.

**Glue applicability.** Dart's `lib/src/<topic>/` directories with
strict barrel exports get a similar effect without a package-per-layer
explosion. The 5k-LOC heuristic for "consider splitting" is portable.

## 8. Constraints enable agent speed

Strict, centrally-enforced rules (Clippy denials, crate boundaries, CI
gates) feel restrictive in human workflow but multiply for agents.
Once encoded, constraints apply everywhere at once.

agent-tui denies several `std::` items via Clippy:

- `std::thread::sleep` — forces use of channels or `park_timeout` so
  shutdown can interrupt waits.
- Unbounded channels — except where explicitly justified, to prevent
  silent memory growth.
- `std::process::exit` — forces exit through the proper shutdown path.

**Glue applicability.** Same idea via Dart's `analysis_options.yaml`
and custom lints. Worth a pass: which patterns has Glue debugged
multiple times? Encode each as a lint rule.

## What's left out of these notes

agent-tui's full belief set covers a few more topics that don't map
cleanly onto Glue:

- Workspace-level Cargo dependency hygiene (Rust-specific).
- The xtask architecture-validation runner (Rust-specific tooling).
- Per-module audit cadence (operational, not portable).

If you want them, the source is `docs/design-docs/core-beliefs.md`,
`docs/audits/`, and `cli/docs/architecture/clean_arch_target.md` in
the upstream repo.
