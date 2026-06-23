import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue/glue.dart';
import 'package:test/test.dart';

/// Records every inbound history list and yields a fixed (or queued) reply.
class _RecordingLlm implements LlmClient {
  _RecordingLlm({List<String>? replies}) : _replies = replies ?? const [];

  final List<String> _replies;
  int _turn = 0;

  /// Full inbound message history captured per turn, before yielding.
  final List<List<Message>> calls = [];

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    calls.add(List.of(messages));
    final reply = _turn < _replies.length ? _replies[_turn] : 'reply';
    _turn++;
    yield TextDelta(reply);
    yield UsageInfo(inputTokens: 1, outputTokens: 1);
  }
}

/// Stdin stub that reports no terminal and immediate EOF, so the
/// print-mode stdin drain returns instantly under `dart test`.
class _EofStdin implements Stdin {
  @override
  bool get hasTerminal => false;

  @override
  String? readLineSync({
    Encoding encoding = systemEncoding,
    bool retainNewlines = false,
  }) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

App _printApp({
  required _RecordingLlm llm,
  required Environment environment,
  required String? prompt,
  bool jsonMode = false,
  String? resumeSessionId,
  bool startupContinue = false,
}) {
  return App(
    terminal: _NoopTerminal(),
    layout: Layout(_NoopTerminal()),
    editor: TextAreaEditor(),
    agent: AgentCore(llm: llm, tools: const {}),
    modelId: 'anthropic/claude-sonnet-4.6',
    printMode: true,
    jsonMode: jsonMode,
    startupPrompt: prompt,
    resumeSessionId: resumeSessionId,
    startupContinue: startupContinue,
    environment: environment,
  );
}

/// Runs print mode with a stubbed EOF stdin (so the drain does not hang),
/// returning captured stdout and stderr.
Future<({String stdout, String stderr})> _runPrint(App app) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final spec = ZoneSpecification(
    print: (self, parent, zone, line) => out.writeln(line),
  );
  await IOOverrides.runZoned(
    () => runZoned(app.run, zoneSpecification: spec),
    stdin: _EofStdin.new,
    stdout: () => _CaptureStdout(out),
    stderr: () => _CaptureStdout(err),
  );
  return (stdout: out.toString(), stderr: err.toString());
}

/// Minimal IOSink-backed stdout/stderr capture.
class _CaptureStdout implements Stdout {
  _CaptureStdout(this._buf);
  final StringBuffer _buf;

