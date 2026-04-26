# CLI Configuration and Flag Parsing

The `appEnv` pattern: configuration is a value, not module state.
Every CLI program ends up with a struct that holds "the things
parsed from argv plus environment plus defaults"; the question is
whether you let it be a global by accident or design it as a value
on purpose.

## The pattern

The Go shape (paraphrased — not a verbatim copy):

```go
type appEnv struct {
    hc         http.Client
    comicNo    int
    saveImage  bool
    outputJSON bool
}

func (app *appEnv) fromArgs(args []string) error {
    fl := flag.NewFlagSet("grabxkcd", flag.ContinueOnError)
    fl.IntVar(&app.comicNo, "n", 0, "comic number")
    fl.BoolVar(&app.saveImage, "s", false, "save image")
    fl.BoolVar(&app.outputJSON, "json", false, "output JSON")
    fl.DurationVar(&app.hc.Timeout, "t", 30*time.Second, "HTTP timeout")
    if err := fl.Parse(args); err != nil {
        return err
    }
    if app.comicNo <= 0 {
        return fmt.Errorf("comic number must be positive")
    }
    return nil
}

func CLI(args []string) int {
    var app appEnv
    if err := app.fromArgs(args); err != nil {
        return 2
    }
    if err := app.run(); err != nil {
        return 1
    }
    return 0
}
```

The four things this is doing right, each non-obvious in isolation:

### 1. The struct _is_ the configuration

Not a "config object passed to" the rest of the program — the
program operates as methods on the struct. `app.run()` reads
`app.comicNo` and `app.outputJSON` directly. This sounds like
global state by another name; it isn't, because:

- The struct is local to `CLI()`. Each invocation gets a fresh
  one.
- Tests construct `appEnv` directly, skip `fromArgs`, and call
  `app.run()` with whatever values they want. No flag-parsing
  ceremony in tests.
- Subcommands or repeated invocations don't share state. The
  global-flag version of this leaks values from one test to the
  next.

### 2. `flag.NewFlagSet`, not the global `flag` package

The Go `flag` package documentation suggests:

```go
var n = flag.Int("n", 0, "comic number")
func init() { flag.Parse() }
```

This is convenient but creates a global `flag.CommandLine`. For a
CLI with one main and no tests it works fine. For anything else
(subcommands, table-driven tests, embedded usage) the global
package leaks state across invocations.

