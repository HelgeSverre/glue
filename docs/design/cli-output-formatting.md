# CLI Output Formatting

How `glue …` top-level subcommands render text to stdout/stderr. This file is
the source of truth — when a new command is added, follow this. When two
commands disagree, the one that diverges from this doc is wrong.

## Scope

Applies to anything that writes to stdout/stderr from a `Command<int>` subclass
under `cli/lib/src/commands/`, plus the matching `*_format.dart` modules.

Out of scope: TUI rendering (`lib/src/terminal/`, `lib/src/rendering/`,
`lib/src/ui/`) and the markdown renderer — those always target a real terminal
and use the raw `.styled` API.

## Vocabulary

All glyphs go through `cli/lib/src/terminal/brand.dart`. Never roll your own:

| Glyph | Helper        | When                                                |
| ----- | ------------- | --------------------------------------------------- |
| ●     | `brandDot`    | Section header (one per command output, top)        |
| ✓     | `markerOk`    | Success / present / stored / enabled                |
| !     | `markerWarn`  | Missing-but-recoverable / disconnected / connecting |
| ✗     | `markerError` | Hard failure / dead / unrecoverable error           |
| ·     | `markerInfo`  | Neutral / disabled / "not configured"               |

Avoid free emoji (🎉, ❌, ⚠️). They render inconsistently across terminals and
break the visual rhythm of the rest of the CLI.

## The four layers

```
+--------------------------------------+
|  Command<int>  (run() in *_command.dart) |  ← thin: parse args, fetch
|                                          |     data, call formatter,
|                                          |     stdout.writeln(result).
+--------------------------------------+
|  Formatter    (*_format.dart)        |  ← pure: takes value objects,
|                                          |     returns a string. No I/O.
+--------------------------------------+
|  styledOrPlain(text, decorate)       |  ← TTY/NO_COLOR guard.
|  (cli/lib/src/terminal/tty_style.dart)   |
+--------------------------------------+
|  Styled  (.styled.bold.green …)      |  ← raw ANSI builder.
|  (cli/lib/src/terminal/styled.dart)      |
+--------------------------------------+
```

### Command<int>

Stays thin. Parse args, load config or pool, project results into the
formatter's input value objects, then `stdout.writeln(formatX(rows))`. Never
build styled strings inline in `run()` for anything more complex than a
single-line confirmation (`✓ Added stdio server "demo".`).

### `*_format.dart`

Pure function, no I/O, no dependency on `dart:io`. Takes simple value objects
or records — never `McpClientPool`, never `GlueConfig`. Returns a single
string. Accepts an optional `bool? ansiEnabled` for testability. Defaults to
`stdoutSupportsAnsi()`.

Reference implementations:

- `cli/lib/src/commands/mcp_tools_format.dart` (most complete shape)
- `cli/lib/src/commands/mcp_list_format.dart`
- `cli/lib/src/commands/mcp_auth_status_format.dart`
- `cli/lib/src/terminal/where_report.dart` (for `glue --where`)

### `styledOrPlain`

Use this **every time** styled output might land in a non-TTY context: pipes,
redirects, captured stdout, CI logs. Brand markers already route through it,
so just calling `brandDot` / `markerOk` is safe. For inline `.styled` chains,
write:

```dart
final id = styledOrPlain(spec.id, (s) => s.bold, ansiEnabled: ansi);
```

`ansi` comes from the `ansiEnabled` parameter (in a formatter) or
`stdoutSupportsAnsi()` (in a command).

### Raw `.styled`

Reserved for TUI / terminal rendering where ANSI is always wanted. Don't use
it in command output paths.

## Output shape

### Diagnostic / inventory commands

(`glue --where`, `glue catalog show`, `glue doctor`, `glue mcp list`,
`glue mcp tools`, `glue mcp auth status`)

```
● <Title>            ← brandDot + 'Title'.styled.bold
  <body…>
                     ← blank line before footer hint, if any
<footer hint in gray>
```

- Exactly one brandDot title per command run.
- Body indented two spaces.
- Status lines lead with a severity marker:
  `  fs    stdio  ✓ enabled`
- Annotations in parentheses use a status color:
  `● fs (dead)` → `(dead)` in red; `(connecting)` in yellow; `(disabled)` in gray.
- Empty-state lines explain why:
  `  ✗ dead: handshake timeout`, `  · disabled; enable to list tools`.

### Action commands

(`glue mcp add`, `glue mcp enable`, `glue catalog refresh`, `glue config init`)

```
✓ <verb past-tense> "<id>".          ← markerOk + plain phrase + bold id
<follow-up hint in gray>             ← e.g. 'Run "glue" to load it.'
```