  @override
  void write(Object? object) => _buf.write(object);
  @override
  void writeln([Object? object = '']) => _buf.writeln(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) =>
      _buf.write(objects.join(sep));
  @override
  void writeCharCode(int charCode) => _buf.writeCharCode(charCode);
  @override
  void add(List<int> data) => _buf.write(systemEncoding.decode(data));
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  bool get hasTerminal => false;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding e) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late Directory tempDir;
  late Environment environment;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('print_mode_session_test_');
    environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
    environment.ensureDirectories();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  SessionMeta seedSession(String id, {String? model}) {
    final meta = SessionMeta(
      id: SessionId(id),
      cwd: environment.cwd,
      modelRef: model ?? 'anthropic/claude-sonnet-4.6',
      startTime: DateTime.now(),
    );
    final store = SessionStore(
      sessionDir: environment.sessionDir(meta.id),
      meta: meta,
    );
    store.logEvent('user_message', {'text': 'first q'});
    store.logEvent('assistant_message', {'text': 'first a'});
    return meta;
  }

  List<Map<String, dynamic>> conversationFor(SessionMeta meta) =>
      SessionStore.loadConversation(environment.sessionDir(meta.id));

  test('print mode persists a session (bug-1 fix)', () async {
    final llm = _RecordingLlm(replies: ['reply']);
    final app = _printApp(llm: llm, environment: environment, prompt: 'hello');

    await _runPrint(app);

    final sessions = SessionStore.listSessions(environment.sessionsDir);
    expect(sessions, hasLength(1));

    final convo = SessionStore.loadConversation(
      environment.sessionDir(sessions.first.id),
    );
    final types = convo.map((e) => e['type']).toList();
    expect(types, contains('user_message'));
    expect(types, contains('assistant_message'));
    expect(
      convo.firstWhere((e) => e['type'] == 'user_message')['text'],
      'hello',
    );
    expect(
      convo.firstWhere((e) => e['type'] == 'assistant_message')['text'],
      'reply',
    );
  });

  test('json envelope reports a non-null session_id (bug-1 surface)', () async {
    final llm = _RecordingLlm(replies: ['reply']);
    final app = _printApp(
      llm: llm,
      environment: environment,
      prompt: 'hello',
      jsonMode: true,
    );

    final result = await _runPrint(app);

    final envelope = jsonDecode(result.stdout) as Map<String, dynamic>;
    final sessions = SessionStore.listSessions(environment.sessionsDir);
    expect(sessions, hasLength(1));
    expect(envelope['session_id'], isNotNull);
    expect(envelope['session_id'], sessions.first.id.value);
  });

  test('--continue replays prior turn into the LLM (bug-2 fix)', () async {
    final seeded = seedSession('continue-target');

    final llm = _RecordingLlm(replies: ['second a']);
    final app = _printApp(
      llm: llm,
      environment: environment,
      prompt: 'second q',
      startupContinue: true,
    );

    final result = await _runPrint(app);

    // Replay proof: the resumed history reached the model.
    expect(llm.calls, isNotEmpty);
    final lastTexts = llm.calls.last.map((m) => m.text).toList();
    expect(lastTexts, contains('first q'));
    expect(lastTexts, contains('first a'));
    expect(lastTexts, contains('second q'));

    // stderr note about continuing was emitted.
    expect(result.stderr, contains('Continuing session'));

    // No new session: the existing one was appended to.
    final sessions = SessionStore.listSessions(environment.sessionsDir);
    expect(sessions, hasLength(1));
    expect(sessions.first.id.value, 'continue-target');

    final convo = conversationFor(seeded);
    final userTexts = convo
        .where((e) => e['type'] == 'user_message')
        .map((e) => e['text'])
        .toList();
    final assistantTexts = convo
        .where((e) => e['type'] == 'assistant_message')
        .map((e) => e['text'])
        .toList();
    expect(userTexts, containsAll(['first q', 'second q']));
    expect(assistantTexts, containsAll(['first a', 'second a']));
  });

  test('--continue with no sessions falls back to fresh', () async {
    final llm = _RecordingLlm(replies: ['reply']);
    final app = _printApp(
      llm: llm,
      environment: environment,
      prompt: 'hi',
      startupContinue: true,
    );

    final result = await _runPrint(app);

    expect(result.stderr, contains('No sessions to continue'));

    final sessions = SessionStore.listSessions(environment.sessionsDir);
    expect(sessions, hasLength(1));

    final convo = SessionStore.loadConversation(
      environment.sessionDir(sessions.first.id),
    );
    expect(convo.firstWhere((e) => e['type'] == 'user_message')['text'], 'hi');
    expect(
      convo.firstWhere((e) => e['type'] == 'assistant_message')['text'],
      'reply',
    );
  });

  test('--resume <id> appends to the same session', () async {
    final seeded = seedSession('resume-target');

    final llm = _RecordingLlm(replies: ['again a']);
    final app = _printApp(
      llm: llm,
      environment: environment,
      prompt: 'again',
      resumeSessionId: 'resume-target',
    );

    await _runPrint(app);

    final sessions = SessionStore.listSessions(environment.sessionsDir);
    expect(sessions, hasLength(1));
    expect(sessions.first.id.value, 'resume-target');

    final convo = conversationFor(seeded);
    final userTexts = convo
        .where((e) => e['type'] == 'user_message')
        .map((e) => e['text'])
        .toList();
    expect(userTexts, containsAll(['first q', 'again']));

    // Resumed history reached the model.
    final lastTexts = llm.calls.last.map((m) => m.text).toList();
    expect(lastTexts, contains('first q'));
    expect(lastTexts, contains('first a'));
  });

  test('bare --resume errors and persists nothing', () async {
    final llm = _RecordingLlm(replies: ['reply']);
    final app = _printApp(
      llm: llm,
      environment: environment,
      prompt: 'whatever',
      resumeSessionId: '',
    );

    final result = await _runPrint(app);

    expect(
      result.stderr,
      contains(
        'Error: --print does not support bare --resume; pass a session ID.',
      ),
    );
    expect(llm.calls, isEmpty);
    expect(SessionStore.listSessions(environment.sessionsDir), isEmpty);
  });

  test('--resume <unknown-id> prints not-found and returns', () async {
    final llm = _RecordingLlm(replies: ['reply']);
    final app = _printApp(
      llm: llm,
      environment: environment,
      prompt: 'whatever',
      resumeSessionId: 'nope',
    );

    final result = await _runPrint(app);

    expect(result.stderr, contains('Session nope not found.'));
    expect(llm.calls, isEmpty);
    expect(SessionStore.listSessions(environment.sessionsDir), isEmpty);
  });

  test('resume-by-id takes precedence over --continue', () async {
    // 'resume-target' is older than the most-recent session.
    final target = seedSession('resume-target');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    seedSession('newer-session');

    final llm = _RecordingLlm(replies: ['again a']);
    final app = _printApp(
      llm: llm,
      environment: environment,
      prompt: 'again',
      resumeSessionId: 'resume-target',
      startupContinue: true,
    );

    await _runPrint(app);

    // Appended to the explicit id, not listSessions().first.
    final targetConvo = conversationFor(target);
    final targetUsers = targetConvo
        .where((e) => e['type'] == 'user_message')
        .map((e) => e['text'])
        .toList();
    expect(targetUsers, containsAll(['first q', 'again']));

    final lastTexts = llm.calls.last.map((m) => m.text).toList();
    expect(lastTexts, contains('first q'));
  });
}
