# CLI Execution and Output

The post's middle and final layers: how the work gets done, and how
the result reaches the user. Two patterns to lift, plus one
anti-pattern to avoid.

## Generic helpers, not wrapper client types

The anti-pattern the post critiques:

```go
// the original demo:
type XKCDClient struct {
    client  *http.Client
    baseURL string
}

func NewXKCDClient() *XKCDClient { ... }
func (c *XKCDClient) Fetch(n ComicNumber) (model.Comic, error) { ... }
```

This _looks_ like good encapsulation — domain-named type, hidden
HTTP details, methods that speak the domain's vocabulary. The
post's argument is that it's the wrong abstraction:

- The `XKCDClient` only knows how to talk to XKCD. Its "encapsulation"
  doesn't help anyone except a hypothetical second XKCD client.
- The base URL it hides isn't a secret — it's `https://xkcd.com`,
  printed in the README. Hiding it just means a test can't redirect
  it without touching the type.
- It owns an `*http.Client` field that callers can't customize
  except through more wrapper methods.

The preferred shape:

```go
func BuildURL(comicNumber int) string { ... }

func (app *appEnv) fetchJSON(url string, data interface{}) error {
    resp, err := app.hc.Get(url)
    if err != nil { return err }
    defer resp.Body.Close()
    return json.NewDecoder(resp.Body).Decode(data)
}
```

Two pieces:

1. `BuildURL` is a **pure function**: comic number in, URL out. No
   hidden state, trivially testable, trivially copyable into the
   next CLI you write.
2. `fetchJSON` is a **generic method on `appEnv`** that takes any
   URL and any decoding target. It works for XKCD, but it'd also
   work for the JSON Placeholder API, GitHub, Anthropic — anything
   that returns JSON over HTTP. The reusability comes from
   _reducing_ what's in the type, not adding to it.

The customization that the wrapper type was supposed to enable
(testing, retries, base-URL overrides) lives on the `http.Client`
itself: pass a different `Transport` (a `RoundTripper`
implementation) and you've got a mock or a retry decorator without
touching the helpers.

## Separate output paths, even when they look the same

The post's other concrete recommendation: don't unify `printJSON`
and `prettyPrint` even when they currently render the same data.

Bad:

```go
func (r APIResponse) String() string { ... }  // shared by both paths
```

Good:

```go
func (app *appEnv) run() error {
    resp, err := app.fetch()
    if err != nil { return err }
    if app.outputJSON {
        return printJSON(resp)
    }
    return prettyPrint(resp)
}
```

The reasoning is timing, not capability:

- Today both functions render the same fields. Tomorrow one might
  add a "humanize the date" step, or omit a field that's noisy in
  human output but useful for `jq`.
- The cost of keeping them separate now is zero. The cost of
  splitting them after they've been unified for six months is
  re-deriving which call site needed which behavior.
- Machine output and human output have different audiences. Their
  _shape requirements diverge over time_. Building toward that
  divergence from day one is cheap; retrofitting it isn't.

The same logic applies to any pair of "output adapters" that
share data right now: stdout vs file, terse vs verbose, color vs
no-color. Default to separate functions; consolidate only when
the shared behavior is actually identical and stays that way.

## No `check()`, no `must()`, no `try()`

The post calls out the helper that initially looked harmless:

```go
func check(err error) {
    if err != nil {
        log.Fatal(err)
    }
}
```

The argument: this helper makes "one specific thing" easy
(immediate fatal) and makes "literally anything else" impossible.
For a 50-line script it's fine; for any CLI that grows past that
size it becomes a deletion target.

What you can't do once `check()` is sprinkled through the code:

- Translate one error into a warning: `couldn't find optional
config file → continue with defaults`.
- Retry an operation that the user might have transient-failed.
- Aggregate multiple errors and report them all at once.
- Add structured logging that captures the error before exiting.
- Skip exit when running under tests (because `log.Fatal` calls
  `os.Exit` and breaks `go test`).
