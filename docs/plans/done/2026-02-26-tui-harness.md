# TUI Harness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Glue CLI TUI fully functional with visible cursor, rendered conversation blocks, scrollback, slash commands, modals, markdown rendering, and polished status bar — all working against the stub LLM before any real API integration.

**Architecture:** The TUI uses a hybrid rendering approach: the output zone uses the terminal's native scroll region for natural scrolling, while the status bar and input area are painted at fixed positions. A `Renderer` orchestrates all painting and ensures the cursor ends up at the correct position. Modals are drawn as overlays using the `ScreenBuffer` for the modal box only.

**Tech Stack:** Dart 3.4+, raw terminal I/O, ANSI escape sequences, no external TUI framework.

---

## Task 1: Fix Cursor Visibility in Input Area

The cursor is invisible because `paintInput()` calls `restoreCursor()` after positioning the cursor, snapping it back to wherever it was saved.

**Files:**

- Modify: `cli/lib/src/terminal/layout.dart:89-99`
- Modify: `cli/lib/src/app.dart:282-299`

**Step 1: Fix `paintInput` cursor positioning**

In `layout.dart`, the `paintInput` method must leave the cursor at the typing position. Remove `saveCursor`/`restoreCursor` and ensure cursor is shown:

```dart
void paintInput(String prompt, String text, int cursorPos) {
  terminal.moveTo(inputTop, 1);
  terminal.clearLine();
  terminal.writeStyled(prompt, style: AnsiStyle.cyan);
  terminal.write(text);

  // Fill rest of line with spaces to clear stale characters.
  final usedCols = prompt.length + text.length;
  if (usedCols < terminal.columns) {
    terminal.write(' ' * (terminal.columns - usedCols));
  }

  // Position the visible cursor where the user is typing.
  final cursorCol = prompt.length + cursorPos + 1;
  terminal.moveTo(inputTop, cursorCol);
  terminal.showCursor();
}
```

**Step 2: Update `_render()` to paint input LAST**

In `app.dart`, the `_render()` method must call `paintInput` as the very last operation so the cursor ends up in the input area:

```dart
void _render() {
  // 1. Status bar (uses save/restore internally, safe).
  final statusLeft = switch (_mode) {
    AppMode.idle => ' Ready',
    AppMode.streaming => ' ● Generating...',
    AppMode.toolRunning => ' ⚙ Running tool...',
    AppMode.confirming => ' ? Waiting for approval',
  };
  final statusRight = 'tokens: ${agent.tokenCount} ';
  layout.paintStatus(statusLeft, statusRight);

  // 2. Input area — MUST be last so cursor lands here.
  final prompt = switch (_mode) {
    AppMode.idle => '❯ ',
    _ => '  ',
  };
  layout.paintInput(prompt, editor.text, editor.cursor);
}
```

**Step 3: Verify manually**

Run: `cd cli && dart run`
Expected: A blinking cursor appears after the `❯` prompt. Typing characters shows them. Arrow keys move the cursor left/right visibly. Backspace works.

**Step 4: Commit**

```bash
git add cli/lib/src/terminal/layout.dart cli/lib/src/app.dart
git commit -m "fix: make cursor visible in input area"
```

---

## Task 2: Render Conversation Blocks to Output Zone

Currently `_blocks` accumulate but are never rendered. The output zone is blank.

**Files:**

- Modify: `cli/lib/src/app.dart`
- Create: `cli/lib/src/rendering/block_renderer.dart`

**Step 1: Create block renderer**

Create `cli/lib/src/rendering/block_renderer.dart` that converts `_ConversationEntry` instances into styled terminal output lines:

