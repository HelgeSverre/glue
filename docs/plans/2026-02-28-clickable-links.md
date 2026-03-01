# Clickable Links Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make URLs, markdown links, and file paths in Glue's terminal output clickable using the OSC 8 hyperlink protocol, and linkify content in the web UI.

**Architecture:** Add an `osc8` helper function that wraps text in OSC 8 escape sequences. Update `stripAnsi`/`visibleLength`/`ansiTruncate`/`ansiWrap` to handle OSC 8 as zero-width sequences. Modify `MarkdownRenderer` to emit OSC 8 links for markdown links and bare URLs. Modify `BlockRenderer` to linkify file paths in tool results. Add a JS linkify function in the web UI's `app.html`.

**Tech Stack:** Dart (terminal CLI), vanilla JS/Alpine.js (web UI), ANSI OSC 8 escape sequences.

**Dependencies:** PR #2 (text wrapping) modifies `MarkdownRenderer` and `ansi_utils.dart`. This plan is written against the current `main` branch code. The implementation must be rebased onto PR #2 before merging if PR #2 lands first. Tasks 1-3 are foundational and don't conflict with PR #2. Tasks 4-5 touch the same files as PR #2 and will need a simple rebase.

---

## Background

### OSC 8 Terminal Hyperlink Protocol

Modern terminals (iTerm2, Ghostty, Kitty, WezTerm, Windows Terminal, GNOME Terminal 3.26+) support clickable hyperlinks via:

```
\x1b]8;;URL\x07VISIBLE_TEXT\x1b]8;;\x07
```

- `\x1b]8;;URL\x07` — opens a hyperlink (BEL-terminated)
- `VISIBLE_TEXT` — the text the user sees and can click
- `\x1b]8;;\x07` — closes the hyperlink

The visible text is what counts for column width. The escape sequences are zero-width. Terminals that don't support OSC 8 simply ignore the sequences and show the visible text — graceful degradation.

### Current ANSI Handling

`stripAnsi()` currently only strips CSI sequences (`\x1b[...letter`). It does NOT strip OSC sequences. This means `visibleLength()`, `ansiTruncate()`, and `ansiWrap()` would all break if we introduced OSC 8 without updating them.

### Current Link Rendering

`MarkdownRenderer._renderInlineSegment()` (line 154-158) converts `[text](url)` to `text (url)` in dimmed gray. No bare URL detection exists.

---

## Task 1: OSC 8 Helper and ANSI Utils Foundation

**Files:**
- Modify: `cli/lib/src/rendering/ansi_utils.dart`
- Test: `cli/test/ansi_utils_test.dart`

### Step 1: Write failing tests for OSC 8 helper

Add a new test group at the end of `cli/test/ansi_utils_test.dart`. If this file doesn't exist yet (it's added by PR #2), create it.

```dart
import 'package:glue/glue.dart';
import 'package:test/test.dart';

// ... existing tests ...

group('osc8Link', () {
  test('wraps text with OSC 8 escape sequences', () {
    final result = osc8Link('https://example.com', 'click here');
    expect(result, '\x1b]8;;https://example.com\x07click here\x1b]8;;\x07');
  });

  test('uses url as text when text is omitted', () {
    final result = osc8Link('https://example.com');
    expect(result, '\x1b]8;;https://example.com\x07https://example.com\x1b]8;;\x07');
  });
});
```

### Step 2: Run tests to verify they fail

Run: `cd cli && dart test test/ansi_utils_test.dart`
Expected: FAIL — `osc8Link` not defined.

### Step 3: Implement `osc8Link`

In `cli/lib/src/rendering/ansi_utils.dart`, add at the top of the file (after the imports):

```dart
/// Wrap [text] in an OSC 8 terminal hyperlink pointing to [url].
///
/// Modern terminals (iTerm2, Ghostty, Kitty, WezTerm, Windows Terminal)
/// render this as a clickable link. Terminals that don't support OSC 8
/// simply show the visible text — graceful degradation.
///
/// Protocol: \x1b]8;;URL\x07VISIBLE_TEXT\x1b]8;;\x07
String osc8Link(String url, [String? text]) {
  final display = text ?? url;
  return '\x1b]8;;$url\x07$display\x1b]8;;\x07';
}
```