- One-line success, optional one or two gray hints.
- No brandDot — these aren't "reports".
- Errors go to **stderr** with no marker; the non-zero exit code is the signal.
  Keep stderr lines short, no styling. Tests and scripts grep stderr; don't
  decorate it.

### Pure-config commands

(`glue completions install`, `glue config path`, `glue mcp remove`)

Plain text. No marker, no header. They're mechanical, not informational.

## stdout vs stderr

- **stdout**: structured output the user asked for (lists, reports, JSON,
  the result of an action).
- **stderr**: errors, warnings, progress chatter that scripts shouldn't
  consume.

Never colorize stderr. It's almost always captured.

## `print()` vs `stdout.writeln()`

Use `stdout.writeln()`. `print()` is fine in tests and tools but inconsistent
in command code (e.g. it can't be redirected as cleanly on Windows).

## JSON / machine output

When a command takes `--json` or `-p/--print`, suppress all styling — even
the brandDot. `--json` output goes through `jsonEncode(…)` and is never
decorated. `--print`/`-p` plain mode is the same: a clean string with no
ANSI, regardless of TTY.

## Piping & `NO_COLOR`

- `glue mcp list | grep enabled` must produce grep-friendly output.
- `NO_COLOR=1 glue …` must produce zero ANSI.

`styledOrPlain` enforces both. Verify a new command by running it twice
during dev:

```sh
glue <cmd>                  # styled
glue <cmd> | cat            # plain (no TTY on stdout)
NO_COLOR=1 glue <cmd>       # plain (opt-out)
```

## Testing the formatter

Two kinds of test, both fast:

1. **Plain-output assertions** (default, dart test has no TTY):

   ```dart
   test('rows show id + transport + state', () {
     final result = formatMcpServerList(rows, configPath: '/x.yaml');
     expect(result, contains('fs'));
     expect(result, isNot(contains('\x1b[')));   // no ANSI
   });
   ```

2. **ANSI-enabled assertions** (explicit override):

   ```dart
   test('enabled rows use ✓', () {
     final result = formatMcpServerList(rows,
         configPath: '/x.yaml', ansiEnabled: true);
     expect(result, contains('✓'));
   });
   ```

Process-level tests (`Process.start`) automatically run without a TTY, so
`contains('substr')` works regardless of styling — no special-casing needed.

## Anti-patterns

- Inline `'foo'.styled.red.toString()` in a command's `run()`. Ship it
  through `styledOrPlain` or a brand marker.
- Two brandDot headers in one command's output.
- Emoji that aren't in the marker vocabulary.
- ANSI codes hard-coded as `\x1b[…m` strings.
- Stderr writes that include ANSI.
- Mixing `print()` and `stdout.writeln()` in the same file.
- Building the formatter inside the `Command<int>` class.

## Drift register

State of the union (2026-05). Update as commands are harmonized:

| Command           | Header  | Markers | Format extracted | TTY-aware |
| ----------------- | ------- | ------- | ---------------- | --------- |
| `--where`         | ✓       | ✓       | ✓                | ✓         |
| `catalog show`    | ✓       | ✓       | inline¹          | ✓         |
| `catalog refresh` | ✓       | ✓       | inline¹          | ✓         |
| `catalog path`    | ✓       | ✓       | inline¹          | ✓         |
| `catalog open`    | ✓       | ✓       | inline¹          | ✓         |
| `catalog edit`    | ✓       | ✓       | inline¹          | ✓         |
| `doctor`          | ✓       | ✓       | ✓                | ✓         |
| `mcp list`        | ✓       | ✓       | ✓                | ✓         |
| `mcp tools`       | ✓       | ✓       | ✓                | ✓         |
| `mcp auth status` | ✓       | ✓       | ✓                | ✓         |
| `mcp add`         | n/a     | ✓       | inline (1-line)  | ✓         |
| `serve`           | ✓       | ✓       | inline           | ✓         |
| `session list`    | ✓       | —       | inline           | ✓         |
| `session show`    | ✓       | —       | inline           | ✓         |
| `session apply`   | n/a     | ✓       | inline (1-line)  | ✓         |
| `session export`  | n/a     | ✓       | inline (1-line)  | ✓         |
| `session diff`    | n/a     | n/a     | n/a (raw patch)  | n/a       |
| `config *`        | n/a     | n/a     | inline (plain)   | n/a       |
| `completions *`   | n/a     | n/a     | inline (plain)   | n/a       |

¹ Catalog renders are short and tightly coupled to their input shape;
extraction into `*_format.dart` is **nice-to-have** but not blocking. The
TTY guard is already in place via `styledOrPlain`.

When you touch one of these surfaces, consider promoting "inline" to a
proper `*_format.dart` if the rendering gets non-trivial.
