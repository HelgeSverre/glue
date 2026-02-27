# Plan: `@filepath` File Reference Expansion

## Overview

Allow users to type `@path/to/file` in the input buffer and have it automatically
expanded to the file's contents before the message is sent to the agent. This is
purely a **pre-send transformation** — the LLM sees the file contents inline in the
user message.

Example:

```
> explain the bug in @lib/src/agent/agent_core.dart
```

Gets sent to the agent as:

````
explain the bug in

[lib/src/agent/agent_core.dart]
```dart
... full file contents ...
````

````

---

## Scope

- Expand one or more `@<path>` tokens anywhere in the user's message.
- Show a visual hint in the input area when a valid `@` path is detected.
- Gracefully handle missing files (leave the token unexpanded with an inline warning).
- No changes to the LLM pipeline, tool system, or storage layer.

---

## Implementation Steps

### 1. `FileExpander` utility — `lib/src/input/file_expander.dart`

A pure, stateless helper that does the actual expansion. Keeping it isolated makes
it easy to test independently.

```dart
// Finds all @<token> patterns in [input] where the token is a valid file path,
// reads each file, and returns the expanded string.
//
// Tokens that don't resolve to a readable file are left as-is with a trailing
// warning comment so the user (and LLM) know the file wasn't found.
String expandFileRefs(String input);

// Returns all @<token> substrings found in [input], regardless of whether
// the paths are valid. Used by the autocomplete/hint layer.
List<String> extractFileRefs(String input);
````

**Expansion format** per reference:

````
@lib/src/foo.dart          →     [lib/src/foo.dart]
                                 ```dart
                                 <file contents>
                                 ```
````

Rules:

- Token regex: `@([\w./\-]+)` — stops at whitespace and shell-special chars.
- Cap file size at **100 KB**; emit a warning and skip expansion if larger.
- Use the file extension to pick a fenced code-block language tag (`dart`, `json`,
  `yaml`, `md`, `sh`, etc.). Default to no tag for unknown extensions.

---

### 2. Expand on submit — `lib/src/app.dart`

In `_handleAppEvent`, transform the raw text before passing it to `_startAgent`:

```dart
case UserSubmit(:final text):
  if (text.startsWith('/')) {
    // slash commands unchanged
  } else {
    final expanded = expandFileRefs(text);   // ← new
    _startAgent(expanded);
  }
```

The raw (unexpanded) text is what goes into `editor.history` and the `user` block
rendered in the conversation — keep showing the original `@path` tokens to the
user rather than dumping hundreds of lines of code into the chat UI.

To do this, pass the **original** text to `_ConversationEntry.user()` and the
**expanded** text to `agent.run()`:

```dart
void _startAgent(String rawMessage, {String? expandedMessage}) {
  _blocks.add(_ConversationEntry.user(rawMessage));   // show raw
  final toSend = expandedMessage ?? rawMessage;
  ...
  final stream = agent.run(toSend);                  // send expanded
```

Update the call site accordingly.

---

### 3. `@`-path autocomplete hint — `lib/src/ui/at_file_hint.dart`

A lightweight companion to `SlashAutocomplete` that activates when the cursor is
immediately after a `@` token and shows filesystem completions.

```
State:
  bool active
  String currentPrefix     // the partial path after @
  List<String> matches     // up to 8 file/dir candidates

Methods:
  void update(String buffer, int cursor)
    — parse the token under/before the cursor; stat the prefix; populate matches
  void moveUp() / moveDown()
  String? accept()         // returns the completed path token
  void dismiss()
  List<String> render(int width)
  int get overlayHeight
```

Logic in `update`:

1. Walk backwards from `cursor` to find the start of a `@...` token.
2. Extract the partial path after `@`.
3. Split into `dir` + `prefix` (everything after the last `/`).
4. `Directory(dir).listSync()` filtered by `prefix`, sorted (dirs first).
5. Cap at 8 results; mark directories with a trailing `/`.

**Key difference from `SlashAutocomplete`**: activates mid-word, not only at the
start of the buffer.

---

### 4. Wire `AtFileHint` into `App` — `lib/src/app.dart`

- Instantiate `_atHint = AtFileHint()` alongside `_autocomplete`.
- In `_handleTerminalEvent`, after `editor.handle(event)`:
  - Call `_atHint.update(editor.text, editor.cursor)` on `InputAction.changed`.
  - Handle `Up`/`Down`/`Tab`/`Enter`/`Escape` for the hint overlay (same pattern
    as `SlashAutocomplete`).
  - On accept, call `editor.setText(editor.text.replaceRange(tokenStart, cursor,
accepted))`.
- In `_doRender`, paint the `AtFileHint` overlay via `layout.paintOverlay(...)` —
  same slot used by `SlashAutocomplete`. Only one overlay shows at a time:
  `SlashAutocomplete` wins if `buffer.startsWith('/')`.

---

### 5. Tests — `test/input/file_expander_test.dart`

| Test case                        | What it checks                           |
| -------------------------------- | ---------------------------------------- |
| Single `@path` expansion         | Token replaced with fenced file contents |
| Multiple tokens in one message   | All tokens expanded independently        |
| Missing file                     | Token left as-is, warning appended       |
| File too large (>100 KB)         | Token left as-is, size warning appended  |
| No `@` tokens                    | Input returned unchanged                 |
| Extension → language tag mapping | `.dart` → `dart`, `.json` → `json`, etc. |
| Paths with subdirectories        | `@lib/src/foo.dart` handled correctly    |

And `test/ui/at_file_hint_test.dart` mirroring the structure of
`test/slash_autocomplete_test.dart`:

| Test case                                 | What it checks                        |
| ----------------------------------------- | ------------------------------------- |
| Inactive when no `@` present              | `active == false`                     |
| Activates on `@` followed by valid prefix | `active == true`, matches populated   |
| Up/down navigation wraps                  | Selection cycles correctly            |
| Accept inserts completion                 | Returned string is the completed path |
| Dismiss clears state                      | `active == false`, matches empty      |
| Render output count                       | `overlayHeight == min(matches, 8)`    |

---

## File Changelist

| File                                 | Change                                                |
| ------------------------------------ | ----------------------------------------------------- |
| `lib/src/input/file_expander.dart`   | **New** — `expandFileRefs`, `extractFileRefs`         |
| `lib/src/ui/at_file_hint.dart`       | **New** — `AtFileHint` overlay widget                 |
| `lib/src/app.dart`                   | **Modified** — expand on submit; wire `AtFileHint`    |
| `lib/glue.dart`                      | **Modified** — export `AtFileHint` if needed publicly |
| `test/input/file_expander_test.dart` | **New** — unit tests for expansion logic              |
| `test/ui/at_file_hint_test.dart`     | **New** — unit tests for hint overlay                 |

---

## What's Explicitly Out of Scope

- Directory expansion (`@lib/src/` expands all files) — too risky for token budgets.
- Glob patterns (`@lib/**/*.dart`).
- Truncation / summarisation of large files (just block with a warning).
- Storing expanded content in session history on disk (sessions already record the
  raw conversation; the expansion is ephemeral).
