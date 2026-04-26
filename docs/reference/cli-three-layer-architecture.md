# CLI Three-Layer Architecture

Carl Mastrangelo's central thesis: any non-trivial CLI has three
layers — input, execution, output — and they should be separate
from the start. Other layers (config files, plugin systems,
client/server splits) are speculative until proven necessary. This
file covers that core shape plus its supporting moves: the
single-line `main()`, the `Run() int` boundary, and the exit-code
triad.

## The three layers

| Layer       | Job                                                                |
| ----------- | ------------------------------------------------------------------ |
| **Input**   | Take `argv`, environment, stdin; produce a structured config value |
| **Execute** | Take that config; do the actual work; produce a structured result  |
| **Output**  | Take the result; render to a destination (stdout, file, exit code) |

Read top to bottom: input flows in, gets normalized, gets executed
into a result, gets formatted out. Errors at any layer propagate
back through the same chain.

What this isn't:

- Hexagonal architecture (no port/adapter abstraction unless needed).
- Onion architecture (no domain/infrastructure rings).
- MVC (no controller).

It's the smallest split that lets you test each piece in isolation:

- Test input parsing without doing real work.
- Test execution with a fake config struct.
- Test output rendering against a known result.

## Why three is the right number

The post's argument is YAGNI applied to CLI scaffolding. A CLI
_always_ has these three responsibilities. It _might_ have:

- A persistent config file (only matters if there's user state).
- A subcommand router (only matters if there's more than one verb).
- A client/server split (only matters if work is remote).
- A plugin loader (only matters if extensibility is a real
  requirement, not "we might want to be extensible someday").

Build the three you always need; add the others when their absence
hurts. Adding a layer to working code is fast; removing a
speculative one nobody uses is slow.

## The `main()` → `Run() int` shape

The post's preferred entry point:

```go
package main

import (
    "os"
    "github.com/you/proj/cli"
)

func main() {
    os.Exit(cli.Run())
}
```

Three things this gets right:

1. **`main()` does no work.** It can't, because it returns nothing
   useful and can't be tested. Move every line of logic into a
   function that _can_ be tested.
2. **`Run()` returns `int`, not `error`.** The integer is the exit
   code. Returning `error` would force `main()` to translate, which
   is exactly the layering violation we're trying to avoid.
3. **`os.Exit` is called exactly once, in `main()`.** Anywhere else
   it's called, deferred cleanups don't run, tests can't run the
   code, and the exit code becomes hard to trace. The pattern
   centralizes termination at the only place where termination is
   inevitable.

The Dart equivalent is identical in shape:

```dart
import 'dart:io';
import 'package:glue/cli.dart';

Future<void> main(List<String> args) async {
  exit(await GlueCli.run(args));
}
```

`exit()` is called exactly once. `GlueCli.run()` is the testable
boundary that returns an `int`.

## Exit codes: 0 / 1 / 2

The convention the post recommends, which is older than Go and
almost universal in Unix CLI tooling:

| Code | Meaning                         | Examples                                          |
| ---- | ------------------------------- | ------------------------------------------------- |
| 0    | Success                         | Command ran, produced expected output             |
| 1    | Runtime error                   | API call failed, file not found, network timeout  |
| 2    | Initialization / argument error | Bad flag, missing required value, validation fail |

What this enables in shell scripts:

```bash
my-cli --foo bar || {
    case $? in
        2) echo "you gave it bad arguments"; exit 2 ;;
        1) echo "it ran but failed; retry?"; exit 1 ;;
    esac
}
```

Without the distinction, every script's error path collapses to "I
don't know what went wrong; surface the error and bail." Most CLIs
return 1 for everything, which forces consumers to grep stderr to
distinguish failure modes — fragile and locale-sensitive.

Higher codes are application-defined. The post doesn't enumerate
them, but the conventions are:

- 64–78 are reserved by `sysexits.h` (BSD) for specific failure
  classes (`EX_USAGE=64`, `EX_DATAERR=65`, …). Use them if you're
  shipping system-level tooling; otherwise their semantics are too
  baroque for an LLM agent CLI.
- 130 = SIGINT (Ctrl-C). Set automatically by the shell when the
  CLI is killed by signal 2; you don't usually set this yourself.
- 137 = SIGKILL (128 + 9), 143 = SIGTERM (128 + 15). Same — signal
  exit codes come from the shell, not from `exit()`.

## What this would look like in Glue

Glue's CLI lives in `cli/bin/main.dart` (or equivalent). The
audit:

1. **Is `main()` a single line that delegates?** If it loads
   config, sets up logging, parses argv, and _then_ calls a
   function — pull all of that into the called function. The post's
   point is that everything except `exit()` should be testable.
2. **Does Glue distinguish exit code 1 from 2?** Test cases:
   - `glue --no-such-flag` → exit 2 (argument error)
   - `glue -m no-such-model` → exit 2 (validation error: model
     doesn't exist)
   - `glue -p "..."` with API key invalid → exit 1 (runtime: the
     model returned auth error)
   - `glue -p "..."` and the user cancels (Ctrl-C) → 130 from the
     shell, no explicit `exit()` call needed
3. **Are the three layers separable?** A `glue -p "..."` invocation
   should look like:
   - **Input**: parse argv → produce a `RunConfig` (model, prompt,
     output format, session id, …).
   - **Execute**: take `RunConfig` → produce a `RunResult` (the
     model's response, token counts, finish reason).
   - **Output**: take `RunResult` → render to stdout (human format,
     `--json`, or whatever).
     The TUI mode is just a different output layer fed by the same
     execution path with `RunConfig.interactive = true`.

If any of these don't hold today, the file changes are mechanical:
move code into `GlueCli.run()`, split `RunConfig` from its parsing,
split rendering from execution. None of this requires a redesign.

## Where this lives in the source

| Pattern                     | Location in the post                                       |
| --------------------------- | ---------------------------------------------------------- |
| Three-layer model           | § "Core Architectural Principle (Three Essential Layers)"  |
| Single-line `main()`        | § "The Single-Line Main Function" (credited to Nate Finch) |
| Exit code triad (0 / 1 / 2) | § "User Input Layer: Flag Parsing"                         |
| YAGNI for additional layers | § "Introduction & Context"                                 |
