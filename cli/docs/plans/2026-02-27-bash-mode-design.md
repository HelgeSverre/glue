# Bash Mode — Shell Passthrough with Background Jobs

## Overview

A `!` prefix switches the input prompt to bash mode, allowing direct shell command execution without involving the LLM. Commands run blocking by default. A `&` prefix within bash mode starts a managed background job. Output is rendered in a fieldset/legend style box, visually distinct from agent conversation. Bash output is never sent to the agent.

## Mode Switching

### Entering Bash Mode

Typing `!` at cursor position 0 (regardless of existing buffer contents):
- The `!` character is consumed (not inserted into buffer)
- `App._bashMode` set to `true`
- Prompt changes from yellow `❯` to red `!`

This means typing `!git push` from an empty prompt enters bash mode and leaves `git push` in the buffer. It also means: type a message, press Home, type `!` → switches to bash mode with the existing text preserved.

### Exiting Bash Mode

Pressing Backspace at cursor position 0 while in bash mode:
- Switches back to normal mode (`_bashMode = false`)
- Buffer contents preserved
- Prompt returns to yellow `❯`

This enables fluid switching: type `!run git commit for me`, realize you want the agent to handle it, press Home → Backspace → now in normal mode with `run git commit for me` ready to send.

### Detection Point

In `App._handleTerminalEvent`, intercept before passing to `LineEditor`:
- `CharEvent('!')` when `editor.cursor == 0 && !_bashMode` → consume, set bash mode
- Backspace `KeyEvent` when `editor.cursor == 0 && _bashMode` → consume, clear bash mode

## Blocking Execution

### Flow

1. User submits text in bash mode (no `&` prefix)
2. `AppMode` switches to new `AppMode.bashRunning`
3. Process started via `Process.start('sh', ['-c', command])` with no stdin
4. stdout/stderr collected asynchronously
5. On completion: strip ANSI from output, tail to `bashMaxLines`, add `_ConversationEntry.bash` block, return to `AppMode.idle`

### Cancellation

- Ctrl+C during `bashRunning` → kill the process (SIGTERM), show partial output, return to idle
- Escape during `bashRunning` → same behavior
- The process never receives stdin — it's fire-and-forget, non-interactive

### Double-Tap Ctrl+C to Exit (Global)

Prevents accidentally quitting Glue when the user thought an operation was still running:

1. First Ctrl+C when idle → insert system message "Press Ctrl+C again to exit", start ~2 second timer
2. Second Ctrl+C within the timer window → shutdown Glue
3. Timer expires → reset state, next Ctrl+C starts the cycle over

This applies globally (not just bash mode) — protects against accidental exits in all contexts.

## Background Jobs

### Syntax

Within bash mode, prefixing with `&` runs the command as a managed background job:
- `& npm run dev` → background job
- `& dart run build_runner watch` → background job

Since `!` enters bash mode and `&` is the first character, typing `!& npm run dev` from normal mode works naturally — `!` switches to bash mode (consumed), `& npm run dev` is submitted.

### ShellJobManager

Owns background `Process` handles and buffers output.

```dart
class ShellJobManager {
  int _nextId = 1;
  final _jobs = <int, ShellJob>{};
  final _events = StreamController<JobEvent>.broadcast();

  Stream<JobEvent> get events => _events.stream;

  Future<ShellJob> start(String command);
  ShellJob? getJob(int id);
  Future<void> kill(int id);
  Future<void> shutdown();  // cleanup on Glue exit
}
```

### ShellJob

```dart
class ShellJob {
  final int id;
  final String command;
  final DateTime startTime;
  final Process process;
  final LineRingBuffer output;  // combined stdout+stderr
  JobStatus status;
  int? exitCode;
}
```

### JobStatus + Events

```dart
enum JobStatus { running, exited, failed, killed }

sealed class JobEvent {}
class JobStarted extends JobEvent { ... }
class JobExited extends JobEvent { ... }
class JobError extends JobEvent { ... }
```

### LineRingBuffer

Bounded circular buffer for output:
- `maxLines`: 2000
- `maxBytes`: 256 KB
- Oldest lines evicted when limits exceeded
- `tail({int lines})` returns last N lines
- `dump()` returns full buffer contents

### Lifecycle

- On start: system block `"Started job #1: npm run dev"`
- On exit: system block `"Job #1 exited (0): npm run dev"` (or `failed (1)`)
- On Glue shutdown: SIGTERM all running jobs → 800ms grace period → SIGKILL

### Integration with App

- `ShellJobManager` created in `App.create()`, held as `App._jobManager`
- Subscribe to `_jobManager.events` in `run()`, insert system blocks on job lifecycle events
- Process stdout/stderr captured with no stdin attached

## Output Rendering