```dart
import '../terminal/terminal.dart';

/// Renders a conversation block as styled terminal text.
class BlockRenderer {
  final int width;

  BlockRenderer(this.width);

  /// Render a user message block.
  String renderUser(String text) {
    final header = '\x1b[1m\x1b[36m❯ You\x1b[0m';
    final body = _wrapText(text, width - 2);
    final indented = body.split('\n').map((l) => '  $l').join('\n');
    return '$header\n$indented';
  }

  /// Render an assistant message block.
  String renderAssistant(String text) {
    final header = '\x1b[1m\x1b[35m◆ Glue\x1b[0m';
    final body = _wrapText(text, width - 2);
    final indented = body.split('\n').map((l) => '  $l').join('\n');
    return '$header\n$indented';
  }

  /// Render a tool call block.
  String renderToolCall(String name, Map<String, dynamic>? args) {
    final header = '\x1b[1m\x1b[33m▶ Tool: $name\x1b[0m';
    if (args == null || args.isEmpty) return header;
    final argsStr = args.entries
        .map((e) => '${e.key}: ${_truncate('${e.value}', width - 6)}')
        .join(', ');
    return '$header\n  \x1b[90m$argsStr\x1b[0m';
  }

  /// Render a tool result block.
  String renderToolResult(String content, {bool success = true}) {
    final icon = success ? '✓' : '✗';
    final color = success ? '\x1b[32m' : '\x1b[31m';
    final header = '\x1b[1m$color$icon Tool result\x1b[0m';
    final truncated = _truncateLines(content, 20, width - 2);
    final indented = truncated.split('\n').map((l) => '  \x1b[90m$l\x1b[0m').join('\n');
    return '$header\n$indented';
  }

  /// Render an error block.
  String renderError(String message) {
    final header = '\x1b[1m\x1b[31m✗ Error\x1b[0m';
    final body = _wrapText(message, width - 2);
    final indented = body.split('\n').map((l) => '  \x1b[31m$l\x1b[0m').join('\n');
    return '$header\n$indented';
  }

  /// Render a system message block.
  String renderSystem(String text) {
    return '\x1b[90m$text\x1b[0m';
  }

  /// Word-wrap text to fit within [maxWidth] columns.
  String _wrapText(String text, int maxWidth) {
    if (maxWidth <= 0) return text;
    final lines = <String>[];
    for (final paragraph in text.split('\n')) {
      if (paragraph.isEmpty) {
        lines.add('');
        continue;
      }
      var remaining = paragraph;
      while (remaining.length > maxWidth) {
        // Find last space within maxWidth.
        var breakAt = remaining.lastIndexOf(' ', maxWidth);
        if (breakAt <= 0) breakAt = maxWidth;
        lines.add(remaining.substring(0, breakAt));
        remaining = remaining.substring(breakAt).trimLeft();
      }
      lines.add(remaining);
    }
    return lines.join('\n');
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  String _truncateLines(String s, int maxLines, int maxWidth) {
    final lines = s.split('\n');
    final capped = lines.length > maxLines
        ? [...lines.take(maxLines), '  … (${lines.length - maxLines} more lines)']
        : lines;
    return capped.map((l) => l.length > maxWidth ? '${l.substring(0, maxWidth - 1)}…' : l).join('\n');
  }
}
```

**Step 2: Track which blocks have already been written to output**

In `app.dart`, add a `_renderedBlockCount` field so we only write new blocks to the output zone (which scrolls naturally):

```dart
int _renderedBlockCount = 0;
```

**Step 3: Update `_render()` to write new blocks to the output zone**

In `app.dart`, before painting the status bar, flush any new blocks:

```dart
void _render() {
  final renderer = BlockRenderer(terminal.columns);

  // 1. Write any new conversation blocks to the output zone.
  while (_renderedBlockCount < _blocks.length) {
    final block = _blocks[_renderedBlockCount];
    final text = switch (block.kind) {
      _EntryKind.user => renderer.renderUser(block.text),
      _EntryKind.assistant => renderer.renderAssistant(block.text),
      _EntryKind.toolCall => renderer.renderToolCall(block.text, block.args),
      _EntryKind.toolResult => renderer.renderToolResult(block.text),
      _EntryKind.error => renderer.renderError(block.text),
    };
    layout.writeOutput(text);
    _renderedBlockCount++;
  }

  // 2. Status bar.
  // ... (existing code)

  // 3. Input area — LAST so cursor lands here.
  // ... (existing code)
}
```

**Step 4: Add `system` kind to `_EntryKind` and `_ConversationEntry`**

```dart
enum _EntryKind { user, assistant, toolCall, toolResult, error, system }

// Add factory:
factory _ConversationEntry.system(String text) =>
    _ConversationEntry._(_EntryKind.system, text);
```

**Step 5: Export the new file from `glue.dart`**

```dart
export 'src/rendering/block_renderer.dart' show BlockRenderer;
```

**Step 6: Show a welcome message on startup**

In `App.run()`, before the initial `_render()`:

```dart
_blocks.add(_ConversationEntry.system(
  'Glue v0.1.0 — model: ${agent.modelName}\n'
  'Type /help for commands. Ctrl+C to exit.',
));
```

This requires adding `modelName` to `AgentCore` (just a `String` field set in the constructor).

**Step 7: Verify manually**

Run: `cd cli && dart run`
Expected: Welcome message appears in the output zone. Typing text and pressing Enter shows "❯ You" header followed by the message, then "◆ Glue" with the stub response.

**Step 8: Commit**

```bash
git add cli/lib/src/rendering/block_renderer.dart cli/lib/src/app.dart cli/lib/glue.dart
git commit -m "feat: render conversation blocks to output zone"
```

---

## Task 3: Slash Command System

**Files:**

- Create: `cli/lib/src/commands/slash_commands.dart`
- Modify: `cli/lib/src/app.dart`

**Step 1: Create the slash command infrastructure**

Create `cli/lib/src/commands/slash_commands.dart`:

```dart
/// A registered slash command.
class SlashCommand {
  final String name;
  final String description;
  final List<String> aliases;
  final String Function(List<String> args) execute;

  const SlashCommand({
    required this.name,
    required this.description,
    this.aliases = const [],
    required this.execute,
  });
}

/// Registry of all slash commands.
class SlashCommandRegistry {
  final List<SlashCommand> _commands = [];

  void register(SlashCommand command) => _commands.add(command);

  /// Parse and execute a slash command string.
  /// Returns the output text, or null if the command is not found.
  String? execute(String input) {
    final parts = input.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || !parts[0].startsWith('/')) return null;

    final cmdName = parts[0].substring(1).toLowerCase();
    final args = parts.sublist(1);

    final command = _commands.cast<SlashCommand?>().firstWhere(
      (c) => c!.name == cmdName || c.aliases.contains(cmdName),
      orElse: () => null,
    );

    if (command == null) {
      return 'Unknown command: /$cmdName. Type /help for available commands.';
    }

    return command.execute(args);
  }

  /// Get all commands for help display.
  List<SlashCommand> get commands => List.unmodifiable(_commands);
}
```

