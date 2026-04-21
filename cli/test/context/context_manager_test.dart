import 'dart:async';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/context/context_budget.dart';
import 'package:glue/src/context/context_config.dart';
import 'package:glue/src/context/context_estimator.dart';
import 'package:glue/src/context/context_manager.dart';
import 'package:glue/src/context/conversation_compactor.dart';
import 'package:glue/src/context/sliding_window_trimmer.dart';
import 'package:glue/src/context/tool_result_trimmer.dart';
import 'package:test/test.dart';

// A minimal budget with tiny thresholds so tests run quickly.
ContextBudget _tinyBudget({
  int contextWindow = 1000,
  double compactThreshold = 0.80,
  double criticalThreshold = 0.95,
}) {
  return ContextBudget(
    contextWindowTokens: contextWindow,
    maxOutputTokens: 50,
    reservedHeadroom: 100,
    compactThreshold: compactThreshold,
    criticalThreshold: criticalThreshold,
  );
}

ContextManager _managerWith({
  ContextBudget? budget,
  ConversationCompactor? compactor,
  bool autoCompact = true,
}) {
  final est = ContextEstimator();
  return ContextManager(
    budget: budget ?? _tinyBudget(),
    estimator: est,
    slidingWindow: SlidingWindowTrimmer(estimator: est),
    toolTrimmer: const ToolResultTrimmer(),
    compactor: compactor,
    autoCompact: autoCompact,
  );
}

/// A stub LLM that returns a single fixed response.
class _StubLlm implements LlmClient {
  final String response;
  _StubLlm(this.response);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    yield TextDelta(response);
    yield UsageInfo(inputTokens: 10, outputTokens: 5);
  }
}

/// A stub compactor that tracks calls and returns a fixed compacted list.
class _TrackingCompactor extends ConversationCompactor {
  int callCount = 0;

  _TrackingCompactor()
      : super(summaryClient: _StubLlm('Summary of older turns.'));

  @override
  Future<List<Message>> compact(List<Message> conversation) async {
    callCount++;
    return [
      Message.user('[Session context summary]\nSummary of older turns.'),
      ...conversation.sublist(
        conversation.length > 2 ? conversation.length - 2 : 0,
      ),
    ];
  }
}

List<Message> _longConversation(int turns) {
  final messages = <Message>[];
  for (var i = 0; i < turns; i++) {
    messages.add(Message.user('User turn $i: ${'word ' * 50}'));
    messages
        .add(Message.assistant(text: 'Assistant reply $i: ${'reply ' * 50}'));
  }
  return messages;
}