### Bash Block (Fieldset/Legend Style)

New `_EntryKind.bash` and `BlockRenderer.renderBash(String command, String output)`:

```
┌─ git push ───────────────────────────┐
│ Enumerating objects: 5, done.        │
│ Counting objects: 100% (5/5), done.  │
│ Total 3 (delta 1), reused 0         │
│ To github.com:user/repo.git         │
│    abc1234..def5678  main -> main    │
└──────────────────────────────────────┘
```

- Border: dim gray (`\x1b[90m`)
- Command name in legend: bold white
- Content: no color (ANSI stripped from command output)
- 1-char padding inside box on left

### ANSI Stripping

All command output has ANSI escape sequences stripped before rendering. Prevents color bleed and terminal corruption from unclosed sequences (e.g. `git diff` output). TODO: revisit preserving colors in the future once we can guarantee safety.

### Output Truncation

Blocking command output truncated to the last `bashMaxLines` lines (default: 50). If truncated, show `"… (N lines above)"` at the top of the box.

### Background Job Notifications

Simple system messages (no box):
```
↳ Started job #1: npm run dev
↳ Job #1 exited (0): npm run dev
```

## Prompt Rendering

In `App._doRender`, the input prompt changes based on mode:

```dart
final prompt = switch ((_mode, _bashMode)) {
  (AppMode.idle, true) => '! ',     // red
  (AppMode.idle, false) => '❯ ',    // yellow
  _ => '  ',                         // dimmed, non-idle
};
```

## Configuration

New field in `GlueConfig`:
- `bashMaxLines` (int, default: 50) — max output lines shown for blocking bash commands

Resolved from config file (`~/.glue/config.yaml`) under `bash.max_lines`, with default fallback.

## `/jobs` Command (Future)

Not in initial implementation scope, but designed for:
- `/jobs` — list all background jobs with status
- `/jobs <id>` — view buffered output for a job
- `/jobs kill <id>` — terminate a job

## Data Flow

```
User types "!" at pos 0
  → App intercepts, sets _bashMode = true, prompt changes

User types "git push" + Enter
  → LineEditor.submit → UserSubmit("git push")
  → App checks _bashMode → run blocking shell command
  → AppMode.bashRunning, process starts
  → stdout/stderr collected, ANSI stripped, truncated
  → _ConversationEntry.bash("git push", output) added
  → AppMode.idle

User types "& npm run dev" + Enter (in bash mode)
  → UserSubmit("& npm run dev")
  → App checks _bashMode, detects "&" prefix
  → ShellJobManager.start("npm run dev")
  → System block: "Started job #1: npm run dev"
  → AppMode.idle (immediately, non-blocking)
  → Later: JobExited event → system block notification
```

## _ConversationEntry Changes

```dart
enum _EntryKind { user, assistant, toolCall, toolResult, error, system, subagent, bash }
```

New factory:
```dart
factory _ConversationEntry.bash(String command, String output) =>
    _ConversationEntry._(_EntryKind.bash, output, expandedText: command);
```

The `expandedText` field (already exists, currently used for user entries with @file expansion) stores the command for the legend. `text` holds the output.

## File Changes

| File | Change |
|---|---|
| `lib/src/app.dart` | `_bashMode` field, mode switching in `_handleTerminalEvent`, bash submit handling in `_handleAppEvent`, `AppMode.bashRunning`, `_bashRunProcess`, double-tap Ctrl+C logic, `_jobManager` field, prompt rendering |
| `lib/src/rendering/block_renderer.dart` | `renderBash(String command, String output)` method |
| `lib/src/shell/shell_job_manager.dart` | **New** — `ShellJob`, `ShellJobManager`, `JobStatus`, `JobEvent` sealed class, `LineRingBuffer` |
| `lib/src/config/glue_config.dart` | `bashMaxLines` field |
| `lib/glue.dart` | Export new types |
| `test/rendering/block_renderer_test.dart` | Tests for `renderBash` |
| `test/shell/shell_job_manager_test.dart` | **New** — ring buffer, job lifecycle, shutdown cleanup |

## Edge Cases

| Situation | Handling |
|---|---|
| Empty submit in bash mode | Ignore (no-op), stay in bash mode |
| `&` with no command after it | Ignore (no-op) |
| Command produces no output | Show empty box with just the command legend |
| Command produces massive output | Tail to `bashMaxLines`, show truncation notice |
| Background job output floods memory | `LineRingBuffer` caps at 2000 lines / 256KB |
| Glue exits with running jobs | SIGTERM → 800ms → SIGKILL |
| `!` typed mid-buffer (not at pos 0) | Normal character insertion, no mode switch |
| Backspace at pos 0 in normal mode | Normal behavior (no-op in LineEditor) |
