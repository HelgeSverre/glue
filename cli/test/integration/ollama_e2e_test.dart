@Tags(['e2e'])
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_runner.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/llm/ollama_client.dart';

const _model = 'qwen3:1.7b';
const _ollamaUrl = 'http://localhost:11434';

/// Small models are non-deterministic — retry flaky tool-calling tests.
const _maxRetries = 3;

String _systemPrompt() => '''
You are a helpful coding assistant running in ${Directory.current.path}.
You have access to tools. Always use tools when asked to read files, list
directories, run commands, or search code. Be concise in your responses.
For file paths, use paths relative to the current directory (e.g. "pubspec.yaml").
''';

Future<bool> _ollamaAvailable() async {
  try {
    final r = await http
        .get(Uri.parse('$_ollamaUrl/api/tags'))
        .timeout(const Duration(seconds: 3));
    if (r.statusCode != 200) return false;
    return r.body.contains(_model);
  } catch (_) {
    return false;
  }
}

/// Run [fn] up to [maxRetries] times, returning on first success.
Future<void> retryTest(Future<void> Function() fn,
    {int maxRetries = _maxRetries}) async {
  Object? lastError;
  for (var i = 0; i < maxRetries; i++) {
    try {
      await fn();
      return;
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError!;
}

void main() {
  late bool available;

  setUpAll(() async {
    available = await _ollamaAvailable();
  });

  AgentCore makeAgent({Map<String, Tool>? tools}) {
    final llm = OllamaClient(
      model: _model,
      systemPrompt: _systemPrompt(),
      baseUrl: _ollamaUrl,
    );
    return AgentCore(
      llm: llm,
      tools: tools ?? {},
      modelId: _model,
    );
  }

  AgentRunner makeRunner(AgentCore core) => AgentRunner(
        core: core,
        policy: ToolApprovalPolicy.autoApproveAll,
        onEvent: (e) {
          if (e is AgentToolCall) {
            // ignore: avoid_print
            print('[TOOL] ${e.call.name}(${e.call.arguments})');
          }
        },
      );

  group('Ollama e2e', () {
    test('simple text response', () async {
      if (!available) {
        markTestSkipped('Ollama not available or $_model not pulled');
        return;
      }
      await retryTest(() async {
        final agent = makeAgent();
        final runner = makeRunner(agent);
        final result = await runner.runToCompletion(
          'What is 2 + 2? Reply with just the number.',
        );
        expect(result, contains('4'));
      });
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('read_file tool call', () async {
      if (!available) {
        markTestSkipped('Ollama not available or $_model not pulled');
        return;
      }
      await retryTest(() async {
        final agent = makeAgent(tools: {
          'read_file': ReadFileTool(),
        });
        final runner = makeRunner(agent);
        final result = await runner.runToCompletion(
          'Use the read_file tool to read "pubspec.yaml" and tell me the package name.',
        );
        final toolResults =
            agent.conversation.where((m) => m.role == Role.toolResult).toList();
        expect(toolResults, isNotEmpty, reason: 'read_file should be called');
        expect(result.toLowerCase(), contains('glue'));
      });
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('list_directory tool call', () async {
      if (!available) {
        markTestSkipped('Ollama not available or $_model not pulled');
        return;
      }
      await retryTest(() async {
        final agent = makeAgent(tools: {
          'list_directory': ListDirectoryTool(),
        });
        final runner = makeRunner(agent);
        final result = await runner.runToCompletion(
          'Use the list_directory tool to list "." and tell me if pubspec.yaml exists.',
        );
        expect(
            result.toLowerCase(), anyOf(contains('yes'), contains('pubspec')));
      });
    }, timeout: const Timeout(Duration(seconds: 120)));

    // Note: bash tool test omitted — small models refuse to call a tool
    // literally named "bash" (safety training). The bash tool works fine
    // with larger models (tested manually with claude/gpt-4).

    test('grep tool finds code', () async {
      if (!available) {
        markTestSkipped('Ollama not available or $_model not pulled');
        return;
      }
      await retryTest(() async {
        final agent = makeAgent(tools: {
          'grep': GrepTool(),
        });
        final runner = makeRunner(agent);
        final result = await runner.runToCompletion(
          'Use the grep tool to search for "class AgentCore" in the "lib/" directory.',
        );
        expect(result.toLowerCase(), contains('agent_core'));
      });
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
