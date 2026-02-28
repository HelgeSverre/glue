import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/input/line_editor.dart';
import 'package:glue/src/input/streaming_input_handler.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/slash_autocomplete.dart';
import 'package:test/test.dart';

SlashCommandRegistry _makeRegistry() {
  final reg = SlashCommandRegistry();
  reg.register(SlashCommand(
    name: 'help',
    description: 'Show available commands',
    execute: (_) => 'Help output',
  ));
  reg.register(SlashCommand(
    name: 'clear',
    description: 'Clear conversation history',
    execute: (_) => 'Cleared.',
  ));
  reg.register(SlashCommand(
    name: 'info',
    description: 'Show session info',
    aliases: ['status'],
    execute: (_) => 'Info output',
  ));
  return reg;
}

void main() {
  late LineEditor editor;
  late SlashAutocomplete autocomplete;
  late SlashCommandRegistry commands;

  setUp(() {
    editor = LineEditor();
    commands = _makeRegistry();
    autocomplete = SlashAutocomplete(commands);
  });

  // ── Regression: slash commands must work during streaming ────────────────

  group('Regression: slash commands during streaming', () {
    test('typing "/" activates autocomplete during streaming', () {
      final result = handleStreamingInput(
        event: CharEvent('/'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.render);
      expect(autocomplete.active, isTrue,
          reason:
              'Autocomplete must activate when "/" is typed during streaming');
      expect(autocomplete.matchCount, 4); // help, clear, info, status (alias)
    });

    test('typing "/h" filters autocomplete to "help" during streaming', () {
      handleStreamingInput(
        event: CharEvent('/'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      final result = handleStreamingInput(
        event: CharEvent('h'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.render);
      expect(autocomplete.active, isTrue);
      expect(autocomplete.matchCount, 1);
      expect(autocomplete.selectedText, '/help');
    });

    test('Up/Down navigate autocomplete during streaming', () {
      // Type "/" to activate autocomplete with all 3 commands.
      handleStreamingInput(
        event: CharEvent('/'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      expect(autocomplete.selected, 0);

      // Move down.
      final down = handleStreamingInput(
        event: KeyEvent(Key.down),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      expect(down.action, StreamingAction.render);
      expect(autocomplete.selected, 1);

      // Move up.
      final up = handleStreamingInput(
        event: KeyEvent(Key.up),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      expect(up.action, StreamingAction.render);
      expect(autocomplete.selected, 0);
    });

    test('Tab accepts autocomplete completion during streaming', () {
      // Type "/" then Tab to accept first match.
      handleStreamingInput(
        event: CharEvent('/'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      final result = handleStreamingInput(
        event: KeyEvent(Key.tab),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.render);
      // Editor should have the completed command text.
      expect(editor.text, startsWith('/'));
    });

    test('Enter executes slash command via autocomplete during streaming', () {
      // Type "/h" to filter to "help", then Tab to accept, then Enter.
      handleStreamingInput(
        event: CharEvent('/'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      handleStreamingInput(
        event: CharEvent('h'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      // Accept the completion.
      handleStreamingInput(
        event: KeyEvent(Key.tab),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      expect(editor.text, '/help');

      // Now update autocomplete for the new text (simulates the render cycle).
      autocomplete.update(editor.text, editor.cursor);

      // Enter with matching selection — executes the command.
      final result = handleStreamingInput(
        event: KeyEvent(Key.enter),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.render);
      expect(result.commandOutput, 'Help output');
      expect(editor.text, isEmpty,
          reason: 'Editor should be cleared after slash command execution');
      expect(autocomplete.active, isFalse);
    });

    test('Enter executes slash command without autocomplete during streaming',
        () {
      // Type "/help" fully without using autocomplete.
      for (final c in ['/', 'h', 'e', 'l', 'p']) {
        handleStreamingInput(
          event: CharEvent(c),
          isBashRunning: false,
          editor: editor,
          autocomplete: autocomplete,
          commands: commands,
        );
      }
      // Autocomplete dismisses when there's a full match — dismiss it
      // to simulate the user pressing enter without autocomplete active.
      autocomplete.dismiss();

      final result = handleStreamingInput(
        event: KeyEvent(Key.enter),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.render);
      expect(result.commandOutput, 'Help output');
      expect(editor.text, isEmpty);
    });

    test('Enter swallows non-slash text during streaming', () {
      // Type "hello" and press Enter.
      for (final c in ['h', 'e', 'l', 'l', 'o']) {
        handleStreamingInput(
          event: CharEvent(c),
          isBashRunning: false,
          editor: editor,
          autocomplete: autocomplete,
          commands: commands,
        );
      }

      final result = handleStreamingInput(
        event: KeyEvent(Key.enter),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.swallowed);
      expect(result.commandOutput, isNull);
      expect(editor.text, 'hello',
          reason: 'Non-slash text should remain in buffer for when agent '
              'finishes');
    });
  });

  // ── Escape behavior ─────────────────────────────────────────────────────

  group('Escape during streaming', () {
    test('dismisses autocomplete instead of canceling agent', () {
      // Activate autocomplete.
      handleStreamingInput(
        event: CharEvent('/'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      expect(autocomplete.active, isTrue);

      // Escape should dismiss autocomplete, NOT cancel the agent.
      final result = handleStreamingInput(
        event: KeyEvent(Key.escape),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.render,
          reason: 'Escape should dismiss autocomplete, not cancel agent');
      expect(autocomplete.active, isFalse);
    });

    test('cancels agent when autocomplete is not active', () {
      final result = handleStreamingInput(
        event: KeyEvent(Key.escape),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.cancelAgent);
    });

    test('cancels bash when autocomplete is not active and bash running', () {
      final result = handleStreamingInput(
        event: KeyEvent(Key.escape),
        isBashRunning: true,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.cancelBash);
    });
  });

  // ── Ctrl+C behavior ─────────────────────────────────────────────────────

  group('Ctrl+C during streaming', () {
    test('always cancels agent even with autocomplete active', () {
      // Activate autocomplete.
      handleStreamingInput(
        event: CharEvent('/'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      expect(autocomplete.active, isTrue);

      final result = handleStreamingInput(
        event: KeyEvent(Key.ctrlC),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.cancelAgent,
          reason: 'Ctrl+C should always cancel the agent');
    });

    test('cancels bash when bash running', () {
      final result = handleStreamingInput(
        event: KeyEvent(Key.ctrlC),
        isBashRunning: true,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(result.action, StreamingAction.cancelBash);
    });
  });

  // ── Pre-typing buffer ───────────────────────────────────────────────────

  group('Pre-typing during streaming', () {
    test('regular text is buffered in editor', () {
      handleStreamingInput(
        event: CharEvent('h'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );
      handleStreamingInput(
        event: CharEvent('i'),
        isBashRunning: false,
        editor: editor,
        autocomplete: autocomplete,
        commands: commands,
      );

      expect(editor.text, 'hi');
      expect(autocomplete.active, isFalse,
          reason: 'Autocomplete should not activate for non-slash text');
    });
  });
}