### Step 4: Run tests to verify they pass

Run: `cd cli && dart test test/ansi_utils_test.dart`
Expected: PASS

### Step 5: Commit

```bash
git add cli/lib/src/rendering/ansi_utils.dart cli/test/ansi_utils_test.dart
git commit -m "feat: add osc8Link helper for terminal hyperlinks"
```

---

## Task 2: Update `stripAnsi` and `visibleLength` to Handle OSC 8

**Files:**
- Modify: `cli/lib/src/rendering/ansi_utils.dart`
- Test: `cli/test/ansi_utils_test.dart`

### Step 1: Write failing tests for OSC 8 stripping

Add to the `stripAnsi` test group in `cli/test/ansi_utils_test.dart`:

```dart
test('strips OSC 8 hyperlink sequences', () {
  final linked = '\x1b]8;;https://example.com\x07click\x1b]8;;\x07';
  expect(stripAnsi(linked), 'click');
});

test('strips OSC 8 mixed with CSI sequences', () {
  final text = '\x1b[1m\x1b]8;;https://x.com\x07bold link\x1b]8;;\x07\x1b[22m';
  expect(stripAnsi(text), 'bold link');
});
```

Add to the `visibleLength` test group:

```dart
test('OSC 8 link sequences are zero-width', () {
  final linked = '\x1b]8;;https://example.com\x07click\x1b]8;;\x07';
  expect(visibleLength(linked), 5); // "click" is 5 chars
});

test('OSC 8 link with surrounding text', () {
  final text = 'see \x1b]8;;https://x.com\x07here\x1b]8;;\x07 for info';
  expect(visibleLength(text), 18); // "see here for info"
});
```

### Step 2: Run tests to verify they fail

Run: `cd cli && dart test test/ansi_utils_test.dart`
Expected: FAIL — `stripAnsi` doesn't strip OSC sequences, so `visibleLength` counts them.

### Step 3: Update `stripAnsi` to handle OSC sequences

In `cli/lib/src/rendering/ansi_utils.dart`, replace the `stripAnsi` function:

```dart
/// Strip all ANSI escape sequences from [text], including both
/// CSI sequences (\x1b[...letter) and OSC sequences (\x1b]...BEL/ST).
String stripAnsi(String text) {
  return text
      .replaceAll(RegExp(r'\x1b\][^\x07]*\x07'), '') // OSC (BEL-terminated)
      .replaceAll(RegExp(r'\x1b\[[0-9;]*[a-zA-Z]'), ''); // CSI
}
```

### Step 4: Run tests to verify they pass

Run: `cd cli && dart test test/ansi_utils_test.dart`
Expected: PASS

### Step 5: Commit

```bash
git add cli/lib/src/rendering/ansi_utils.dart cli/test/ansi_utils_test.dart
git commit -m "feat: update stripAnsi/visibleLength to handle OSC 8 sequences"
```

---

## Task 3: Update `ansiTruncate` and `ansiWrap` for OSC 8

**Files:**
- Modify: `cli/lib/src/rendering/ansi_utils.dart`
- Test: `cli/test/ansi_utils_test.dart`

OSC 8 sequences must be treated as zero-width by `ansiTruncate` (just like CSI). The regex-based matching in `ansiTruncate` currently only skips CSI patterns. We need it to also skip OSC patterns.

### Step 1: Write failing tests for truncation with OSC 8

Add to the `ansiTruncate` test group:

```dart
test('truncation preserves OSC 8 link when text fits', () {
  final linked = '\x1b]8;;https://x.com\x07click\x1b]8;;\x07';
  final result = ansiTruncate(linked, 10);
  expect(result, linked); // 5 visible chars fits in 10
});

test('truncation handles OSC 8 link in longer text', () {
  final text = 'see \x1b]8;;https://x.com\x07link\x1b]8;;\x07 and more text here';
  final result = ansiTruncate(text, 12);
  expect(visibleLength(result), lessThanOrEqualTo(12));
  expect(stripAnsi(result), startsWith('see '));
});
```

Add to the `ansiWrap` test group:

```dart
test('wrapping preserves OSC 8 links', () {
  final text = 'see \x1b]8;;https://x.com\x07link\x1b]8;;\x07 end';
  final result = ansiWrap(text, 80);
  expect(result, text); // fits on one line
});
```