**Step 2: Register commands in `App`**

In `app.dart`, add a `SlashCommandRegistry` field and register commands in the constructor or `App.create()`:

```dart
late final SlashCommandRegistry _commands;

// In App.create() or init:
void _initCommands() {
  _commands = SlashCommandRegistry();

  _commands.register(SlashCommand(
    name: 'help',
    description: 'Show available commands and keybindings',
    execute: (_) {
      final buf = StringBuffer('Available commands:\n');
      for (final cmd in _commands.commands) {
        final aliases = cmd.aliases.isNotEmpty
            ? ' (${cmd.aliases.map((a) => '/$a').join(', ')})'
            : '';
        buf.writeln('  /${cmd.name}$aliases — ${cmd.description}');
      }
      buf.writeln('\nKeybindings:');
      buf.writeln('  Ctrl+C     Cancel / Exit');
      buf.writeln('  Up/Down    History navigation');
      buf.writeln('  Ctrl+U     Clear line');
      buf.writeln('  Ctrl+W     Delete word');
      buf.writeln('  Ctrl+K     Kill to end of line');
      buf.writeln('  Ctrl+A     Move to start');
      buf.writeln('  Ctrl+E     Move to end');
      buf.writeln('  PageUp/Dn  Scroll output');
      return buf.toString();
    },
  ));

  _commands.register(SlashCommand(
    name: 'clear',
    description: 'Clear conversation history',
    execute: (_) {
      _blocks.clear();
      _renderedBlockCount = 0;
      _streamingText = '';
      terminal.clearScreen();
      layout.apply();
      return 'Cleared.';
    },
  ));

  _commands.register(SlashCommand(
    name: 'exit',
    description: 'Exit Glue',
    aliases: ['quit', 'q'],
    execute: (_) {
      _exitCompleter.complete();
      return '';
    },
  ));

  _commands.register(SlashCommand(
    name: 'model',
    description: 'Show or set the model name',
    execute: (args) {
      if (args.isEmpty) return 'Current model: ${_modelName}';
      _modelName = args.join(' ');
      return 'Model set to: $_modelName';
    },
  ));

  _commands.register(SlashCommand(
    name: 'tokens',
    description: 'Show token usage',
    execute: (_) => 'Total tokens used: ${agent.tokenCount}',
  ));

  _commands.register(SlashCommand(
    name: 'tools',
    description: 'List available tools',
    execute: (_) {
      final buf = StringBuffer('Available tools:\n');
      for (final tool in agent.tools.values) {
        buf.writeln('  ${tool.name} — ${tool.description}');
      }
      return buf.toString();
    },
  ));

  _commands.register(SlashCommand(
    name: 'history',
    description: 'Show input history',
    execute: (args) {
      final n = args.isNotEmpty ? int.tryParse(args[0]) ?? 10 : 10;
      final history = editor.history;
      if (history.isEmpty) return 'No history.';
      final recent = history.length > n
          ? history.sublist(history.length - n)
          : history;
      final buf = StringBuffer('Recent inputs:\n');
      for (var i = 0; i < recent.length; i++) {
        buf.writeln('  ${i + 1}. ${recent[i]}');
      }
      return buf.toString();
    },
  ));
}
```

This requires exposing `history` from `LineEditor`:

```dart
// In line_editor.dart, add getter:
List<String> get history => List.unmodifiable(_history);
```

**Step 3: Route slash commands in `_handleAppEvent`**

In the `UserSubmit` handler:

```dart
case UserSubmit(:final text):
  if (text.startsWith('/')) {
    final result = _commands.execute(text);
    if (result != null && result.isNotEmpty) {
      _blocks.add(_ConversationEntry.system(result));
    }
    editor.clear();
    _render();
  } else {
    _startAgent(text);
  }
```

**Step 4: Verify manually**

Run: `cd cli && dart run`
Expected:

- Type `/help` → shows command list and keybindings in gray
- Type `/clear` → screen clears, shows "Cleared."
- Type `/tools` → lists the 5 registered tools
- Type `/model gpt-5` → shows "Model set to: gpt-5"
- Type `/exit` → cleanly exits

**Step 5: Commit**

```bash
git add cli/lib/src/commands/slash_commands.dart cli/lib/src/app.dart cli/lib/src/input/line_editor.dart cli/lib/glue.dart
git commit -m "feat: add slash command system with /help, /clear, /exit, /model, /tokens, /tools, /history"
```

---

## Task 4: Scrollback Support

**Files:**

- Modify: `cli/lib/src/app.dart`
- Modify: `cli/lib/src/terminal/layout.dart`

**Step 1: Add scroll state to App**

In `app.dart`, add:

```dart
/// Lines of rendered output for scrollback.
final List<String> _outputLines = [];

/// Scroll offset from the bottom. 0 = follow mode (pinned to bottom).
int _scrollOffset = 0;
```

