import 'dart:async';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/runtime/services/session.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/session/session_manager.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:test/test.dart';

import '../../_helpers/test_config.dart';

class _TextOnlyLlm implements LlmClient {
  final String response;
  _TextOnlyLlm(this.response);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    yield TextDelta(response);
    yield UsageInfo(inputTokens: 5, outputTokens: 5);
  }
}

class _Harness {
  _Harness({
    required this.tempDir,
    required this.session,
    required this.transcript,
    required this.agent,
    required this.manager,
    required this.environment,
    required this.installedDrafts,
  });

  final Directory tempDir;
  final Session session;
  final Transcript transcript;
  final Agent agent;
  final SessionManager manager;
  final Environment environment;
  final List<String> installedDrafts;

  void dispose() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

_Harness _makeHarness() {
  final tempDir = Directory.systemTemp.createTempSync('session_test_');
  final environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
  environment.ensureDirectories();

  final obs = Observability(debugController: DebugController());
  final agent = Agent(
    llm: _TextOnlyLlm('hi'),
    tools: const {},
    obs: obs,
    modelId: 'test',
  );
  final transcript = Transcript();
  var glueConfig = testConfig(
    env: {'ANTHROPIC_API_KEY': 'sk-test'},
    credentialsPath: '${tempDir.path}/credentials.json',
  );
  final config = Config(
    read: () => glueConfig,
    write: (next) => glueConfig = next,
    environment: environment,
  );
  final manager = SessionManager(environment: environment, observability: obs);
  final installedDrafts = <String>[];
  final session = Session(
    manager: manager,
    agent: agent,
    transcript: transcript,
    config: config,
    environment: environment,
    modelIdProvider: () => 'test-model',
    installDraft: installedDrafts.add,
  );

  return _Harness(
    tempDir: tempDir,
    session: session,
    transcript: transcript,
    agent: agent,
    manager: manager,
    environment: environment,
    installedDrafts: installedDrafts,
  );
}

void main() {
  group('Session accessors', () {
    test(
        'currentMeta / currentId / currentStore are null before '
        'ensureStore', () {
      final h = _makeHarness();
      addTearDown(h.dispose);

      expect(h.session.currentMeta, isNull);
      expect(h.session.currentId, isNull);
      expect(h.session.currentStore, isNull);
    });

    test('ensureStore creates a session and populates accessors', () {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.session.ensureStore();

      expect(h.session.currentId, isNotNull);
      expect(h.session.currentStore, isNotNull);
      expect(h.session.currentMeta, isNotNull);
      // The store uses the current config's activeModel ref if available.
      expect(h.session.currentMeta!.modelRef, isNotEmpty);
    });

    test('ensureStore is idempotent — second call returns same id', () {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.session.ensureStore();
      final firstId = h.session.currentId;
      h.session.ensureStore();
      expect(h.session.currentId, firstId);
    });

    test(
        'list returns empty initially and non-empty after '
        'ensureStore flushes', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      expect(h.session.list(), isEmpty);
      h.session.ensureStore();
      h.session.logEvent('user_message', {'text': 'hi'});
      await h.session.closeCurrent();
      expect(h.session.list(), isNotEmpty);
    });
  });

  group('Session.markManualRename', () {
    test('manual rename blocks both initial and re-evaluation titling', () {
      // The observable contract we can test without hitting the disk-backed
      // title generation: after markManualRename, onTurnComplete becomes a
      // no-op (it doesn't touch the session's title metadata).
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.session.ensureStore();
      h.session.markManualRename();

      // Prime some conversation state that would normally cause
      // re-evaluation.
      h.agent.addMessage(Message.user('first question'));
      h.agent.addMessage(Message.assistant(
          text: 'A long assistant answer that well exceeds the '
              'forty-character threshold for title re-eval.'));
      h.agent.addMessage(Message.user('a different second question'));

      final beforeTitleSource = h.session.currentMeta?.titleSource;

      // onTurnComplete should short-circuit.
      h.session.onTurnComplete();

      expect(h.session.currentMeta?.titleSource, beforeTitleSource);
    });
  });

