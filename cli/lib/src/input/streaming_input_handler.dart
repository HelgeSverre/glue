import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/commands/slash_autocomplete.dart';
import 'package:glue/src/input/line_editor.dart' show InputAction;
import 'package:glue/src/input/text_area_editor.dart';

/// Action to take after handling a terminal event during streaming mode.
enum StreamingAction {
  /// Re-render needed (autocomplete/editor state changed).
  render,

  /// Event consumed, no render needed (e.g. swallowed Enter).
  swallowed,

  /// Cancel the running agent.
  cancelAgent,

  /// Cancel the running bash process.
  cancelBash,
}

/// Result of handling a terminal event during streaming mode.
typedef StreamingInputResult = ({
  StreamingAction action,
  String? commandOutput
});

/// Handle a terminal event while in a non-idle mode (streaming, tool running,
/// or bash running).
///
/// Performs side effects on [editor] and [autocomplete] inline.
/// Returns the action the caller should take, plus any slash command output.
///
/// [isBashRunning] distinguishes bash mode from agent streaming for cancel
/// behavior.
StreamingInputResult handleStreamingInput({
  required TerminalEvent event,
  required bool isBashRunning,
  required TextAreaEditor editor,
  required SlashAutocomplete autocomplete,
  required SlashCommandRegistry commands,
}) {
  // Escape: dismiss autocomplete if active, otherwise cancel.
  if (event case KeyEvent(key: Key.escape)) {
    if (autocomplete.active) {
      autocomplete.dismiss();
      return (action: StreamingAction.render, commandOutput: null);
    }
    return (
      action: isBashRunning
          ? StreamingAction.cancelBash
          : StreamingAction.cancelAgent,
      commandOutput: null,
    );
  }

  // Ctrl+C: always cancel.
  if (event case KeyEvent(key: Key.ctrlC)) {
    return (
      action: isBashRunning
          ? StreamingAction.cancelBash
          : StreamingAction.cancelAgent,
      commandOutput: null,
    );
  }

  // Autocomplete intercepts keys when active.
  if (autocomplete.active) {
    if (event case KeyEvent(key: Key.up)) {
      autocomplete.moveUp();
      return (action: StreamingAction.render, commandOutput: null);
    }
    if (event case KeyEvent(key: Key.down)) {
      autocomplete.moveDown();
      return (action: StreamingAction.render, commandOutput: null);
    }
    if (event case KeyEvent(key: Key.tab)) {
      final result = autocomplete.accept(editor.text, editor.cursor);
      if (result != null) editor.setText(result.text, cursor: result.cursor);
      return (action: StreamingAction.render, commandOutput: null);
    }
    if (event case KeyEvent(key: Key.enter)) {
      if (autocomplete.selectedText == editor.text) {
        autocomplete.dismiss();
        final text = editor.text;
        editor.setText('');
        final out = commands.execute(text);
        return (action: StreamingAction.render, commandOutput: out);
      } else {
        final result = autocomplete.accept(editor.text, editor.cursor);
        if (result != null) editor.setText(result.text, cursor: result.cursor);
        return (action: StreamingAction.render, commandOutput: null);
      }
    }
  }

  // Enter: execute slash commands, swallow everything else.
  if (event case KeyEvent(key: Key.enter)) {
    final text = editor.text.trim();
    if (text.startsWith('/')) {
      autocomplete.dismiss();
      editor.setText('');
      final result = commands.execute(text);
      return (action: StreamingAction.render, commandOutput: result);
    }
    return (action: StreamingAction.swallowed, commandOutput: null);
  }

  // Pre-typing: buffer other keystrokes and update autocomplete.
  final action = editor.handle(event);
  if (action == InputAction.changed) {
    autocomplete.update(editor.text, editor.cursor);
    return (action: StreamingAction.render, commandOutput: null);
  }
  return (action: StreamingAction.swallowed, commandOutput: null);
}