**Step 2: Change output rendering to use full-viewport repaint for scroll**

Instead of using `Layout.writeOutput` (which relies on native terminal scrolling), switch to a viewport model where `_render()` computes which lines to display and paints them directly into the output zone.

Add to `Layout`:

```dart
/// Paint the output zone with specific lines (for scrollback mode).
void paintOutputViewport(List<String> lines) {
  final height = outputBottom - outputTop + 1;
  for (var i = 0; i < height; i++) {
    terminal.moveTo(outputTop + i, 1);
    terminal.clearLine();
    if (i < lines.length) {
      terminal.write(lines[i]);
    }
  }
}
```

**Step 3: Update `_render()` to support scrollback**

When blocks are added, convert them to wrapped lines and store in `_outputLines`. Then compute the visible window:

```dart
void _render() {
  final renderer = BlockRenderer(terminal.columns);

  // Rebuild output lines from blocks (could be optimized with caching).
  _outputLines.clear();
  for (final block in _blocks) {
    final text = switch (block.kind) {
      _EntryKind.user => renderer.renderUser(block.text),
      _EntryKind.assistant => renderer.renderAssistant(block.text),
      _EntryKind.toolCall => renderer.renderToolCall(block.text, block.args),
      _EntryKind.toolResult => renderer.renderToolResult(block.text),
      _EntryKind.error => renderer.renderError(block.text),
      _EntryKind.system => renderer.renderSystem(block.text),
    };
    _outputLines.addAll(text.split('\n'));
    _outputLines.add(''); // blank line between blocks
  }

  // If streaming, add the partial text.
  if (_streamingText.isNotEmpty) {
    _outputLines.addAll(renderer.renderAssistant(_streamingText).split('\n'));
  }

  // Compute visible window.
  final viewportHeight = layout.outputBottom - layout.outputTop + 1;
  final totalLines = _outputLines.length;
  final maxScroll = (totalLines - viewportHeight).clamp(0, totalLines);

  // Clamp scroll offset.
  _scrollOffset = _scrollOffset.clamp(0, maxScroll);

  final firstLine = (totalLines - viewportHeight - _scrollOffset).clamp(0, totalLines);
  final visibleLines = _outputLines.sublist(
    firstLine,
    (firstLine + viewportHeight).clamp(0, totalLines),
  );

  layout.paintOutputViewport(visibleLines);

  // Status bar.
  final statusLeft = switch (_mode) {
    AppMode.idle => ' Ready',
    AppMode.streaming => ' ● Generating...',
    AppMode.toolRunning => ' ⚙ Running tool...',
    AppMode.confirming => ' ? Waiting for approval',
  };
  final scrollIndicator = _scrollOffset > 0 ? '↑${_scrollOffset} ' : '';
  final statusRight = '${scrollIndicator}tok ${agent.tokenCount} ';
  layout.paintStatus(statusLeft, statusRight);

  // Input area — LAST.
  final prompt = switch (_mode) {
    AppMode.idle => '❯ ',
    _ => '  ',
  };
  layout.paintInput(prompt, editor.text, editor.cursor);
}
```

**Step 4: Handle scroll keys in `_handleTerminalEvent`**

Before passing to the editor, intercept PageUp/PageDown:

```dart
case KeyEvent(key: Key.pageUp):
  final viewportHeight = layout.outputBottom - layout.outputTop + 1;
  _scrollOffset += viewportHeight ~/ 2;
  _render();
  return;

case KeyEvent(key: Key.pageDown):
  final viewportHeight = layout.outputBottom - layout.outputTop + 1;
  _scrollOffset = (_scrollOffset - viewportHeight ~/ 2).clamp(0, _scrollOffset);
  _render();
  return;
```

When new blocks arrive and `_scrollOffset == 0`, they auto-scroll into view (follow mode). If the user has scrolled up, new content doesn't jump.

**Step 5: Remove `_renderedBlockCount` since we now repaint the full viewport**

The `_renderedBlockCount` tracking from Task 2 is no longer needed. Remove it. The viewport repaint handles everything.

**Step 6: Verify manually**

Run: `cd cli && dart run`
Expected:

- Send several messages to fill the output area
- PageUp scrolls up, showing earlier output
- PageDown scrolls back down
- Status bar shows `↑N` when scrolled up
- New messages auto-scroll when at the bottom

**Step 7: Commit**

```bash
git add cli/lib/src/app.dart cli/lib/src/terminal/layout.dart
git commit -m "feat: add scrollback support with PageUp/PageDown"
```

---

## Task 5: Modal System for Tool Confirmations

**Files:**

- Create: `cli/lib/src/ui/modal.dart`
- Modify: `cli/lib/src/app.dart`
- Modify: `cli/lib/src/agent/agent_core.dart` (fix duplicate yield)

**Step 1: Fix duplicate `AgentToolCall` emission in `agent_core.dart`**

In `AgentCore.run()`, tool calls are yielded twice — once from `ToolCallDelta` and again in the execution loop. Remove the second yield:

```dart
// In the tool execution loop, change:
for (final call in toolCalls) {
  _toolResultCompleter = Completer<ToolResult>();
  // REMOVED: yield AgentToolCall(call);  ← this was the duplicate
  final result = await _toolResultCompleter!.future;
  _conversation.add(Message.toolResult(
    callId: call.id,
    content: result.content,
  ));
  yield AgentToolResult(result);
}
```

