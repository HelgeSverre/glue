# Status Bar Redesign — Dim Gray + Reordered Segments

**Goal:** Replace the current black-on-yellow status bar with a dim gray background / white text style, highlight the model name in bold yellow, and reorder segments to: scroll indicator → mode → pwd → model (bold white) → tokens.

**Scope:** Cosmetic only. No behavioral changes, no new state, no new config. Three files touched.

---

## Current State

```
 ● Generating  ·  claude-opus-4-5  ·  [ask]  ·  ~/code/glue  ·  ↑3  ·  1,240 tokens
└─ black text on yellow bg (\x1b[30;43m) ──────────────────────────────────────────────┘
```

Segments (right side, left-to-right):

1. Model ID
2. Approval mode label
3. Shortened cwd
4. Scroll offset (conditional)
5. Token count

---

## Target State

```
 ● Generating    ↑3  ·  [ask]  ·  ~/code/glue  ·  claude-opus-4-5  ·  1,240 tokens
└─ dim gray bg, white text — model in bold yellow ─────────────────────────────────────┘
```

Segments (right side, left-to-right):

1. Scroll offset (conditional, always first when present)
2. Approval mode label
3. Shortened cwd
4. Model ID — **bold yellow**
5. Token count

---

## Changes Required

### 1. `cli/lib/src/terminal/terminal.dart` — add named constants

Add two new statics to `AnsiStyle` alongside the existing set:

```dart
// Background colors (256-color palette)
static const statusBar = AnsiStyle('\x1b[2;37;48;5;238m', '\x1b[0m');
//                                      │  │  └── bg: color 238 (dark gray)
//                                      │  └──── fg: 37 = white
//                                      └─────── 2 = dim

static const boldYellow = AnsiStyle('\x1b[1;33m', '\x1b[22;39m');
//                                      │  └── fg: 33 = yellow
//                                      └──── 1 = bold
//                                  close resets bold (22) and fg (39) independently
```

Why named constants rather than inline literals? The existing `\x1b[30;43m` in `layout.dart` is already a smell — the rest of the codebase uses `AnsiStyle.foo`. This finishes the job.

Why `48;5;238` for gray background? The basic ANSI background colors (`40`–`47`) don't include a dark gray that reads well. Color 238 (`#444444` in most terminals) is the standard choice for muted status bars and is universally supported in modern terminals (iTerm2, Ghostty, Kitty, WezTerm, Terminal.app).

Why `2;37` for dim white foreground? `37` is standard white (not `97` bright-white) combined with `2` (dim) to knock it back slightly relative to main output text, making the bar feel "below the fold" visually without being illegible.

---

### 2. `cli/lib/src/terminal/layout.dart` — use the new constant

**Line 207** — swap the hardcoded style:

```dart
// Before
style: const AnsiStyle('\x1b[30;43m', '\x1b[0m'),

// After
style: AnsiStyle.statusBar,
```

No other changes in this file. `paintStatus` already handles `visibleLength`/padding correctly — the 256-color background sequence (`\x1b[48;5;238m`) is matched by `_csiPattern = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]')` in `ansi_utils.dart` so stripping and length accounting work as-is.

---

### 3. `cli/lib/src/app/render_pipeline.dart` — reorder segments + style model

**Lines ~155–170** — the status bar assembly block. Full before/after:

```dart
// ── BEFORE ──────────────────────────────────────────────────────────────────
const sep = ' · ';
final scrollSeg = app._scrollOffset > 0 ? '↑${app._scrollOffset}' : null;
final rightSegs = [
  app._modelId,
  modeLabel,
  shortCwd,
  if (scrollSeg != null) scrollSeg,
  '${app.agent.tokenCount} tokens',
];
final statusRight = ' ${rightSegs.join(sep)} ';

// ── AFTER ────────────────────────────────────────────────────────────────────
const sep = ' · ';
final scrollSeg = app._scrollOffset > 0 ? '↑${app._scrollOffset}' : null;
final modelSeg =
    '${AnsiStyle.boldYellow.open}${app._modelId}${AnsiStyle.boldYellow.close}';
final rightSegs = [
  if (scrollSeg != null) scrollSeg,
  modeLabel,
  shortCwd,
  modelSeg,
  '${app.agent.tokenCount} tokens',
];
final statusRight = ' ${rightSegs.join(sep)} ';
```

Key points:

- `scrollSeg` moves to **first** position (was last, and conditional).
- `modelSeg` wraps `app._modelId` in `boldYellow` open/close. `visibleLength` in `paintStatus` already strips ANSI before measuring, so the padding math stays correct.
- `modeLabel` and `shortCwd` stay but reorder: mode before pwd.
- No other logic changes — `statusLeft` (the mode indicator with its existing inline bold) is untouched.

---

## Files Summary

| File                                   | Lines changed | Nature                                               |
| -------------------------------------- | ------------- | ---------------------------------------------------- |
| `cli/lib/src/terminal/terminal.dart`   | ~2            | Add `AnsiStyle.statusBar` and `AnsiStyle.boldYellow` |
| `cli/lib/src/terminal/layout.dart`     | ~1            | Replace inline literal with `AnsiStyle.statusBar`    |
| `cli/lib/src/app/render_pipeline.dart` | ~8            | Reorder segments, wrap model in `boldYellow`         |

No new tests required — this is pure rendering/cosmetic with no logic branches. The existing render pipeline tests (if any) continue to pass; the status bar content is not currently covered by unit tests.

---

## Implementation Checklist

- [ ] Add `AnsiStyle.statusBar` to `terminal.dart`
- [ ] Add `AnsiStyle.boldYellow` to `terminal.dart`
- [ ] Replace `'\x1b[30;43m'` literal in `layout.dart` with `AnsiStyle.statusBar`
- [ ] Reorder `rightSegs` in `render_pipeline.dart`
- [ ] Wrap `app._modelId` in `boldYellow` in `render_pipeline.dart`
- [ ] Run `dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test`
- [ ] Visual check in terminal: confirm bar is gray, model is bold yellow, scroll indicator appears first