`flag.NewFlagSet("name", flag.ContinueOnError)` makes a fresh
parser scoped to one call. The `ContinueOnError` mode (vs.
`ExitOnError`) lets `fromArgs` _return_ the error to the caller
instead of calling `os.Exit` from inside the flag library — which
matters because the caller is the only place that knows whether
to exit 2 (bad flags), exit 1 (a different layer's error), or
exit 0 (`--help` was requested).

### 3. `DurationVar` directly into the destination

```go
fl.DurationVar(&app.hc.Timeout, "t", 30*time.Second, "HTTP timeout")
```

`http.Client.Timeout` is a `time.Duration`. The flag is parsed as
a `time.Duration` (`30s`, `2m`, `500ms`). The flag binds _directly
into the struct field that consumes it_. No intermediate `int
seconds` variable, no manual conversion.

The general lesson: when a flag's parsed value has the same type
as a field on a struct you're going to populate, point the flag
at the field. Flag libraries usually support enough types
(`int`, `bool`, `string`, `time.Duration`, custom `flag.Value`
implementations) to make this clean.

### 4. `flag.ErrHelp` is the unified validation-error return

When a user passes `--help`, the `flag` package returns
`flag.ErrHelp` from `Parse`. The post's pattern returns that
same sentinel from `fromArgs` _also_ when validation fails:

```go
if app.comicNo <= 0 {
    fl.Usage()
    return flag.ErrHelp
}
```

Then in `CLI`:

```go
if err := app.fromArgs(args); err != nil {
    if errors.Is(err, flag.ErrHelp) {
        return 0
    }
    fmt.Fprintln(os.Stderr, err)
    return 2
}
```

`--help` is exit 0; bad flags are exit 2; `flag.ErrHelp` is the
same return path either way. The "explain yourself" output
already happened (`flag.Usage()` printed it); the caller just
decides the exit code.

## What `package:args` looks like in Dart

Dart's `package:args` is the standard equivalent to Go's `flag`.
The shape transfers cleanly:

```dart
class GlueConfig {
  final String? prompt;
  final String model;
  final bool json;
  final Duration timeout;
  final String? sessionId;
  // ...

  GlueConfig({...});

  static Result<GlueConfig> fromArgs(List<String> args) {
    final parser = ArgParser()
      ..addOption('prompt', abbr: 'p')
      ..addOption('model', abbr: 'm', defaultsTo: 'claude-sonnet-4-6')
      ..addFlag('json')
      ..addOption('timeout', defaultsTo: '30s')
      ..addOption('session');
    final r = parser.parse(args);

    final timeout = parseDuration(r['timeout'] as String);
    final model = r['model'] as String;
    if (!isKnownModel(model)) {
      return Result.err('unknown model: $model');
    }
    return Result.ok(GlueConfig(
      prompt: r['prompt'] as String?,
      model: model,
      json: r['json'] as bool,
      timeout: timeout,
      sessionId: r['session'] as String?,
    ));
  }
}
```

Three differences from Go:

- `package:args` doesn't have a `flag.ErrHelp` equivalent — you
  build your own (return a `Result.help()` variant or throw a
  specific exception).
- Dart's `Duration` doesn't parse `30s` natively; either use a
  small helper (`parseDuration`) or accept seconds-as-int and
  convert.
- The struct is a class with a constructor, not a struct literal.
  Same shape, different syntax.

## What this would look like in Glue

The audit for Glue:

1. **Find Glue's argv-parsing site.** It's almost certainly in
   `cli/bin/main.dart` or `cli/lib/src/cli/`. Confirm whether the
   parsed values land in:
   - A class instance (good — the `appEnv` shape).
   - Module-level variables or `late final` globals (bad — globals
     in disguise).
   - The first lines of `main()` itself (acceptable but harder to
     test).
2. **Look for `late` / global state holding parsed flags.** If
   `Glue.model` is a `late final String model = parsedArgs['model']`
   somewhere, that's the global pattern. Move it onto a config
   class.
3. **Check `--help` exit code.** It should be 0 (the user asked
   for help and got it). Bad flags should be 2. Most CLIs
   accidentally treat both as 1 because they both go through the
   same "print and exit" path.
4. **Validate enum-like options after parsing.** Glue probably
   has flags like `--model`, `--provider`, `--output` that should
   accept only specific values. The validation belongs in
   `fromArgs` (so the user gets exit 2 for "bad flag") not in the
   execution layer (where they'd get exit 1).
5. **Bind durations as `Duration`, not as integer seconds.** If
   Glue has a `--timeout` or `--read-timeout` flag and parses it
   as `int seconds`, replace with a `Duration` parser. The
   integer representation will eventually have to support `30s`,
   `2m`, etc. anyway.

The conversion from "global flags" to "appEnv struct" is purely
mechanical and almost always reduces code. The struct gives you
one place where every option lives, which means tests stop
needing 12-line "set up the globals" preambles.

## Where this lives in the source

| Pattern                                  | Location in the post                                   |
| ---------------------------------------- | ------------------------------------------------------ |
| `appEnv` struct + `fromArgs` method      | § "User Input Layer: Flag Parsing"                     |
| `flag.NewFlagSet` over global `flag`     | same — citing Peter Bourgon's "no globals" rule        |
| `DurationVar` straight into client field | same — example uses `http.Client.Timeout`              |
| `flag.ErrHelp` as the validation return  | same — unifies `--help` and "bad flag" return paths    |
| Two packages, not three                  | § "Problems with Existing Patterns" (Dave Cheney link) |