**Step 2: Create the modal system**

Create `cli/lib/src/ui/modal.dart`:

```dart
import 'dart:async';
import 'dart:math';
import '../terminal/terminal.dart';

/// A choice in a confirmation modal.
class ModalChoice {
  final String label;
  final String hotkey;

  const ModalChoice(this.label, this.hotkey);
}

/// A confirmation modal rendered as a centered box overlay.
class ConfirmModal {
  final String title;
  final List<String> bodyLines;
  final List<ModalChoice> choices;
  final _completer = Completer<int>();
  int _selected = 0;

  ConfirmModal({
    required this.title,
    required this.bodyLines,
    required this.choices,
  });

  /// The future that resolves with the index of the chosen option.
  Future<int> get result => _completer.future;

  bool get isComplete => _completer.isCompleted;

  /// Handle a terminal event. Returns true if consumed.
  bool handleEvent(TerminalEvent event) {
    if (_completer.isCompleted) return false;

    switch (event) {
      case KeyEvent(key: Key.left):
        _selected = (_selected - 1).clamp(0, choices.length - 1);
        return true;
      case KeyEvent(key: Key.right) || KeyEvent(key: Key.tab):
        _selected = (_selected + 1) % choices.length;
        return true;
      case KeyEvent(key: Key.enter):
        _completer.complete(_selected);
        return true;
      case KeyEvent(key: Key.escape):
        // Escape = deny (index 1, typically "No")
        final noIndex = choices.indexWhere((c) => c.hotkey.toLowerCase() == 'n');
        _completer.complete(noIndex >= 0 ? noIndex : 1);
        return true;
      case CharEvent(char: final c):
        final idx = choices.indexWhere(
          (ch) => ch.hotkey.toLowerCase() == c.toLowerCase(),
        );
        if (idx >= 0) {
          _completer.complete(idx);
          return true;
        }
        return true; // Swallow all input while modal is open
      default:
        return true;
    }
  }

  /// Render the modal as lines to be painted in the output zone.
  /// Returns a list of strings, one per row, representing the box.
  List<String> render(int terminalWidth) {
    final contentWidth = min(terminalWidth - 4, 64);
    final horizontal = '─' * (contentWidth - 2);

    final lines = <String>[];
    lines.add(_center('┌$horizontal┐', terminalWidth));

    // Title
    lines.add(_center('│${_pad(' $title', contentWidth - 2)}│', terminalWidth));
    lines.add(_center('│${'─' * (contentWidth - 2)}│', terminalWidth));

    // Body
    for (final line in bodyLines) {
      final truncated = line.length > contentWidth - 4
          ? '${line.substring(0, contentWidth - 5)}…'
          : line;
      lines.add(_center('│${_pad('  $truncated', contentWidth - 2)}│', terminalWidth));
    }

    lines.add(_center('│${' ' * (contentWidth - 2)}│', terminalWidth));

    // Choices
    final choiceBuf = StringBuffer();
    for (var i = 0; i < choices.length; i++) {
      final choice = choices[i];
      if (i == _selected) {
        choiceBuf.write(' \x1b[7m [${choice.hotkey}]${choice.label} \x1b[27m ');
      } else {
        choiceBuf.write(' [${choice.hotkey}]${choice.label} ');
      }
    }
    lines.add(_center('│${_pad(choiceBuf.toString(), contentWidth - 2)}│', terminalWidth));
    lines.add(_center('└$horizontal┘', terminalWidth));

    return lines;
  }

  String _pad(String s, int width) {
    // Strip ANSI for measurement
    final visible = s.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
    if (visible.length >= width) return s;
    return '$s${' ' * (width - visible.length)}';
  }

  String _center(String s, int terminalWidth) {
    final visible = s.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
    final pad = ((terminalWidth - visible.length) / 2).floor().clamp(0, terminalWidth);
    return '${' ' * pad}$s';
  }
}
```

**Step 3: Integrate modal into App**

In `app.dart`, add:

```dart
ConfirmModal? _activeModal;
```

Update `_handleTerminalEvent` to route to modal first:

```dart
void _handleTerminalEvent(TerminalEvent event) {
  // Modal gets first crack at input.
  if (_activeModal != null && !_activeModal!.isComplete) {
    if (_activeModal!.handleEvent(event)) {
      _render();
      return;
    }
  }
  // ... rest of existing handler
}
```

Update `_handleAgentEvent` for `AgentToolCall`:

```dart
case AgentToolCall(:final call):
  _blocks.add(_ConversationEntry.toolCall(call.name, call.arguments));

  // Check tool policy (auto-approve read-only tools).
  if (_shouldAutoApprove(call.name)) {
    _mode = AppMode.toolRunning;
    _render();
    agent.executeTool(call).then((result) {
      agent.completeToolCall(result);
    });
    return;
  }

  // Show confirmation modal.
  _mode = AppMode.confirming;
  final bodyLines = call.arguments.entries
      .map((e) => '${e.key}: ${e.value}')
      .toList();
  _activeModal = ConfirmModal(
    title: 'Approve tool: ${call.name}',
    bodyLines: bodyLines,
    choices: [
      ModalChoice('Yes', 'y'),
      ModalChoice('No', 'n'),
      ModalChoice('Always', 'a'),
    ],
  );
  _render();

  _activeModal!.result.then((choiceIndex) {
    _activeModal = null;
    switch (choiceIndex) {
      case 0: // Yes
        _mode = AppMode.toolRunning;
        _render();
        agent.executeTool(call).then((result) {
          agent.completeToolCall(result);
        });
      case 2: // Always
        _autoApprovedTools.add(call.name);
        _mode = AppMode.toolRunning;
        _render();
        agent.executeTool(call).then((result) {
          agent.completeToolCall(result);
        });
      default: // No
        agent.completeToolCall(ToolResult.denied(call.id));
    }
  });
```

Add auto-approve support:

```dart
final Set<String> _autoApprovedTools = {'read_file', 'list_directory', 'grep'};

bool _shouldAutoApprove(String toolName) => _autoApprovedTools.contains(toolName);
```

**Step 4: Render the modal overlay in `_render()`**

After painting the output viewport but before the input area, if a modal is active, paint it over the center of the output zone:

```dart
// In _render(), after paintOutputViewport:
if (_activeModal != null && !_activeModal!.isComplete) {
  final modalLines = _activeModal!.render(terminal.columns);
  final startRow = layout.outputTop +
      ((layout.outputBottom - layout.outputTop - modalLines.length) ~/ 2)
          .clamp(0, layout.outputBottom);
  for (var i = 0; i < modalLines.length; i++) {
    terminal.moveTo(startRow + i, 1);
    terminal.clearLine();
    terminal.write(modalLines[i]);
  }
}
```

**Step 5: Hide cursor during modal**

In `paintInput`, check the mode:

```dart
// At end of paintInput:
if (mode != AppMode.confirming) {
  terminal.showCursor();
} else {
  terminal.hideCursor();
}
```

This means `paintInput` needs a `mode` parameter, or `_render()` handles cursor visibility after calling `paintInput`.

**Step 6: Verify manually**

Run: `cd cli && dart run`
Expected:

- Update the stub LLM to emit a tool call for testing
- A centered modal box appears with "Approve tool: bash"
- Press Y to approve, N to deny
- Arrow/Tab cycle between options
- After approval, tool result block appears

**Step 7: Commit**

```bash
git add cli/lib/src/ui/modal.dart cli/lib/src/app.dart cli/lib/src/agent/agent_core.dart cli/lib/glue.dart
git commit -m "feat: add modal system for tool confirmations"
```

---

## Task 6: Markdown Rendering for Assistant Output

**Files:**

- Create: `cli/lib/src/rendering/markdown_renderer.dart`
- Modify: `cli/lib/src/rendering/block_renderer.dart`

**Step 1: Create a terminal markdown renderer**

Create `cli/lib/src/rendering/markdown_renderer.dart` that handles a pragmatic subset:

````dart
/// Renders a subset of Markdown to ANSI-styled terminal text.
///
/// Supported:
/// - Headings: #, ##, ###
/// - Bold: **text**
/// - Italic: *text*
/// - Inline code: `code`
/// - Fenced code blocks: ```lang ... ```
/// - Unordered lists: - item, * item
/// - Ordered lists: 1. item
/// - Blockquotes: > text
class MarkdownRenderer {
  final int width;

  MarkdownRenderer(this.width);

  /// Render markdown text to ANSI-styled terminal output.
  String render(String markdown) {
    final lines = markdown.split('\n');
    final output = <String>[];
    var inCodeBlock = false;
    String? codeBlockLang;
    final codeLines = <String>[];

    for (final line in lines) {
      // Fenced code blocks
      if (line.trimLeft().startsWith('```')) {
        if (!inCodeBlock) {
          inCodeBlock = true;
          codeBlockLang = line.trimLeft().substring(3).trim();
          if (codeBlockLang!.isEmpty) codeBlockLang = null;
          continue;
        } else {
          // End code block — render it
          output.addAll(_renderCodeBlock(codeLines, codeBlockLang));
          codeLines.clear();
          inCodeBlock = false;
          codeBlockLang = null;
          continue;
        }
      }

      if (inCodeBlock) {
        codeLines.add(line);
        continue;
      }

      // Headings
      if (line.startsWith('### ')) {
        output.add('\x1b[1m\x1b[4m${line.substring(4)}\x1b[0m');
        continue;
      }
      if (line.startsWith('## ')) {
        output.add('\x1b[1m\x1b[4m${line.substring(3)}\x1b[0m');
        continue;
      }
      if (line.startsWith('# ')) {
        output.add('\x1b[1m\x1b[4m${line.substring(2)}\x1b[0m');
        continue;
      }

      // Blockquote
      if (line.startsWith('> ')) {
        output.add('\x1b[90m│ ${line.substring(2)}\x1b[0m');
        continue;
      }

      // Unordered list
      final ulMatch = RegExp(r'^(\s*)[-*] (.*)').firstMatch(line);
      if (ulMatch != null) {
        final indent = ulMatch.group(1)!;
        final content = _renderInline(ulMatch.group(2)!);
        output.add('$indent• $content');
        continue;
      }

      // Ordered list
      final olMatch = RegExp(r'^(\s*)(\d+)\. (.*)').firstMatch(line);
      if (olMatch != null) {
        final indent = olMatch.group(1)!;
        final num = olMatch.group(2)!;
        final content = _renderInline(olMatch.group(3)!);
        output.add('$indent$num. $content');
        continue;
      }

      // Regular paragraph line
      if (line.isEmpty) {
        output.add('');
      } else {
        output.add(_renderInline(line));
      }
    }

    // Close any unclosed code block
    if (inCodeBlock && codeLines.isNotEmpty) {
      output.addAll(_renderCodeBlock(codeLines, codeBlockLang));
    }

    return output.join('\n');
  }

