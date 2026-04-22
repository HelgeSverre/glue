import 'dart:convert';
import 'dart:io';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/session/session_manager.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:test/test.dart';

class _NoopLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    yield TextDelta('ok');
    yield UsageInfo(inputTokens: 1, outputTokens: 1);
  }
}

void main() {
  late Directory tempDir;
  late Environment environment;
  late AgentCore agent;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_manager_test_');
    environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
    environment.ensureDirectories();
    agent = AgentCore(llm: _NoopLlm(), tools: const {});
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('ensureSessionStore lazily creates and reuses session store', () {
    final manager = SessionManager(environment: environment);

    final first = manager.ensureSessionStore(
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-4.6',
    );
    final second = manager.ensureSessionStore(
      cwd: environment.cwd,
      modelRef: 'openai/gpt-4.1',
    );

    expect(identical(first, second), isTrue);
    expect(Directory(first.sessionDir).existsSync(), isTrue);
  });

  test('resumeSession restores agent conversation and replay entries', () {
    final manager = SessionManager(environment: environment);
    final meta = SessionMeta(
      id: 'resume-1',
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-4.6',
      startTime: DateTime.now(),
    );
    final store =
        SessionStore(sessionDir: environment.sessionDir(meta.id), meta: meta);
    store.logEvent('user_message', {'text': 'hello'});
    store.logEvent('assistant_message', {'text': 'hi'});
    store.logEvent('tool_call', {
      'id': 'c1',
      'name': 'read_file',
      'arguments': {'path': 'README.md'},
    });
    store.logEvent('tool_result', {'call_id': 'c1', 'content': 'file content'});

    final result = manager.resumeSession(session: meta, agent: agent);

    expect(result.hasConversation, isTrue);
    expect(result.message, contains('Restored 1 user + 1 assistant messages.'));
    expect(result.replay.entries, hasLength(4));
    expect(result.replay.firstUserMessage, 'hello');
    expect(agent.conversation.map((m) => m.role), [
      Role.user,
      Role.assistant,
      Role.toolResult,
    ]);
    expect(manager.currentSessionId, 'resume-1');
  });

  test('resumeSession on empty conversation does not create extra session', () {
    final manager = SessionManager(environment: environment);
    final meta = SessionMeta(
      id: 'resume-empty',
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-4.6',
      startTime: DateTime.now(),
    );
    SessionStore(sessionDir: environment.sessionDir(meta.id), meta: meta);

    final result = manager.resumeSession(session: meta, agent: agent);

    expect(result.hasConversation, isFalse);
    expect(result.message, contains('no conversation data'));
    final dirs = Directory(environment.sessionsDir)
        .listSync()
        .whereType<Directory>()
        .toList();
    expect(dirs, hasLength(1));
    expect(manager.currentSessionId, 'resume-empty');
  });

  test('forkSession creates new session and replays truncated history', () {
    final manager = SessionManager(environment: environment);
    final oldStore = manager.ensureSessionStore(
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-4.6',
    );
    oldStore.logEvent('user_message', {'text': 'first question'});
    oldStore.logEvent('assistant_message', {'text': 'first answer'});
    oldStore.logEvent('user_message', {'text': 'second question'});
    final oldId = oldStore.meta.id;

    final result = manager.forkSession(
      userMessageIndex: 0,
      messageText: 'first question',
      agent: agent,
    );

    expect(result, isNotNull);
    expect(result!.message, contains('Forked from session'));
    expect(result.draftText, 'first question');
    expect(manager.currentSessionId, isNot(oldId));
    expect(manager.currentStore!.meta.forkedFrom, oldId);

    final events =
        SessionStore.loadConversation(manager.currentStore!.sessionDir);
    expect(events.where((e) => e['type'] == 'user_message'), hasLength(1));
    expect(events.first['text'], 'first question');
    expect(agent.conversation.map((m) => m.role), [Role.user]);
  });

  test('updateSessionModel persists modelRef to meta.json', () {
    final manager = SessionManager(environment: environment);
    final store = manager.ensureSessionStore(
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-4.6',
    );

    manager.updateSessionModel(modelRef: 'openai/gpt-4.1');

    final metaJson = jsonDecode(
      File('${store.sessionDir}/meta.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(metaJson['model_ref'], 'openai/gpt-4.1');
  });

  test('generateTitle sets provisional auto title and logs event', () async {
    final manager = SessionManager(environment: environment);
    final store = manager.ensureSessionStore(
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-4.6',
    );

    await manager.generateTitle(
      userMessage: 'Summarize this bug',
      generate: (_) async => 'Fix flaky docker test',
    );

    expect(store.meta.title, 'Fix flaky docker test');
    expect(store.meta.titleSource, SessionTitleSource.auto);
    expect(store.meta.titleState, SessionTitleState.provisional);
    expect(store.meta.titleGenerationCount, 1);
    final events = SessionStore.loadConversation(store.sessionDir);
    expect(events.last['type'], 'title_generated');
    expect(events.last['title'], 'Fix flaky docker test');
  });

  test('renameTitle marks title as user-owned and stable', () async {
    final manager = SessionManager(environment: environment);
    final store = manager.ensureSessionStore(
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-4.6',
    );

    await manager.renameTitle('Manual title');

    expect(store.meta.title, 'Manual title');
    expect(store.meta.titleSource, SessionTitleSource.user);
    expect(store.meta.titleState, SessionTitleState.stable);
    expect(store.meta.titleRenamedAt, isNotNull);
  });

  test('reevaluateTitle promotes provisional auto title to stable', () async {
    final manager = SessionManager(environment: environment);
    final store = manager.ensureSessionStore(
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-4.6',
    );
    await manager.generateTitle(
      userMessage: 'help debug this',
      generate: (_) async => 'Help debug this',
    );

    await manager.reevaluateTitle(
      context: const TitleContext(
        firstUserMessage: 'help debug this',
        latestAssistantMessage: 'The Docker resume tests are flaky in CI.',
        toolNames: ['read_file'],
      ),
      generate: (_) async => 'Docker resume test flakiness',
    );

    expect(store.meta.title, 'Docker resume test flakiness');
    expect(store.meta.titleState, SessionTitleState.stable);
    expect(store.meta.titleGenerationCount, 2);
  });
}