### Step 2: Run tests to verify they fail

Run: `cd cli && dart test test/ansi_utils_test.dart`
Expected: FAIL — `ansiTruncate` doesn't know about OSC sequences and counts them as visible characters.

### Step 3: Update `ansiTruncate` to skip OSC sequences

In `ansiTruncate`, the inner loop uses `ansiPattern.matchAsPrefix(text, i)` to skip CSI sequences. Add a second pattern match for OSC sequences. Replace the `ansiTruncate` function:

```dart
/// Truncate [text] to [maxVisible] visible columns, preserving ANSI
/// sequences (both CSI and OSC) and handling wide characters. Appends '…' if truncated.
String ansiTruncate(String text, int maxVisible) {
  if (visibleLength(text) <= maxVisible) return text;
  final buf = StringBuffer();
  int visible = 0;
  final csiPattern = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]');
  final oscPattern = RegExp(r'\x1b\][^\x07]*\x07');
  var i = 0;
  while (i < text.length && visible < maxVisible - 1) {
    // Skip CSI sequences
    final csiMatch = csiPattern.matchAsPrefix(text, i);
    if (csiMatch != null) {
      buf.write(csiMatch.group(0));
      i += csiMatch.group(0)!.length;
      continue;
    }
    // Skip OSC sequences
    final oscMatch = oscPattern.matchAsPrefix(text, i);
    if (oscMatch != null) {
      buf.write(oscMatch.group(0));
      i += oscMatch.group(0)!.length;
      continue;
    }
    final codeUnit = text.codeUnitAt(i);
    int cp;
    int advance;
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && i + 1 < text.length) {
      final low = text.codeUnitAt(i + 1);
      cp = 0x10000 + ((codeUnit - 0xD800) << 10) + (low - 0xDC00);
      advance = 2;
    } else {
      cp = codeUnit;
      advance = 1;
    }
    final w = _charWidth(cp);
    if (w == 0) {
      buf.write(text.substring(i, i + advance));
      i += advance;
      continue;
    }
    if (visible + w > maxVisible - 1) break;
    buf.write(text.substring(i, i + advance));
    visible += w;
    i += advance;
  }
  buf.write('…');
  return buf.toString();
}
```

### Step 4: Run tests to verify they pass

Run: `cd cli && dart test test/ansi_utils_test.dart`
Expected: PASS

### Step 5: Commit

```bash
git add cli/lib/src/rendering/ansi_utils.dart cli/test/ansi_utils_test.dart
git commit -m "feat: update ansiTruncate to handle OSC 8 sequences"
```

---

## Task 4: Linkify Markdown Links and Bare URLs in MarkdownRenderer

**Files:**
- Modify: `cli/lib/src/rendering/markdown_renderer.dart`
- Test: `cli/test/markdown_renderer_test.dart`

### Step 1: Write failing tests for OSC 8 markdown links

Add to `cli/test/markdown_renderer_test.dart`, in the `inline styles` group:

```dart
test('markdown links render as OSC 8 hyperlinks', () {
  final result = renderer.render('[click](https://example.com)');
  // Should contain OSC 8 open sequence with URL
  expect(result, contains('\x1b]8;;https://example.com\x07'));
  // Should contain the visible text
  expect(result, contains('click'));
  // Should contain OSC 8 close sequence
  expect(result, contains('\x1b]8;;\x07'));
});
```

Add a new group for bare URL detection:

```dart
group('bare URLs', () {
  test('https URLs become OSC 8 links', () {
    final result = renderer.render('Visit https://example.com for info');
    expect(result, contains('\x1b]8;;https://example.com\x07'));
    expect(result, contains('https://example.com'));
    expect(result, contains('\x1b]8;;\x07'));
  });

  test('http URLs become OSC 8 links', () {
    final result = renderer.render('See http://example.com/path');
    expect(result, contains('\x1b]8;;http://example.com/path\x07'));
  });

  test('URLs with query strings and fragments', () {
    final result = renderer.render('Go to https://example.com/page?q=1&b=2#top');
    expect(result, contains('\x1b]8;;https://example.com/page?q=1&b=2#top\x07'));
  });

  test('URL followed by punctuation does not include trailing period', () {
    final result = renderer.render('See https://example.com.');
    expect(result, contains('\x1b]8;;https://example.com\x07'));
    // The period should be outside the link
    final stripped = stripAnsi(result);
    expect(stripped, endsWith('.'));
  });

  test('URL followed by comma does not include trailing comma', () {
    final result = renderer.render('Visit https://example.com, then');
    expect(result, contains('\x1b]8;;https://example.com\x07'));
  });

  test('URL in parentheses does not include trailing paren', () {
    final result = renderer.render('(see https://example.com)');
    expect(result, contains('\x1b]8;;https://example.com\x07'));
  });

  test('URLs inside markdown links are NOT double-linked', () {
    final result = renderer.render('[click](https://example.com)');
    // Count OSC 8 opens — should be exactly 1
    final opens = '\x1b]8;;https://example.com\x07'.allMatches(result).length;
    expect(opens, 1);
  });

  test('bare URL is not linkified inside code span', () {
    final result = renderer.render('Run `https://example.com` as test');
    // Inside inline code, URLs should stay as plain text
    expect(result, isNot(contains('\x1b]8;;')));
  });
});
```

### Step 2: Run tests to verify they fail

Run: `cd cli && dart test test/markdown_renderer_test.dart`
Expected: FAIL — current implementation doesn't emit OSC 8 sequences.

### Step 3: Update the existing link test

The existing link test (line 53-57) expects `(https://example.com)` in parens. Update it:

```dart
test('links render as OSC 8 hyperlinks', () {
  final result = renderer.render('[click](https://example.com)');
  expect(result, contains('\x1b]8;;https://example.com\x07'));
  expect(result, contains('click'));
  expect(result, contains('\x1b]8;;\x07'));
});
```

### Step 4: Implement OSC 8 links and bare URL detection

In `cli/lib/src/rendering/markdown_renderer.dart`, add import at top:

```dart
import 'ansi_utils.dart';
```

(This import already exists.)

Add a static regex for bare URLs as a class field:

```dart
class MarkdownRenderer {
  final int width;

  static final _tableRowPattern = RegExp(r'^\s*\|.*\|\s*$');
  static final _tableSepPattern = RegExp(r'^\s*\|[\s:?\-|]+\|\s*$');
  static final _bareUrlPattern = RegExp(
    r'https?://[^\s<>\[\])`''"]+',
  );

  // ... rest of class
```

Update `_renderInlineSegment` to use OSC 8 for markdown links and add bare URL detection:

```dart
String _renderInlineSegment(String text) {
  // Bold: **text**
  text = text.replaceAllMapped(
    RegExp(r'\*\*(.+?)\*\*'),
    (m) => '\x1b[1m${m.group(1)}\x1b[22m',
  );
  // Italic: *text* (but not inside **)
  text = text.replaceAllMapped(
    RegExp(r'(?<!\*)\*([^*]+?)\*(?!\*)'),
    (m) => '\x1b[3m${m.group(1)}\x1b[23m',
  );
  // Links: [text](url) → OSC 8 clickable link, underlined
  text = text.replaceAllMapped(
    RegExp(r'\[(.+?)\]\((.+?)\)'),
    (m) => '\x1b[4m${osc8Link(m.group(2)!, m.group(1))}\x1b[24m',
  );
  // Bare URLs: https://... and http://...
  text = text.replaceAllMapped(
    _bareUrlPattern,
    (m) {
      var url = m.group(0)!;
      // Strip trailing punctuation that's likely not part of the URL
      var suffix = '';
      while (url.isNotEmpty && '.,;:!?)'.contains(url[url.length - 1])) {
        suffix = url[url.length - 1] + suffix;
        url = url.substring(0, url.length - 1);
      }
      return '${osc8Link(url)}\x1b[0m$suffix';
    },
  );
  return text;
}
```

### Step 5: Run tests to verify they pass

Run: `cd cli && dart test test/markdown_renderer_test.dart`
Expected: PASS

### Step 6: Run full test suite

Run: `cd cli && dart test`
Expected: All tests pass.

### Step 7: Commit

```bash
git add cli/lib/src/rendering/markdown_renderer.dart cli/test/markdown_renderer_test.dart
git commit -m "feat: render markdown links and bare URLs as clickable OSC 8 hyperlinks"
```

---

## Task 5: Linkify File Paths in Tool Results

**Files:**
- Modify: `cli/lib/src/rendering/block_renderer.dart`
- Test: `cli/test/block_renderer_test.dart` (create if needed)

### Step 1: Write failing tests for file path linkification

Create `cli/test/block_renderer_test.dart`:

```dart
import 'package:glue/glue.dart';
import 'package:test/test.dart';