  /// Render inline markdown: **bold**, *italic*, `code`
  String _renderInline(String text) {
    // Bold
    text = text.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (m) => '\x1b[1m${m.group(1)}\x1b[22m',
    );
    // Italic
    text = text.replaceAllMapped(
      RegExp(r'\*(.+?)\*'),
      (m) => '\x1b[3m${m.group(1)}\x1b[23m',
    );
    // Inline code
    text = text.replaceAllMapped(
      RegExp(r'`(.+?)`'),
      (m) => '\x1b[36m${m.group(1)}\x1b[39m',
    );
    // Links: [text](url) → text (url)
    text = text.replaceAllMapped(
      RegExp(r'\[(.+?)\]\((.+?)\)'),
      (m) => '${m.group(1)} \x1b[90m(${m.group(2)})\x1b[0m',
    );
    return text;
  }

  /// Render a fenced code block with box-drawing characters.
  List<String> _renderCodeBlock(List<String> lines, String? lang) {
    final codeWidth = (width - 4).clamp(20, width);
    final label = lang != null ? ' $lang ' : '';
    final headerRule = '─' * (codeWidth - 2 - label.length);

    final output = <String>[];
    output.add('\x1b[90m╭─$label$headerRule╮\x1b[0m');
    for (final line in lines) {
      final truncated = line.length > codeWidth - 4
          ? '${line.substring(0, codeWidth - 5)}…'
          : line;
      final padded = truncated.padRight(codeWidth - 4);
      output.add('\x1b[90m│\x1b[0m \x1b[2m$padded\x1b[22m \x1b[90m│\x1b[0m');
    }
    output.add('\x1b[90m╰${'─' * (codeWidth - 2)}╯\x1b[0m');
    return output;
  }
}
````

**Step 2: Integrate into `BlockRenderer.renderAssistant`**

In `block_renderer.dart`, use the markdown renderer for assistant output:

```dart
import 'markdown_renderer.dart';

// In renderAssistant():
String renderAssistant(String text) {
  final header = '\x1b[1m\x1b[35m◆ Glue\x1b[0m';
  final md = MarkdownRenderer(width - 2);
  final body = md.render(text);
  final indented = body.split('\n').map((l) => '  $l').join('\n');
  return '$header\n$indented';
}
```

**Step 3: Update the stub LLM to emit markdown-rich responses for testing**

In `app.dart`'s `_StubLlmClient`:

````dart
class _StubLlmClient extends LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final response = '''
Hello! I'm **Glue**, your coding agent.

## What I can do

- Read and write files
- Run shell commands
- Search through code with `grep`

Here's an example:

```dart
void main() {
  print('Hello, World!');
}
````

> LLM integration is not yet implemented.
> This is a _stub_ response.''';

    // Stream character by character for realistic feel.
    for (var i = 0; i < response.length; i++) {
      yield TextDelta(response[i]);
      // Tiny delay would be here in real impl.
    }
    yield UsageInfo(inputTokens: 42, outputTokens: response.length);

}
}

````

**Step 4: Verify manually**

Run: `cd cli && dart run`
Expected:
- Type any message and press Enter
- "◆ Glue" header appears
- **Bold** text renders as bold
- `code` renders in cyan
- Code block renders inside a box with `╭/╰` corners
- Blockquote lines have `│` prefix in gray
- List items use `•` bullets

**Step 5: Commit**

```bash
git add cli/lib/src/rendering/markdown_renderer.dart cli/lib/src/rendering/block_renderer.dart cli/lib/src/app.dart cli/lib/glue.dart
git commit -m "feat: add markdown rendering for assistant output"
````

---

## Task 7: Status Bar Polish

**Files:**

- Modify: `cli/lib/src/app.dart`

**Step 1: Add model name and CWD tracking**

In `App`:

```dart
String _modelName;
final String _cwd;

// In App.create():
_modelName = model;
_cwd = Directory.current.path;
```

**Step 2: Update status bar rendering in `_render()`**

```dart
// Shorten path for display
String _shortenPath(String path) {
  final home = Platform.environment['HOME'] ?? '';
  if (home.isNotEmpty && path.startsWith(home)) {
    return '~${path.substring(home.length)}';
  }
  return path;
}

// In _render():
final modeIndicator = switch (_mode) {
  AppMode.idle => 'Ready',
  AppMode.streaming => '● Generating',
  AppMode.toolRunning => '⚙ Tool',
  AppMode.confirming => '? Approve',
};
final shortCwd = _shortenPath(_cwd);
final statusLeft = ' $modeIndicator  $_modelName  $shortCwd';

