import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/app.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:test/test.dart';

class _NoopTerminal extends Terminal {
  @override
  Stream<TerminalEvent> get events => const Stream.empty();

  @override
  int get columns => 120;

  @override
  int get rows => 40;

  @override
  void clearScreen() {}

  @override
  void clearLine() {}

  @override
  void disableAltScreen() {}

  @override
  void disableMouse() {}

  @override
  void disableRawMode() {}

  @override
  void enableAltScreen() {}

  @override
  void enableMouse() {}

  @override
  void enableRawMode() {}

  @override
  void hideCursor() {}

  @override
  bool get isRaw => false;

  @override
  void moveTo(int row, int col) {}

  @override
  void resetScrollRegion() {}

  @override
  void restoreCursor() {}

  @override
  void saveCursor() {}

  @override
  void setScrollRegion(int top, int bottom) {}

  @override
  void showCursor() {}

  @override
  void write(String text) {}

  @override
  void writeStyled(String text, {AnsiStyle? style}) {}
}

class _NoopLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {}
}

void main() {
  group('App startup resume behavior', () {
    late Directory tempDir;
    late Environment environment;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('app_resume_startup_test_');
      environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
      environment.ensureDirectories();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('bare --resume opens the resume panel on startup', () async {
      final meta = SessionMeta(
        id: 'resume-target',
        cwd: environment.cwd,
        modelRef: 'anthropic/claude-sonnet-4.6',
        startTime: DateTime.now(),
        title: 'Saved work',
      );
      SessionStore(sessionDir: environment.sessionDir(meta.id), meta: meta);

      final terminal = _NoopTerminal();
      final app = App(
        terminal: terminal,
        layout: Layout(terminal),
        editor: TextAreaEditor(),
        agent: Agent(llm: _NoopLlm(), tools: const {}),
        modelId: 'anthropic/claude-sonnet-4.6',
        startupPrompt: null,
        resumeSessionId: '',
        environment: environment,
      );

      final runFuture = app.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      app.requestExit();
      await runFuture;

      expect(app.editor.text, isEmpty,
          reason:
              'opening the resume panel should not inject conversation text');
      expect(
        SessionStore.listSessions(environment.sessionsDir).map((s) => s.id),
        contains('resume-target'),
      );
    });

    test('resume with startup prompt submits the prompt after resuming',
        () async {
      final meta = SessionMeta(
        id: 'resume-target',
        cwd: environment.cwd,
        modelRef: 'anthropic/claude-sonnet-4.6',
        startTime: DateTime.now(),
        title: 'Saved work',
      );
      final store =
          SessionStore(sessionDir: environment.sessionDir(meta.id), meta: meta);
      store.logEvent('user_message', {'text': 'Earlier context'});
      store.logEvent('assistant_message', {'text': 'Prior answer'});

      final terminal = _NoopTerminal();
      final app = App(
        terminal: terminal,
        layout: Layout(terminal),
        editor: TextAreaEditor(),
        agent: Agent(llm: _NoopLlm(), tools: const {}),
        modelId: 'anthropic/claude-sonnet-4.6',
        startupPrompt: 'bar',
        resumeSessionId: 'resume-target',
        environment: environment,
      );

      final runFuture = app.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      app.requestExit();
      await runFuture;

      expect(
        app.agent.conversation.map((m) => m.text),
        contains('bar'),
      );
    });
  });
}