void main() {
  late BlockRenderer renderer;

  setUp(() {
    renderer = BlockRenderer(80);
  });

  group('renderToolCall file path links', () {
    test('tool call with file path arg wraps in OSC 8 file:// link', () {
      final result = renderer.renderToolCall('read_file', {'path': '/src/main.dart'});
      expect(result, contains('\x1b]8;;file:///src/main.dart\x07'));
      expect(result, contains('/src/main.dart'));
      expect(result, contains('\x1b]8;;\x07'));
    });

    test('tool call without path arg renders normally', () {
      final result = renderer.renderToolCall('bash', {'command': 'ls -la'});
      expect(result, isNot(contains('\x1b]8;;file://')));
    });
  });

  group('renderToolResult grep output links', () {
    test('grep-style file:line output gets file path linked', () {
      final result = renderer.renderToolResult('src/main.dart:42:  print("hello");');
      expect(result, contains('\x1b]8;;file://src/main.dart\x07'));
    });
  });
}
```

### Step 2: Run tests to verify they fail

Run: `cd cli && dart test test/block_renderer_test.dart`
Expected: FAIL — no file path linkification exists.

### Step 3: Implement file path linkification in BlockRenderer

In `cli/lib/src/rendering/block_renderer.dart`, add a static regex and helper:

```dart
import 'ansi_utils.dart';
import 'markdown_renderer.dart';

class BlockRenderer {
  final int width;
  int get _inner => (width - 2).clamp(1, width);

  /// Matches grep-style output: file:line:content
  static final _grepLinePattern = RegExp(r'^(\S+?):(\d+):');

  BlockRenderer(this.width);

  /// Wrap a file path in an OSC 8 file:// hyperlink.
  String _linkPath(String path) {
    final uri = path.startsWith('/') ? 'file://$path' : 'file://$path';
    return osc8Link(uri, path);
  }

