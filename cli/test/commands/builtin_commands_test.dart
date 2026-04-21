import 'dart:io';

import 'package:glue/glue.dart';
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
  group('BuiltinCommands', () {
    SlashCommandRegistry createRegistry({
      void Function()? openHistoryPanel,
      String Function(String query)? historyActionByQuery,
      void Function()? openSkillsPanel,
      String Function(String name)? activateSkillByName,
      void Function()? openResumePanel,
      String Function(String query)? resumeSessionByQuery,
      String Function()? pathsReport,
      String Function(List<String> args)? openGlueTarget,
      String Function(List<String> args)? configAction,
      String Function(List<String> args)? sessionAction,
    }) {
      return BuiltinCommands.create(
        openHelpPanel: () {},
        clearConversation: () => '',
        requestExit: () {},
        openModelPanel: () {},
        switchModelByQuery: (_) => '',
        sessionInfo: () => '',
        sessionAction: sessionAction ?? (_) => '',
        listTools: () => '',
        openHistoryPanel: openHistoryPanel ?? () {},
        historyActionByQuery: historyActionByQuery ?? (_) => '',
        openResumePanel: openResumePanel ?? () {},
        resumeSessionByQuery: resumeSessionByQuery ?? (_) => '',
        toggleDebug: () => '',
        openSkillsPanel: openSkillsPanel ?? () {},
        activateSkillByName: activateSkillByName ?? (_) => '',
        toggleApproval: () => '',
        runProviderCommand: (_) => '',
        pathsReport: pathsReport ?? () => '',
        openGlueTarget: openGlueTarget ?? (_) => '',
        configAction: configAction ?? (_) => '',
        runMcpCommand: (_) => '',
      );
    }

    test('/skills without args opens panel', () {
      var opened = 0;
      String? activated;

      final registry = createRegistry(
        openSkillsPanel: () => opened++,
        activateSkillByName: (name) {
          activated = name;
          return 'Activating $name';
        },
      );

      final result = registry.execute('/skills');
      expect(result, '');
      expect(opened, 1);
      expect(activated, isNull);
    });

    test('/skills with args activates skill directly', () {
      var opened = 0;
      String? activated;

      final registry = createRegistry(
        openSkillsPanel: () => opened++,
        activateSkillByName: (name) {
          activated = name;
          return 'Activating $name';
        },
      );

      final result = registry.execute('/skills code-review');
      expect(result, 'Activating code-review');
      expect(opened, 0);
      expect(activated, 'code-review');
    });

    test('/history without args opens panel', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openHistoryPanel: () => opened++,
        historyActionByQuery: (q) {
          query = q;
          return 'Forking from $q';
        },
      );

      final result = registry.execute('/history');
      expect(result, '');
      expect(opened, 1);
      expect(query, isNull);
    });

    test('/history with args delegates to historyActionByQuery', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openHistoryPanel: () => opened++,
        historyActionByQuery: (q) {
          query = q;
          return 'Forking from $q';
        },
      );

      final result = registry.execute('/history 3');
      expect(result, 'Forking from 3');
      expect(opened, 0);
      expect(query, '3');
    });

    test('/resume without args opens panel', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openResumePanel: () => opened++,
        resumeSessionByQuery: (q) {
          query = q;
          return 'Resuming $q';
        },
      );

      final result = registry.execute('/resume');
      expect(result, '');
      expect(opened, 1);
      expect(query, isNull);
    });

    test('/resume with args delegates to resumeSessionByQuery', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openResumePanel: () => opened++,
        resumeSessionByQuery: (q) {
          query = q;
          return 'Resuming $q';
        },
      );

      final result = registry.execute('/resume abc123');
      expect(result, 'Resuming abc123');
      expect(opened, 0);
      expect(query, 'abc123');
    });

    test('/paths invokes pathsReport', () {
      var calls = 0;
      final registry = createRegistry(
        pathsReport: () {
          calls++;
          return 'GLUE_HOME  /tmp/.glue';
        },
      );

      final result = registry.execute('/paths');
      expect(result, 'GLUE_HOME  /tmp/.glue');
      expect(calls, 1);
    });

    test('/where is a hidden alias for /paths', () {
      var calls = 0;
      final registry = createRegistry(
        pathsReport: () {
          calls++;
          return 'report';
        },
      );

      final result = registry.execute('/where');
      expect(result, 'report');
      expect(calls, 1);
    });

    test('/open forwards args to openGlueTarget', () {
      List<String>? received;
      final registry = createRegistry(
        openGlueTarget: (args) {
          received = args;
          return 'Opening ${args.join(' ')}';
        },
      );

      final result = registry.execute('/open home');
      expect(result, 'Opening home');
      expect(received, ['home']);
    });

    test('/open without args still invokes openGlueTarget for usage', () {
      List<String>? received;
      final registry = createRegistry(
        openGlueTarget: (args) {
          received = args;
          return 'Usage: /open <target>';
        },
      );

      final result = registry.execute('/open');
      expect(result, 'Usage: /open <target>');
      expect(received, isEmpty);
    });

    test('/config without args delegates with empty args', () {
      List<String>? received;
      final registry = createRegistry(
        configAction: (args) {
          received = args;
          return 'Opening ~/.glue/config.yaml in editor';
        },
      );

      final result = registry.execute('/config');
      expect(result, 'Opening ~/.glue/config.yaml in editor');
      expect(received, isEmpty);
    });

    test('/config init forwards init subcommand', () {
      List<String>? received;
      final registry = createRegistry(
        configAction: (args) {
          received = args;
          return 'Created ./config.yaml';
        },
      );

      final result = registry.execute('/config init');
      expect(result, 'Created ./config.yaml');
      expect(received, ['init']);
    });

    test('/session without args delegates to sessionAction with empty list',
        () {
      List<String>? received;
      final registry = createRegistry(
        sessionAction: (args) {
          received = args;
          return 'Session Info';
        },
      );

      final result = registry.execute('/session');
      expect(result, 'Session Info');
      expect(received, isEmpty);
    });

    test('/session copy delegates to sessionAction with [copy]', () {
      List<String>? received;
      final registry = createRegistry(
        sessionAction: (args) {
          received = args;
          return '';
        },
      );

      registry.execute('/session copy');
      expect(received, ['copy']);
    });
  });

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

      final app = App(
        terminal: _NoopTerminal(),
        layout: Layout(_NoopTerminal()),
        editor: TextAreaEditor(),
        agent: AgentCore(llm: _NoopLlm(), tools: const {}),
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
  });
}