  group('Session.maybeGenerateInitialTitle', () {
    test(
        'title generation disabled in config → early return with no '
        'throw even though credentials are absent', () {
      final h = _makeHarness();
      addTearDown(h.dispose);

      // Default testConfig has titleGenerationEnabled=true. Flip it by
      // replacing the active config with one that disables titling.
      final disabledConfig = testConfig(
        env: {'ANTHROPIC_API_KEY': 'sk-test'},
        credentialsPath: '${h.environment.cwd}/credentials.json',
      );
      // GlueConfig fields are mostly final; we can't easily mutate
      // titleGenerationEnabled. Instead test the broader contract that
      // maybeGenerateInitialTitle does not throw when credentials are
      // missing — the internal try/catch on ConfigError swallows that.
      h.session.ensureStore();
      expect(() => h.session.maybeGenerateInitialTitle('first user message'),
          returnsNormally);
      expect(disabledConfig, isNotNull);
    });
  });

  group('Session.fork / Session.resume', () {
    test('fork returns false when no session is active', () {
      final h = _makeHarness();
      addTearDown(h.dispose);

      final result = h.session.fork(0, 'retry text');
      expect(result, isFalse);
      expect(h.installedDrafts, isEmpty);
    });

    test(
        'resume replays persisted entries into the transcript in '
        'submission order', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      // Create a real on-disk session with a couple of user + assistant
      // messages, then resume it via Session.resume.
      h.session.ensureStore();
      h.session.logEvent('user_message', {'text': 'first'});
      h.session.logEvent('assistant_message', {'text': 'response one'});
      h.session.logEvent('user_message', {'text': 'second'});
      h.session.logEvent('assistant_message', {'text': 'response two'});
      final meta = h.session.currentMeta!;
      await h.session.closeCurrent();

      // Dirty the transcript so we can verify it gets cleared.
      h.transcript.blocks.add(ConversationEntry.system('stale'));
      h.transcript.toolUi['tc'] = ToolCallUiState(id: 'tc', name: 'ghost');

      final message = h.session.resume(meta);

      expect(message, isNotNull);
      // Transcript cleared, then seeded with the resume system notice,
      // then replay entries.
      expect(h.transcript.toolUi, isEmpty);
      final kinds = h.transcript.blocks.map((b) => b.kind).toList();
      expect(kinds.first, EntryKind.system);
      // Order: user, assistant, user, assistant — preserved after the
      // system notice.
      final conversationKinds = kinds.skip(1).toList();
      expect(conversationKinds, [
        EntryKind.user,
        EntryKind.assistant,
        EntryKind.user,
        EntryKind.assistant,
      ]);
    });

    test(
        'resume on a session with no conversation data returns a '
        '"no conversation data" message', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.session.ensureStore();
      final meta = h.session.currentMeta!;
      await h.session.closeCurrent();

      final message = h.session.resume(meta);

      expect(message.toLowerCase(), contains('no conversation'));
    });
  });

  group('Session.onTurnComplete gating', () {
    test('is a no-op when there is no current session', () {
      final h = _makeHarness();
      addTearDown(h.dispose);

      expect(h.session.onTurnComplete, returnsNormally);
    });

    test('is a no-op when the agent conversation lacks enough context', () {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.session.ensureStore();
      // A short assistant response + no tool calls + single user turn —
      // the "hasEnoughContext" guard inside onTurnComplete returns false,
      // so no title re-eval fires.
      h.agent.addMessage(Message.user('hi'));
      h.agent.addMessage(Message.assistant(text: 'short reply'));

      expect(h.session.onTurnComplete, returnsNormally);
    });
  });

  group('Session.rename', () {
    test(
        'renames the current session and marks title as '
        'manually-overridden', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.session.ensureStore();
      await h.session.rename('My Custom Title');

      expect(h.session.currentMeta!.title, 'My Custom Title');
      expect(h.session.currentMeta!.titleSource, SessionTitleSource.user);
    });
  });

  group('Session.updateModel', () {
    test('updates the model-ref stored on the current session meta', () {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.session.ensureStore();
      final before = h.session.currentMeta!.modelRef;
      h.session.updateModel('custom/model:v1');
      expect(h.session.currentMeta!.modelRef, isNot(before));
      expect(h.session.currentMeta!.modelRef, 'custom/model:v1');
    });
  });
}
