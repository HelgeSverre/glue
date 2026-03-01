# Status Line Improvements

## Current State

The status bar is built as two concatenated strings joined with padding:

```dart
final statusLeft = ' $modeIndicator  $_modelName  $shortCwd';
final statusRight = '${scrollIndicator}tok ${agent.tokenCount} ';
layout.paintStatus(statusLeft, statusRight);
```

**Problems:**

- `statusLeft` is a single flat string — when `modeIndicator` changes width
  (`"Ready"` → `"⚙ Tool"` → `"? Approve"`), everything to its right shifts.
- No visual separation between semantic groups — model, cwd, and mode bleed together.
- Everything is plain black-on-yellow (`\x1b[30;43m`). Dark black on yellow is
  hard to read; dim text is worse. Nothing is emphasised.

Current layout (approximate):

```
 Ready  claude-3-5-sonnet-20241022  ~/code/glue/cli        ↑12  tok 4231
```

---

## Chosen Direction: Semantic Grouping with Separators

Left-align the mode indicator (the most important at-a-glance state).
Right-align everything else (model, cwd, scroll position, token count),
separated by `│` so each group is visually distinct and independently readable.

```
 ❯ Ready          │ claude-sonnet-3-5 │ ~/code/glue/cli │ ↑3 │ tok 4.2k
```

- Mode is **bold** — highest contrast against yellow, immediately scannable.
- Separators and secondary labels (model, cwd, tok) use regular black.
- Token count formatted as `4.2k` / `12k` to save horizontal space.
- Scroll indicator only appears when scrolled, slotted between cwd and tokens
  so tokens stay anchored to the right edge.

---

## Layout Anatomy

```
┌──────────────────────────────────────────────────────────────────────┐
│ BOLD: mode        │ model │ cwd (truncated)    │ ↑N │ tok 4.2k      │
│ ←── left ────────────────────────────────────────── right ─────────→ │
└──────────────────────────────────────────────────────────────────────┘
```

**Left section** (left-aligned, fixed to mode only):

- `❯ Ready` — bold black on yellow (`\x1b[1;30m`)
- Mode labels: `❯ Ready` / `⠋ Generating` / `⚙ Tool` / `? Approve` / `! Running`

**Right section** (right-aligned, joined by `│`):

- Model name (short form preferred, e.g. `sonnet-3-5` not full ID)
- CWD (shortened, truncated with `…` if tight)
- Scroll offset `↑3` (omitted when at bottom)
- Token count `tok 4.2k`

---

## Typography / ANSI

The status bar base style is `\x1b[30;43m` (black fg, yellow bg).

| Element       | Style                           | ANSI              |
| ------------- | ------------------------------- | ----------------- |
| Mode label    | **Bold black** on yellow        | `\x1b[1;30m`      |
| Separator `│` | Regular black (slightly dimmer) | `\x1b[30m` (base) |
| Model name    | Regular black                   | `\x1b[30m` (base) |
| CWD           | Regular black                   | `\x1b[30m` (base) |
| Scroll `↑N`   | Regular black                   | `\x1b[30m` (base) |
| Token count   | Regular black                   | `\x1b[30m` (base) |

Inline style resets back to base (`\x1b[30;43m`) after each bold segment so
the yellow background is never broken.

---

## Implementation Notes

### `paintStatus` in `layout.dart`

Change signature from `(String left, String right)` to
`(String content, int leftVisible, int rightVisible)` so the caller
pre-builds the full ANSI string and provides visible widths for padding:

```dart
void paintStatus(String content, int leftVisible, int rightVisible) {
  terminal.moveTo(statusRow, 1);
  terminal.clearLine();
  final padding = terminal.columns - leftVisible - rightVisible;
  terminal.write(
    '\x1b[30;43m$content${' ' * padding.clamp(0, 9999)}\x1b[0m',
  );
}
```

### Status build in `app.dart`

```dart
// Bold mode label (left)
const base = '\x1b[30;43m';
const bold = '\x1b[1;30;43m';
const sep  = ' │ ';

final modeLabel = switch (_mode) {
  AppMode.idle        => '❯ Ready',
  AppMode.streaming   => '${_spinnerFrames[_spinnerFrame]} Generating',
  AppMode.toolRunning => '⚙ Tool',
  AppMode.confirming  => '? Approve',
  AppMode.bashRunning => '! Running',
};

final leftContent = ' $bold$modeLabel$base ';
final leftVisible = 1 + visibleLength(modeLabel) + 1; // spaces

// Right segments
final shortModel = _shortModelName(_modelName); // e.g. "sonnet-3-5"
final scrollSeg  = _scrollOffset > 0 ? '↑$_scrollOffset' : null;
final tokSeg     = 'tok ${_formatTokens(agent.tokenCount)}';

final rightSegments = [
  shortModel,
  ansiTruncate(shortCwd, 30),
  if (scrollSeg != null) scrollSeg,
  tokSeg,
];
final rightContent = '${rightSegments.join(sep)} ';
final rightVisible = visibleLength(rightContent);

layout.paintStatus('$leftContent$base', leftVisible, rightVisible);
// then write right separately ... (see full impl)
```

Token formatter:

```dart
String _formatTokens(int n) =>
    n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
```

Short model name: strip provider prefix and date suffix, e.g.
`claude-3-5-sonnet-20241022` → `claude-3-5-sonnet`, `gpt-4o-mini` → `gpt-4o-mini`.

---

## Visual Examples

**Idle, no scroll, narrow terminal (80 cols):**

```
 ❯ Ready           │ sonnet-3-5 │ ~/code/glue/cli │ tok 1.2k
```

**Streaming, scrolled, wide terminal (160 cols):**

```
 ⠋ Generating      │ gpt-4o │ ~/code/my-very-long-project-name/src │ ↑24 │ tok 8.7k
```

**Confirming tool approval:**

```
 ? Approve         │ sonnet-3-5 │ ~/code/glue/cli │ tok 3.4k
```

**Bash mode running:**

```
 ! Running         │ sonnet-3-5 │ ~/code/glue/cli │ tok 5.1k
```
