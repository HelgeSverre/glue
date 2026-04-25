# Go CLI Patterns (Carl Mastrangelo)

Reference notes extracted from Carl Mastrangelo's 2020 essay
**"Command-line Utilities in Go: How To and Advice"** (`https://blog.carlana.net/post/2020/go-cli-how-to-and-advice/`).
The post critiques a small Go CLI app and rewrites it idiomatically.
The patterns are Go-specific in their library choices (`flag`,
`http.Client`) but **language-agnostic in their architectural moves**,
which is why they're worth lifting into a Dart project like Glue.

The post's thesis: a CLI almost always has three layers — input,
execution, output — and the time to separate them is at the start.
Doing it right costs nothing upfront and pays dividends as the CLI
grows. The companion files break it down.

## Companion files

| File                              | What it covers                                                            |
| --------------------------------- | ------------------------------------------------------------------------- |
| `cli-three-layer-architecture.md` | The input/execute/output split, the `main → Run() int` shape, exit codes  |
| `cli-config-and-flags.md`         | The `appEnv` struct pattern: configuration as a value, no globals, no `init()` |
| `cli-execution-and-output.md`     | Generic helpers over wrapper clients; separate `printJSON` and `prettyPrint` paths |

## What's actually novel here

These are the bits worth keeping. Most are not "novel" in the
inventor sense — they're conventions that experienced CLI authors
converge on. They're novel for the kind of CLI that hasn't been
through a year of feature additions yet.

- **Three-layer mental model** — input / execute / output. Other layers
  are speculative until you have a concrete reason. YAGNI applied to
  CLI architecture.
- **Single-line `main()` that delegates.** `func main() { os.Exit(cli.Run()) }`.
  Costs nothing, makes the rest testable, gives one explicit exit
  point.
- **Exit code triad: 0 / 1 / 2.** 0 = success, 1 = runtime error, 2 =
  init/argument error. This is older than the post and almost
  universal, but most CLIs still don't follow it.
- **`appEnv` struct with `fromArgs(args []string) error`** instead of
  global flag variables. Configuration is data, not module state.
- **`flag.NewFlagSet()` not the global `flag` package.** Globals leak
  across tests and subcommands; a fresh FlagSet per invocation
  doesn't.
- **`flag.DurationVar` directly into `http.Client.Timeout`.** Skip the
  intermediate "seconds as int" representation. The struct field is
  the source of truth.
- **`flag.ErrHelp` from `fromArgs` triggers usage and exit-2.** The
  same return path that handles `--help` also handles "you gave us
  garbage" — clean and uniform.
- **No `check()` / `must()` / `try()` helper.** Closes off every error
  response except "abort." Real CLIs need warnings, retries, and
  recovery; the helper makes that impossible to add later.
- **Generic helpers, not wrapper client types.** `func (app *appEnv)
  fetchJSON(url string, data interface{}) error` is reusable into the
  next CLI; `XKCDClient.Fetch()` isn't.
- **Two separate output functions, not a polymorphic one.**
  `printJSON()` and `prettyPrint()` will diverge — let them. Sharing a
  type now is the kind of "DRY" that costs flexibility later.
- **The rewrite was the same line count as the original** (197+ /
  197-) but handled more error cases. Architecture is not a fixed
  cost; sloppy code and clean code take the same number of lines.

## Where this maps onto Glue

Glue is a Dart CLI/TUI. The post's Go-specific recommendations
(`flag.NewFlagSet`, `http.Client`) don't transfer; the *patterns* do.
Concrete hooks:

1. **Audit Glue's exit codes.** Glue should return 0 for success, 2
   for argument/init errors (bad flags, missing API key,
   unrecognized model), 1 for runtime errors (provider failure,
   user-cancelled session). If Glue currently returns 1 for both
   classes, scripts can't distinguish "I gave bad input" from "the
   model timed out." See `cli-three-layer-architecture.md`.
2. **Look at how Glue's flag parsing is wired.** Dart's
   `package:args` is the analogue to Go's `flag` package. The
   pattern to mirror: parse into a config struct (a `class
   GlueConfig`), not into module-level variables. `fromArgs(List<String>
   args)` becomes a static factory or constructor. See
   `cli-config-and-flags.md`.
3. **Confirm `glue -p "..."` (non-interactive mode) and the TUI
   share an execution layer**, not an output layer. The post's
   advice is that human output and machine output should never share
   a formatter even if they happen to overlap right now. Glue's
   `--json` (if present) and TUI rendering should call into the
   same execution path with different output adapters. See
   `cli-execution-and-output.md`.
4. **Check for `check()`-equivalents in Glue.** Dart has its own
   tempting shortcuts: `?? throw`, `!`, `assert()`, top-level
   `exitCode = 1; exit(0)`. Each one closes off a future "warn,
   don't die" or "retry once" path. See
   `cli-execution-and-output.md`.
5. **Glue's `cli.Run()` analogue.** Glue's `bin/main.dart` should
   be a single line: `Future<void> main(List<String> args) async =>
   exit(await GlueCli.run(args));`. Anything else (logger setup,
   config loading) belongs *inside* the `run()` function, where it
   can be tested.

## Source provenance

- **Source**: `https://blog.carlana.net/post/2020/go-cli-how-to-and-advice/`
- **Author**: Carl Mastrangelo
- **Date**: 2020 (no further version metadata; web essay)
- **License**: All-rights-reserved blog post. These notes paraphrase
  rather than quote; brief code-shape excerpts are normal fair-use
  technical citation with attribution.
- **Reviewed**: 2026-04-25

The post itself is a critique-and-rewrite of an earlier
"Programming a Real-World Go CLI" demo by Tony Tsui, so the post
includes both an "anti-pattern" and a "preferred" version of every
section. The notes here lift the preferred version.
