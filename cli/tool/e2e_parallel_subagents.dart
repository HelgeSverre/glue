// One-off verification script. Drives `AgentManager.spawnParallel` against
// a local Ollama model, persists subagent activity to a real
// `conversation.jsonl`, then re-runs the share builder + HTML renderer to
// confirm parallel siblings render correctly.
//
// Run from `cli/`:
//   dart run tool/e2e_parallel_subagents.dart
//
// Requires Ollama running locally with `gemma4:latest` pulled.
//
// ignore_for_file: avoid_print, prefer_const_constructors

import 'dart:convert';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:path/path.dart' as p;

const _model = 'gemma4:latest';
const _ollamaUrl = 'http://localhost:11434';

void main() async {
  final tmpRoot = Directory.systemTemp.createTempSync('glue-parallel-e2e-');
  final fixturesDir = Directory(p.join(tmpRoot.path, 'fixtures'))..createSync();
  for (final colour in ['red', 'green', 'blue']) {
    final dir = Directory(p.join(fixturesDir.path, colour))..createSync();
    File(p.join(dir.path, 'note.txt')).writeAsStringSync('$colour content\n');
  }
  final sessionDir = p.join(tmpRoot.path, 'session');

  final store = SessionStore(
    sessionDir: sessionDir,
    meta: SessionMeta(
      id: SessionId('e2e-parallel'),
      cwd: fixturesDir.path,
      modelRef: 'ollama/$_model',
      startTime: DateTime.now().toUtc(),
    ),
  );

  final llmFactory = _OllamaFactory();
  final config = GlueConfig(
    activeModel: ModelRef.parse('ollama/$_model'),
    catalogData: bundledCatalog,
    credentials: CredentialStore(
      path: p.join(tmpRoot.path, 'creds.json'),
      env: {},
    ),
    adapters: AdapterRegistry([
      AnthropicAdapter(),
      OpenAiCompatibleAdapter(),
      OllamaAdapter(),
    ]),
  );
  final manager = AgentManager(
    tools: {
      'list_directory': ListDirectoryTool(
          LocalWorkspace(WorkspaceMapping.host(fixturesDir.path))),
      'read_file':
          ReadFileTool(LocalWorkspace(WorkspaceMapping.host(fixturesDir.path))),
    },
    llmFactory: llmFactory,
    config: config,
    systemPrompt:
        'You are a focused agent. Use the read_file and list_directory '
        'tools to answer the question concisely.',
    onPersistEvent: store.logEvent,
  );

  print('Spawning 3 parallel subagents against ${fixturesDir.path}...');
  final results = await manager.spawnParallel(
    tasks: [
      'Read ${fixturesDir.path}/red/note.txt and report its content verbatim.',
      'Read ${fixturesDir.path}/green/note.txt and report its content verbatim.',
      'Read ${fixturesDir.path}/blue/note.txt and report its content verbatim.',
    ],
  );
  print('Subagents returned ${results.length} results.\n');

  // --- Inspect persisted JSONL ---
  final jsonlPath = p.join(sessionDir, 'conversation.jsonl');
  final lines = File(jsonlPath).readAsLinesSync();
  final events = [
    for (final line in lines)
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];

  final spawned = events.where((e) => e['type'] == 'subagent_spawned').toList();
  print('subagent_spawned rows: ${spawned.length}');
  for (final row in spawned) {
    final id = row['subagent_id'];
    final parent = row['parent_subagent_id'];
    final depth = row['depth'];
    final index = row['index'];
    print('  id=$id depth=$depth index=$index parent=$parent');
  }

  final completed =
      events.where((e) => e['type'] == 'subagent_completed').toList();
  print('subagent_completed rows: ${completed.length}');

  // --- Build transcript and verify ---
  final transcript = ShareTranscriptBuilder().build(events);
  final groups = transcript.entries
      .where((e) => e.kind == ShareEntryKind.subagentGroup)
      .toList();

  print('\nTop-level subagent groups: ${groups.length}');
  for (final g in groups) {
    print(
        '  ${g.subagentId}  nestingLevel=${g.nestingLevel}  children=${g.children.length}');
  }

  // --- Render HTML ---
  final htmlPath = p.join(tmpRoot.path, 'transcript.html');
  final html = ShareHtmlRenderer().render(
    meta: store.meta,
    transcript: transcript,
    exportedAt: DateTime.now().toUtc(),
  );
  File(htmlPath).writeAsStringSync(html);
  print('\nHTML written to: $htmlPath');

  // --- Asserts ---
  final ok = spawned.length == 3 &&
      completed.length == 3 &&
      spawned.every((row) =>
          (row['depth'] as int? ?? -1) == 0 &&
          row['parent_subagent_id'] == null) &&
      groups.length == 3 &&
      groups.every((g) => g.nestingLevel == 0);
  print(ok ? '\nPASS' : '\nFAIL');
  exitCode = ok ? 0 : 1;
}

class _OllamaFactory implements LlmClientFactory {
  @override
  LlmClient createFor(ModelRef ref, {required String systemPrompt}) {
    return OllamaClient(
      model: ref.modelId,
      systemPrompt: systemPrompt,
      baseUrl: _ollamaUrl,
    );
  }

  @override
  LlmClient createFromConfig({required String systemPrompt}) =>
      throw UnimplementedError();
}