- Distinguish exit code 1 (runtime) from 2 (init).

Each of those is a real product change someone will eventually
ask for. Once `check()` is the failure path, every one of them is
"first, replace 47 calls to `check()`."

The Dart equivalents to watch for:

| Dart shortcut                            | What's wrong with it                           |
| ---------------------------------------- | ---------------------------------------------- |
| `result!`                                | Throws on null with no caller-friendly message |
| `?? throw "..."`                         | Same problem, slightly better message          |
| `assert()`                               | Removed in production builds — silent failure  |
| `exit(1)` mid-call                       | No deferred cleanup, no test isolation         |
| `.then(... .catchError((_) => exit(1)))` | Same issue, futurized                          |

The post's preferred shape is `return err` everywhere, then a
single `if err != nil { return 1 }` at the top of `CLI()`. In Dart
that's `throw` with custom exception types and a single
`try/catch` at the top of `GlueCli.run()`:

```dart
class GlueRuntimeError implements Exception { ... }
class GlueArgumentError implements Exception { ... }

static Future<int> run(List<String> args) async {
  try {
    final config = parseArgs(args);
    final result = await execute(config);
    return render(result);
  } on GlueArgumentError catch (e) {
    stderr.writeln(e.message);
    return 2;
  } on GlueRuntimeError catch (e) {
    stderr.writeln(e.message);
    return 1;
  }
}
```

One catch site, every error class explicit, every layer free to
return / throw / wrap as it sees fit.

## What this would look like in Glue

The post's three execution-layer ideas, projected onto Glue:

1. **Audit Glue's HTTP client usage.** Glue talks to multiple
   provider APIs (Anthropic, OpenAI, Mistral, GitHub Copilot,
   Ollama). The right shape is one shared `http.Client` instance
   (or `package:http`'s `Client`) and per-provider helper
   functions that take that client. Avoid `class AnthropicClient`
   that owns its own HTTP client and keeps its own base URL —
   per the post, this just creates one wrapper per provider with
   no actual reuse benefit. The differences between providers
   are real (auth header, request shape) but live at the
   request-construction layer, not in a class hierarchy.
2. **Check Glue's output paths for premature unification.** Glue
   probably has at least:
   - TUI rendering (markdown, code highlighting, scroll buffer).
   - `glue -p "..."` non-interactive stdout.
   - `--json` machine output (if it exists; if not, it'll be
     asked for soon).
   - Error output to stderr.
     Each is a separate output adapter consuming the same
     `RunResult`. They should not share rendering code beyond
     pure formatting helpers (e.g. a `formatDuration(d)` is
     fine to share; a `RunResult.toString()` that all three call
     is the trap the post warns about).
3. **Look for `check()`-equivalents in Glue's tool layer.** Tool
   call execution is the most likely place — a `ShellTool` that
   throws on `exitCode != 0` instead of returning the
   non-zero result to the agent forecloses on every "the agent
   should see and react to the error" pattern. Compare to
   what Claude Code does: shell tool always returns, and
   exit-code information is part of the structured response so
   the model can reason about it.
4. **Make sure the execute layer doesn't render or exit.** If
   Glue's `execute(config)` calls `print()` directly or
   `exit(1)` on failure, those are layering violations. Execute
   should produce a value (or throw an exception). Rendering
   and exiting belong to `main()` and the output adapter.

## Where this lives in the source

| Pattern                                    | Location in the post                                     |
| ------------------------------------------ | -------------------------------------------------------- |
| `BuildURL` + `fetchJSON` over `XKCDClient` | § "Actual Task Execution"                                |
| Customizing via `http.Client.Transport`    | same — credited to Mat Ryer's dependency-injection style |
| `printJSON` vs `prettyPrint` separation    | § "Output Formatting"                                    |
| The `check()` anti-pattern                 | § "Problems with Existing Patterns" — error handling     |
| Why "the rewrite was the same line count"  | § "Public API Summary"                                   |