final scrollIndicator = _scrollOffset > 0 ? '↑$_scrollOffset  ' : '';
final statusRight = '${scrollIndicator}tok ${agent.tokenCount} ';
```

**Step 3: Verify manually**

Run: `cd cli && dart run`
Expected: Status bar shows mode, model name, working directory on the left. Token count on the right. Scroll indicator appears when scrolled up.

**Step 4: Commit**

```bash
git add cli/lib/src/app.dart
git commit -m "feat: polish status bar with model, cwd, and scroll indicator"
```

---

## Task 8: Startup/Shutdown Polish

**Files:**

- Modify: `cli/lib/src/app.dart`
- Modify: `cli/bin/glue.dart`

**Step 1: Add robust shutdown with try/finally**

In `App.run()`:

```dart
Future<void> run() async {
  terminal.enableRawMode();
  terminal.enableAltScreen();
  terminal.clearScreen();
  layout.apply();

  _blocks.add(_ConversationEntry.system(
    'Glue v0.1.0 — $_modelName\n'
    'Working directory: ${_shortenPath(_cwd)}\n'
    'Type /help for commands.',
  ));

  terminal.events.listen(_handleTerminalEvent);
  _events.stream.listen(_handleAppEvent);

  _render();

  try {
    await _exitCompleter.future;
  } finally {
    _agentSub?.cancel();
    terminal.showCursor();
    terminal.write('\x1b[0m'); // Reset all styles
    terminal.disableAltScreen();
    terminal.disableRawMode();
    terminal.dispose();
  }
}
```

**Step 2: Simplify `bin/glue.dart` shutdown**

Since `App.run()` now handles cleanup in `finally`, simplify the signal handler:

```dart
ProcessSignal.sigint.watch().listen((_) {
  // App.run()'s finally block handles cleanup.
  exit(0);
});
```

Actually, better: have SIGINT trigger the exit completer instead of calling `exit(0)` directly, so cleanup runs:

```dart
// In App, expose a method:
void requestExit() {
  if (!_exitCompleter.isCompleted) _exitCompleter.complete();
}

// In bin/glue.dart:
ProcessSignal.sigint.watch().listen((_) => app.requestExit());
await app.run();
```

**Step 3: Verify manually**

Run: `cd cli && dart run`
Expected:

- Clean startup with welcome message, model, cwd
- Ctrl+C exits cleanly without terminal corruption
- `/exit` exits cleanly
- Terminal is fully restored (cursor visible, normal mode, no alt screen)

**Step 4: Commit**

```bash
git add cli/lib/src/app.dart cli/bin/glue.dart
git commit -m "feat: polish startup/shutdown with robust terminal cleanup"
```

---

## Task 9: Streaming Text Display

The stub LLM currently emits all text instantly. Make the streaming visible so it's testable.

**Files:**

- Modify: `cli/lib/src/app.dart`

**Step 1: Add artificial delay to stub LLM for testing**

```dart
class _StubLlmClient extends LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    // ... same response text ...

    // Stream word by word with delay for visible streaming effect.
    final words = response.split(' ');
    for (var i = 0; i < words.length; i++) {
      final word = i == 0 ? words[i] : ' ${words[i]}';
      yield TextDelta(word);
      await Future.delayed(Duration(milliseconds: 30));
    }
    yield UsageInfo(inputTokens: 42, outputTokens: response.length);
  }
}
```

**Step 2: Ensure streaming text renders incrementally**

The existing `_render()` already includes `_streamingText` in the viewport. Verify that `AgentTextDelta` triggers `_render()` on each delta — this is already the case in `_handleAgentEvent`.

**Step 3: Verify manually**

Run: `cd cli && dart run`
Expected: Assistant response appears word by word. Status shows "● Generating" during streaming. When done, status returns to "Ready".

**Step 4: Commit**

```bash
git add cli/lib/src/app.dart
git commit -m "feat: add streaming text display with word-by-word stub"
```

---

## Summary — Execution Order

| Task | What                       | Key Files                                                   |
| ---- | -------------------------- | ----------------------------------------------------------- |
| 1    | Fix cursor visibility      | `layout.dart`, `app.dart`                                   |
| 2    | Render conversation blocks | `block_renderer.dart` (new), `app.dart`                     |
| 3    | Slash commands             | `slash_commands.dart` (new), `app.dart`, `line_editor.dart` |
| 4    | Scrollback                 | `app.dart`, `layout.dart`                                   |
| 5    | Modal system               | `modal.dart` (new), `app.dart`, `agent_core.dart`           |
| 6    | Markdown rendering         | `markdown_renderer.dart` (new), `block_renderer.dart`       |
| 7    | Status bar polish          | `app.dart`                                                  |
| 8    | Startup/shutdown polish    | `app.dart`, `bin/glue.dart`                                 |
| 9    | Streaming display          | `app.dart`                                                  |

Tasks 1→2 are strict dependencies. Tasks 3, 5, 6, 7 can be done in any order after 2. Task 4 should come after 2. Task 8 can be done anytime. Task 9 should be last (validates the full pipeline).