  // ... existing methods ...
```

Update `renderToolCall` to linkify the `path` argument:

```dart
String renderToolCall(String name, Map<String, dynamic>? args) {
  final header = ' \x1b[1m\x1b[33m▶ Tool: $name\x1b[0m';
  if (args == null || args.isEmpty) return header;
  final argsStr = args.entries.map((e) {
    final val = '${e.value}';
    final display = ansiTruncate(val, _inner - 6);
    if (e.key == 'path') {
      return '${e.key}: ${_linkPath(display)}';
    }
    return '${e.key}: $display';
  }).join(', ');
  return '$header\n    \x1b[90m$argsStr\x1b[0m';
}
```

Update `renderToolResult` to linkify grep-style file:line patterns:

```dart
String renderToolResult(String content, {bool success = true}) {
  final icon = success ? '✓' : '✗';
  final color = success ? '\x1b[32m' : '\x1b[31m';
  final header = ' \x1b[1m$color$icon Tool result\x1b[0m';
  final truncated = _truncateLines(content, 20, _inner - 2);
  final lines = truncated.split('\n');
  final linked = lines.map((l) {
    final m = _grepLinePattern.firstMatch(l);
    if (m != null) {
      final path = m.group(1)!;
      final rest = l.substring(m.start + path.length);
      return '${_linkPath(path)}$rest';
    }
    return l;
  });
  final indented =
      linked.map((l) => '    \x1b[90m$l\x1b[0m').join('\n');
  return '$header\n$indented';
}
```

### Step 4: Run tests to verify they pass

Run: `cd cli && dart test test/block_renderer_test.dart`
Expected: PASS

### Step 5: Run full test suite

Run: `cd cli && dart test`
Expected: All tests pass.

### Step 6: Commit

```bash
git add cli/lib/src/rendering/block_renderer.dart cli/test/block_renderer_test.dart
git commit -m "feat: linkify file paths in tool calls and grep results via OSC 8"
```

---

## Task 6: Web UI Linkification

**Files:**
- Modify: `website/app.html`

This is a simpler task — the web UI uses `x-html` for assistant text, so we can process markdown links and bare URLs into `<a>` tags.

### Step 1: Add a linkify function to the Alpine.js app

In `website/app.html`, add a `linkify` method to the `glue()` function (inside the return object, after `sendMessage`):

```javascript
linkify(text) {
  if (!text) return text;
  // Markdown links: [text](url) → <a>
  text = text.replace(/\[(.+?)\]\((.+?)\)/g,
    '<a href="$2" target="_blank" rel="noopener" style="color:var(--yellow);text-decoration:underline;text-underline-offset:2px">$1</a>');
  // Bare URLs (not already inside href="...")
  text = text.replace(/(^|[^"=])(https?:\/\/[^\s<>\[\])`'"]+?)([.,;:!?)]*(?=\s|$))/g,
    '$1<a href="$2" target="_blank" rel="noopener" style="color:var(--yellow);text-decoration:underline;text-underline-offset:2px">$2</a>$3');
  return text;
},
```

### Step 2: Use linkify in assistant block rendering

In `app.html`, change the assistant template (around line 296) from:

```html
<div class="t-assistant" x-html="block.text + (block.streaming ? '<span class=\'t-cursor\'></span>' : '')"></div>
```

To:

```html
<div class="t-assistant" x-html="linkify(block.text) + (block.streaming ? '<span class=\'t-cursor\'></span>' : '')"></div>
```

### Step 3: Test manually

Open `website/app.html` in a browser. The mock session data contains assistant text. Verify:
- Any URLs in assistant responses are rendered as yellow underlined clickable links
- Links open in a new tab
- No broken HTML rendering

### Step 4: Commit

```bash
git add website/app.html
git commit -m "feat: linkify URLs and markdown links in web UI assistant output"
```

---

## Task 7: Export `osc8Link` and Final Cleanup

**Files:**
- Modify: `cli/lib/glue.dart`

### Step 1: Add `osc8Link` to the public export

In `cli/lib/glue.dart`, update the `ansi_utils.dart` export line to include `osc8Link`:

Current (or after PR #2):
```dart
export 'src/rendering/ansi_utils.dart'
    show stripAnsi, visibleLength, ansiTruncate, ansiWrap;
```

Change to:
```dart
export 'src/rendering/ansi_utils.dart'
    show stripAnsi, visibleLength, ansiTruncate, ansiWrap, osc8Link;
```

(If PR #2 has landed, the line already includes `wrapIndented` — just add `osc8Link` to that list.)

### Step 2: Run full test suite

Run: `cd cli && dart test`
Expected: All tests pass.

### Step 3: Run dart analyze

Run: `cd cli && dart analyze`
Expected: No new issues (1 pre-existing lint is acceptable).

### Step 4: Commit

```bash
git add cli/lib/glue.dart
git commit -m "feat: export osc8Link from public API"
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `cli/lib/src/rendering/ansi_utils.dart` | Add `osc8Link()`, update `stripAnsi()` for OSC, update `ansiTruncate()` for OSC |
| `cli/lib/src/rendering/markdown_renderer.dart` | Use OSC 8 for `[text](url)`, add bare URL detection |
| `cli/lib/src/rendering/block_renderer.dart` | Linkify `path` args in tool calls, linkify grep-style file:line patterns |
| `cli/lib/glue.dart` | Export `osc8Link` |
| `cli/test/ansi_utils_test.dart` | Tests for `osc8Link`, OSC 8 stripping, truncation |
| `cli/test/markdown_renderer_test.dart` | Tests for OSC 8 links, bare URL detection |
| `cli/test/block_renderer_test.dart` | Tests for file path linkification |
| `website/app.html` | JS `linkify()` function, use in assistant blocks |

## Rebase Notes

If PR #2 (text wrapping) merges before this work:
- Tasks 1-3 have **no conflicts** (they touch different parts of `ansi_utils.dart`)
- Task 4 will need a minor rebase since PR #2 changes `_renderInlineSegment` indirectly (the wrapping logic changes). The actual link regex replacement code is the same — just resolve any context conflicts
- The `glue.dart` export line will need to include both `wrapIndented` and `osc8Link`
