import 'dart:async';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/src/agent/agent_core.dart';

/// Policy for automatic tool approval in headless execution.
///
/// {@category Agent}
enum ToolApprovalPolicy {
  /// Automatically approve and execute all tool calls.
  autoApproveAll,

  /// Deny all tool calls.
  denyAll,

  /// Approve only tools in an allowlist.
  allowlist,
}

/// Runs an [AgentCore] to completion without interactive approval.
///
/// Used for subagent execution where the parent agent has already
/// decided the task and tools should run without human intervention.
class AgentRunner {
  final AgentCore core;
  final ToolApprovalPolicy policy;
  final Set<String> _allowedTools;

  /// Optional callback invoked for every [AgentEvent] during execution.
  /// Used to forward subagent activity to the parent UI.
  final void Function(AgentEvent)? onEvent;

  /// Cumulative usage observed during this runner's lifetime. Surfaces
  /// the subagent's token cost back to the parent — without this, every
  /// subagent's `AgentCore.stats` would be discarded when the manager
  /// returns.
  final UsageStats stats = UsageStats();

  AgentRunner({
    required this.core,
    required this.policy,
    Set<String>? allowedTools,
    this.onEvent,
  }) : _allowedTools = allowedTools ?? const {};

  /// Runs a [userMessage] through the agent loop until completion.
  ///
  /// Returns the concatenated assistant text output.
  Future<String> runToCompletion(String userMessage) async {
    final buf = StringBuffer();

    await for (final event in core.run(userMessage)) {
      onEvent?.call(event);
      switch (event) {
        case AgentTextDelta(:final delta):
          buf.write(delta);
        case AgentThinkingDelta():
          // Headless mode discards reasoning traces — they're a UI
          // affordance, not part of the structured result.
          break;
        case AgentToolCallPending():
          break;
        case AgentToolCall(:final call):
          final result = await _handleToolCall(call);
          core.completeToolCall(result);
        case AgentToolResult():
          break;
        case AgentUsage(:final usage):
          stats.record(usage);
        case AgentDone():
          break;
        case AgentError(:final error):
          buf.write('\nError: $error');
      }
    }

    return buf.toString();
  }

  Future<ToolResult> _handleToolCall(ToolCall call) async {
    final approved = switch (policy) {
      ToolApprovalPolicy.autoApproveAll => true,
      ToolApprovalPolicy.denyAll => false,
      ToolApprovalPolicy.allowlist => _allowedTools.contains(call.name),
    };

    if (approved) {
      return core.executeTool(call);
    }
    return ToolResult.denied(call.id);
  }
}