void main() {
  group('ContextManager.prepareForLlm', () {
    test('returns same messages when within budget', () async {
      final manager = _managerWith(budget: _tinyBudget(contextWindow: 100000));
      final conv = [Message.user('Hello')];
      final result = await manager.prepareForLlm(conv);
      // Only tier 1 (tool result trimming) runs; no tool results, so identical.
      expect(result.length, conv.length);
    });

    test('applies Tier 3 when critically over budget', () async {
      // Budget so tiny that even a short conversation triggers Tier 3.
      const budget = ContextBudget(
        contextWindowTokens: 200,
        maxOutputTokens: 20,
        reservedHeadroom: 50,
        compactThreshold: 0.80,
        criticalThreshold: 0.85,
      );
      final manager = _managerWith(budget: budget, autoCompact: false);
      final conv = _longConversation(10);
      final result = await manager.prepareForLlm(conv);
      expect(result.length, lessThan(conv.length));
    });

    test('Tier 2 compaction is skipped when autoCompact is false', () async {
      const budget = ContextBudget(
        contextWindowTokens: 200,
        maxOutputTokens: 20,
        reservedHeadroom: 50,
        compactThreshold: 0.01, // extremely low threshold
        criticalThreshold: 0.999,
      );
      final compactor = _TrackingCompactor();
      final manager = _managerWith(
        budget: budget,
        compactor: compactor,
        autoCompact: false,
      );
      final conv = _longConversation(3);
      await manager.prepareForLlm(conv);
      expect(compactor.callCount, 0);
    });

    test('Tier 2 fires when estimated > compactAt and compactor available',
        () async {
      // Force compaction to trigger by using tiny budget.
      const budget = ContextBudget(
        contextWindowTokens: 100,
        maxOutputTokens: 10,
        reservedHeadroom: 10,
        compactThreshold: 0.01, // fires at 0.01 * 90 ≈ 0
        criticalThreshold: 0.999,
      );
      final compactor = _TrackingCompactor();
      final manager = _managerWith(
        budget: budget,
        compactor: compactor,
        autoCompact: true,
      );
      final conv = _longConversation(3);
      await manager.prepareForLlm(conv);
      expect(compactor.callCount, 1);
    });

    test('uses emergency-trimmed messages when requestEmergencyTrim was called',
        () async {
      // Use a very small budget so emergency trim actually drops messages.
      const budget = ContextBudget(
        contextWindowTokens: 300,
        maxOutputTokens: 20,
        reservedHeadroom: 50,
        compactThreshold: 0.80,
        criticalThreshold: 0.95,
      );
      final est = ContextEstimator();
      final manager = ContextManager(
        budget: budget,
        estimator: est,
        slidingWindow: SlidingWindowTrimmer(estimator: est),
      );
      final conv = _longConversation(10);
      manager.requestEmergencyTrim(conv);

      final result = await manager.prepareForLlm(conv);
      // Emergency trim should produce fewer messages than the original.
      expect(result.length, lessThan(conv.length));
    });

    test('emergency trim flag is consumed after one call', () async {
      final manager = _managerWith(budget: _tinyBudget(contextWindow: 100000));
      final conv = [Message.user('Hi')];
      manager.requestEmergencyTrim(conv);

      await manager.prepareForLlm(conv); // consumes the flag
      // Second call should run normal tiers.
      final result2 = await manager.prepareForLlm(conv);
      expect(result2.length, conv.length);
    });
  });

  group('ContextManager.forceCompact', () {
    test('returns zero removedTokens when conversation is short', () async {
      final manager = _managerWith(budget: _tinyBudget(contextWindow: 100000));
      final conv = [Message.user('Hi')];
      final result = await manager.forceCompact(conv);
      // Nothing to compact; summary ≥ 0.
      expect(result.removedTokens, greaterThanOrEqualTo(0));
    });

    test('stores compacted state for next prepareForLlm', () async {
      final compactor = _TrackingCompactor();
      final manager = _managerWith(
        budget: _tinyBudget(contextWindow: 100000),
        compactor: compactor,
      );
      final conv = _longConversation(6);
      await manager.forceCompact(conv);

      // Next prepareForLlm should use the forced compaction.
      final prepared = await manager.prepareForLlm(conv);
      // The compaction includes a summary + up to 2 recent messages.
      expect(
        prepared
            .any((m) => m.text?.contains('[Session context summary') == true),
        isTrue,
      );
    });
  });

  group('ContextManager.fromBudget factory', () {
    test('creates a ContextManager with wired estimator and slidingWindow', () {
      final budget = _tinyBudget();
      final manager = ContextManager.fromBudget(budget);
      expect(manager.budget, same(budget));
      expect(manager.estimator, isA<ContextEstimator>());
    });
  });

  group('ContextBudget.fromModelDef via ContextConfig', () {
    test('toolResultTrimAfter is respected by ToolResultTrimmer construction',
        () {
      const cfg = ContextConfig(toolResultTrimAfter: 2);
      final trimmer = ToolResultTrimmer(keepRecentN: cfg.toolResultTrimAfter);
      expect(trimmer.keepRecentN, 2);
    });
  });

  group('ContextManager overflow integration', () {
    test('AgentCore retries once on ContextOverflowException', () async {
      // LLM that throws overflow on the first call, then succeeds.
      final llm = _OverflowThenSuccessLlm();
      final est = ContextEstimator();
      final budget = ContextBudget.fromModelDef(
        const ModelDef(
          id: 'test',
          name: 'Test',
          contextWindow: 100000,
          maxOutputTokens: 1000,
        ),
      );
      final contextManager = ContextManager(
        budget: budget,
        estimator: est,
        slidingWindow: SlidingWindowTrimmer(estimator: est),
      );

      final core = AgentCore(llm: llm, tools: {});
      core.contextManager = contextManager;

      final events = <AgentEvent>[];
      await for (final e in core.run('test')) {
        events.add(e);
        if (e is AgentDone) break;
      }

      expect(llm.callCount, 2); // one overflow, one retry
      expect(events.any((e) => e is AgentDone), isTrue);
    });

    test('AgentCore does not retry a second time on repeated overflow',
        () async {
      final llm = _AlwaysOverflowLlm();
      final est = ContextEstimator();
      final budget = ContextBudget.fromModelDef(
        const ModelDef(
          id: 'test',
          name: 'Test',
          contextWindow: 100000,
          maxOutputTokens: 1000,
        ),
      );
      final contextManager = ContextManager(
        budget: budget,
        estimator: est,
        slidingWindow: SlidingWindowTrimmer(estimator: est),
      );

      final core = AgentCore(llm: llm, tools: {});
      core.contextManager = contextManager;

      final events = <AgentEvent>[];
      await for (final e in core.run('test')) {
        events.add(e);
        if (e is AgentError || e is AgentDone) break;
      }

      expect(llm.callCount, 2); // tried once + one retry, then gave up
      expect(events.any((e) => e is AgentError), isTrue);
    });
  });
}

/// LLM stub that throws a context overflow on first call, succeeds on second.
class _OverflowThenSuccessLlm implements LlmClient {
  int callCount = 0;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    callCount++;
    if (callCount == 1) {
      throw Exception('context length exceeded');
    }
    yield TextDelta('Done after retry.');
    yield UsageInfo(inputTokens: 5, outputTokens: 5);
  }
}

/// LLM stub that always throws a context overflow.
class _AlwaysOverflowLlm implements LlmClient {
  int callCount = 0;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    callCount++;
    throw Exception('context length exceeded');
  }
}
