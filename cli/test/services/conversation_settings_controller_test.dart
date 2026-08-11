import 'dart:io';

import 'package:glue/src/services/conversation_settings_controller.dart';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../_helpers/test_config.dart';

class _MarkerLlm implements LlmClient {
  _MarkerLlm(this.model);

  final ModelRef model;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    yield TextDelta(model.toString());
  }
}

class _LockedSessionManager extends SessionManager {
  _LockedSessionManager({required super.environment});

  int settingsUpdates = 0;

  @override
  SessionResumeResult resumeSession({
    required SessionMeta session,
    required AgentCore agent,
  }) => SessionResumeResult(
    message: 'locked',
    status: SessionResumeStatus.locked,
    replay: SessionReplay(
      entries: const [],
      userCount: 0,
      assistantCount: 0,
      totalUsage: buildUsageReport(usageEvents: const []),
    ),
  );

  @override
  void updateSessionModel({required String modelRef}) => settingsUpdates++;

  @override
  void updateSessionReasoning({
    required ReasoningEffort effort,
    required bool showThoughts,
  }) => settingsUpdates++;
}

void main() {
  late Directory tempDir;
  late Environment environment;
  late SessionManager sessions;
  late AgentCore agent;
  late GlueConfig config;
  late String modelId;
  late List<GlueConfig> builtConfigs;
  late ConversationSettingsController controller;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'conversation_settings_controller_test_',
    );
    environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
    environment.ensureDirectories();
    config = testConfig(
      activeModel: ModelRef.parse('anthropic/claude-sonnet-4-6'),
    );
    modelId = config.activeModel.modelId;
    sessions = SessionManager(environment: environment);
    sessions.ensureSessionStore(
      cwd: environment.cwd,
      modelRef: config.activeModel.toString(),
    );
    agent = AgentCore(llm: _MarkerLlm(config.activeModel), tools: const {});
    builtConfigs = [];
    controller = ConversationSettingsController(
      configGetter: () => config,
      configSetter: (value) => config = value,
      modelIdSetter: (value) => modelId = value,
      agent: agent,
      session: sessions,
      systemPrompt: 'test',
      configWriter: ConversationConfigWriter(environment.configYamlPath),
      clientBuilder: (next, _) {
        builtConfigs.add(next);
        return _MarkerLlm(next.activeModel);
      },
    );
  });

  tearDown(() {
    sessions.closeCurrent();
    tempDir.deleteSync(recursive: true);
  });

  test('user model change updates runtime, session, and config.yaml', () {
    final selected = ModelRef.parse('openai/o3');

    final result = controller.selectModel(
      selected,
      origin: SettingsChangeOrigin.user,
    );

    expect(result.applied, isTrue);
    expect(config.activeModel, selected);
    expect(modelId, 'o3');
    expect(agent.modelId, 'o3');
    expect((agent.llm as _MarkerLlm).model, selected);
    expect(sessions.currentStore?.meta.modelRef, 'openai/o3');
    final yaml =
        loadYaml(File(environment.configYamlPath).readAsStringSync()) as Map;
    expect(yaml['active_model'], 'openai/o3');
  });

  test('user reasoning change persists effort and thought visibility', () {
    final result = controller.setReasoning(
      const ReasoningConfig(effort: ReasoningEffort.high, showThoughts: true),
      origin: SettingsChangeOrigin.user,
    );

    expect(result.applied, isTrue);
    expect(config.reasoning.effort, ReasoningEffort.high);
    expect(config.reasoning.showThoughts, isTrue);
    expect(sessions.currentStore?.meta.reasoningEffort, 'high');
    expect(sessions.currentStore?.meta.showThoughts, isTrue);
    final yaml =
        loadYaml(File(environment.configYamlPath).readAsStringSync()) as Map;
    expect((yaml['reasoning'] as Map)['effort'], 'high');
    expect((yaml['reasoning'] as Map)['show_thoughts'], isTrue);
  });

  test('resume restores exact settings without changing config.yaml', () {
    File(environment.configYamlPath).writeAsStringSync('''# defaults
active_model: anthropic/claude-sonnet-4-6
reasoning:
  effort: low
  show_thoughts: false
''');
    final before = File(environment.configYamlPath).readAsStringSync();
    final meta = SessionMeta(
      id: const SessionId('restored'),
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-5',
      startTime: DateTime.now(),
      reasoningEffort: 'high',
      showThoughts: true,
    );
    SessionStore(
      sessionDir: environment.sessionDir(meta.id),
      meta: meta,
    ).logEvent('user_message', {'text': 'earlier'});

    final resumed = controller.resume(meta);

    expect(resumed.sessionResult.status, SessionResumeStatus.resumed);
    expect(config.activeModel, ModelRef.parse('anthropic/claude-sonnet-5'));
    expect(config.reasoning.effort, ReasoningEffort.high);
    expect(config.reasoning.showThoughts, isTrue);
    expect(File(environment.configYamlPath).readAsStringSync(), before);
  });

  test('invalid stored values warn and retain current valid settings', () {
    final meta = SessionMeta(
      id: const SessionId('invalid-settings'),
      cwd: environment.cwd,
      modelRef: 'missing-provider/model',
      startTime: DateTime.now(),
      reasoningEffort: 'extreme',
    );

    final prepared = controller.prepareRestore(meta);

    expect(prepared.config.activeModel, config.activeModel);
    expect(prepared.config.reasoning.effort, config.reasoning.effort);
    expect(prepared.warnings, hasLength(2));
  });

  test('locked resume does not apply prepared settings', () {
    final lockedSessions = _LockedSessionManager(environment: environment);
    final originalLlm = agent.llm;
    controller = ConversationSettingsController(
      configGetter: () => config,
      configSetter: (value) => config = value,
      modelIdSetter: (value) => modelId = value,
      agent: agent,
      session: lockedSessions,
      systemPrompt: 'test',
      configWriter: ConversationConfigWriter(environment.configYamlPath),
      clientBuilder: (next, _) => _MarkerLlm(next.activeModel),
    );
    final meta = SessionMeta(
      id: const SessionId('locked'),
      cwd: environment.cwd,
      modelRef: 'anthropic/claude-sonnet-5',
      startTime: DateTime.now(),
      reasoningEffort: 'high',
    );

    final resumed = controller.resume(meta);

    expect(resumed.sessionResult.status, SessionResumeStatus.locked);
    expect(config.activeModel.toString(), 'anthropic/claude-sonnet-4-6');
    expect(identical(agent.llm, originalLlm), isTrue);
    expect(lockedSessions.settingsUpdates, 0);
  });

  test('incompatible model switch persists the effective auto effort', () {
    controller.setReasoning(
      const ReasoningConfig(effort: ReasoningEffort.high),
      origin: SettingsChangeOrigin.sessionRestore,
    );

    final result = controller.selectModel(
      ModelRef.parse('openai/o3'),
      origin: SettingsChangeOrigin.user,
    );

    expect(result.message, contains('reset to Auto'));
    expect(config.reasoning.effort, ReasoningEffort.auto);
    expect(sessions.currentStore?.meta.reasoningEffort, 'auto');
    final yaml =
        loadYaml(File(environment.configYamlPath).readAsStringSync()) as Map;
    expect((yaml['reasoning'] as Map)['effort'], 'auto');
  });

  test('persistence failure keeps runtime change and reports session-only', () {
    final badWriter = ConversationConfigWriter(tempDir.path);
    controller = ConversationSettingsController(
      configGetter: () => config,
      configSetter: (value) => config = value,
      modelIdSetter: (value) => modelId = value,
      agent: agent,
      session: sessions,
      systemPrompt: 'test',
      configWriter: badWriter,
      clientBuilder: (next, _) => _MarkerLlm(next.activeModel),
    );

    final result = controller.selectModel(
      ModelRef.parse('openai/o3'),
      origin: SettingsChangeOrigin.user,
    );

    expect(result.applied, isTrue);
    expect(config.activeModel, ModelRef.parse('openai/o3'));
    expect(result.message, contains('session-only'));
  });
}
