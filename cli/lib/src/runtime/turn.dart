import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/app.dart' show AppMode;
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/redaction.dart';
import 'package:glue/src/orchestrator/permission_gate.dart';
import 'package:glue/src/runtime/renderer.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/runtime/services/session.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/ui/components/modal.dart';

/// One user message → assistant response cycle, possibly including tool
/// calls and approvals.
///
/// A `Turn` is ephemeral: it owns the observability span, the agent event
/// stream subscription, and the set of tool-call IDs early-approved inside
/// it. When the turn ends (the agent emits `AgentDone`, an error occurs,
/// or the user cancels), those are disposed with the instance.
///
/// The same class handles both interactive and print (`--print`) modes —
/// they differ only in how assistant output is surfaced (incremental
/// transcript updates vs. stdout flush + optional JSON dump). Both paths
/// run inside [Observability.runInContext] so concurrent turns (e.g. a
/// subagent spawned by a tool) can carry their own span context without
/// corrupting the parent turn's.
class Turn {
  Turn({
    required this.agent,
    required this.transcript,
    required this.renderer,
    required this.session,
    required this.config,
    required this.obs,
    required this.permissionGateFactory,
    required this.modelIdProvider,
    required this.setMode,
    required this.setActiveModal,
    required this.getActiveModal,
    required this.render,
    required this.onTurnComplete,
  });

  final Agent agent;
  final Transcript transcript;
  final Renderer renderer;
  final Session session;
  final Config config;
  final Observability? obs;
  final PermissionGate Function() permissionGateFactory;
  final String Function() modelIdProvider;
  final void Function(AppMode) setMode;
  final void Function(ConfirmModal?) setActiveModal;
  final ConfirmModal? Function() getActiveModal;
  final void Function() render;
  final void Function() onTurnComplete;

  ObservabilitySpan? _span;
  StreamSubscription<AgentEvent>? _sub;
  final Set<String> _earlyApprovedIds = {};

  // ---------------------------------------------------------------------------
  // Public entry points
  // ---------------------------------------------------------------------------

  /// Start an interactive turn. Kicks off the agent stream subscription and
  /// returns immediately — the turn runs in the background until
  /// [AgentDone] / [AgentError] / [cancel].
  void run(String displayMessage, {String? expandedMessage}) {
    transcript.blocks.add(
      ConversationEntry.user(displayMessage, expandedText: expandedMessage),
    );
    setMode(AppMode.streaming);
    renderer.startSpinner(render);
    transcript.streamingText = '';
    transcript.subagentGroups.clear();
    render();

    final effective = expandedMessage ?? displayMessage;

    void start() {
      _span = obs?.startSpan(
        'agent.turn',
        kind: 'agent',
        attributes: {
          'openinference.span.kind': 'AGENT',
          'session.id': session.currentId ?? '',
          'llm.model_name': modelIdProvider(),
          'process.command': 'interactive',
          'user.message_length': displayMessage.length,
          'input.value': redactBody(effective),
        },
      );
      if (_span != null) obs!.activeSpan = _span;

      _sub = agent.run(effective).listen(
        _handleAgentEvent,
        onError: (Object e) {
          _endSpan(extra: {'error': e.toString()});
          transcript.blocks.add(ConversationEntry.error(e.toString()));
          renderer.stopSpinner();
          setMode(AppMode.idle);
          render();
        },
        onDone: () {
          _endSpan();
          if (transcript.streamingText.isNotEmpty) {
            transcript.blocks
                .add(ConversationEntry.assistant(transcript.streamingText));
            transcript.streamingText = '';
          }
          renderer.stopSpinner();
          setMode(AppMode.idle);
          render();
        },
      );
    }

    // Wrap in an observability context so the span holder is scoped to
    // this turn even across async/subagent hops. The subscription
    // callbacks captured above will fire in this zone.
    if (obs != null) {
      obs!.runInContext(start);
    } else {
      start();
    }
  }

  /// Run a turn in print mode. Consumes the agent stream to completion,
  /// writes assistant text to stdout (or emits a JSON dump at the end),
  /// and resolves when the turn finishes. App-level teardown (tool
  /// dispose, obs flush/close, session close) stays on the caller.
  Future<void> runPrint({
    required String expandedPrompt,
    required bool jsonMode,
  }) async {
    session.logEvent('user_message', {'text': expandedPrompt});

    Future<void> body() async {
      final assistantText = StringBuffer();
      final conversationLog = <Map<String, dynamic>>[];
      _span = obs?.startSpan(
        'agent.turn',
        kind: 'agent',
        attributes: {
          'openinference.span.kind': 'AGENT',
          'session.id': session.currentId ?? '',
          'llm.model_name': modelIdProvider(),
          'process.command': 'print',
          'user.message_length': expandedPrompt.length,
          'input.value': redactBody(expandedPrompt),
        },
      );
      if (_span != null) obs!.activeSpan = _span;

      try {
        await for (final event in agent.run(expandedPrompt)) {
          switch (event) {
            case AgentTextDelta(:final delta):
              assistantText.write(delta);
              if (!jsonMode) stdout.write(delta);

            case AgentToolCall(:final call):
              conversationLog.add({
                'type': 'tool_call',
                'name': call.name,
                'arguments': call.arguments,
              });
              try {
                final result = await agent.executeTool(call);
                agent.completeToolCall(result);
              } catch (e) {
                agent.completeToolCall(ToolResult(
                  callId: call.id,
                  content: 'Tool error: $e',
                  success: false,
                ));
              }

            case AgentDone():
              break;

            case AgentError(:final error):
              if (_span != null && _span!.endTime == null) {
                obs!.endSpan(_span!, extra: {
                  'error': true,
                  'error.type': error.runtimeType.toString(),
                  'error.message': error.toString(),
                });
                _span = null;
              }
              stderr.writeln(error);
              return;

            default:
              break;
          }
        }
      } catch (e) {
        if (_span != null) {
          obs!.endSpan(_span!, extra: {
            'error': true,
            'error.type': e.runtimeType.toString(),
            'error.message': e.toString(),
          });
          _span = null;
        }
        stderr.writeln('Error: $e');
        return;
      } finally {
        if (_span != null && _span!.endTime == null) {
          obs!.endSpan(_span!, extra: {
            'output.value': redactBody(assistantText.toString()),
            'output.length': assistantText.length,
          });
        }
        _span = null;
      }

      final text = assistantText.toString();
      if (!jsonMode && !text.endsWith('\n')) stdout.writeln();

      session.logEvent('assistant_message', {'text': text});

      if (jsonMode) {
        final sessionId = session.currentId;
        conversationLog.insert(
            0, {'type': 'user_message', 'text': expandedPrompt});
        conversationLog.add({'type': 'assistant_message', 'text': text});
        final output = {
          'session_id': sessionId,
          'model': modelIdProvider(),
          'conversation': conversationLog,
        };
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
      }
    }

    if (obs != null) {
      return obs!.runInContext(body);
    }
    return body();
  }

  /// Cancel the in-flight turn. The span is ended with `cancelled: true`,
  /// the subscription is torn down, and any dangling tool-call UI states
  /// flip to [ToolPhase.cancelled] so the transcript doesn't read as a
  /// failure.
  void cancel() {
    _sub?.cancel();
    _endSpan(extra: {'cancelled': true});
    renderer.stopSpinner();
    setMode(AppMode.idle);
    if (transcript.streamingText.isNotEmpty) {
      transcript.blocks.add(ConversationEntry.assistant(
          '${transcript.streamingText}\n[cancelled]'));
      transcript.streamingText = '';
    }
    for (final state in transcript.toolUi.values) {
      if (state.phase == ToolPhase.preparing ||
          state.phase == ToolPhase.awaitingApproval ||
          state.phase == ToolPhase.running) {
        state.phase = ToolPhase.cancelled;
      }
    }
    agent.ensureToolResultsComplete();
    render();
  }

  // ---------------------------------------------------------------------------
  // Agent event handling (interactive path)
  // ---------------------------------------------------------------------------

  void _handleAgentEvent(AgentEvent event) {
    switch (event) {
      case AgentTextDelta(:final delta):
        transcript.streamingText += delta;
        render();

      case AgentToolCallPending(:final id, :final name):
        if (transcript.streamingText.isNotEmpty) {
          session.logEvent(
              'assistant_message', {'text': transcript.streamingText});
          transcript.blocks
              .add(ConversationEntry.assistant(transcript.streamingText));
          transcript.streamingText = '';
        }
        transcript.toolUi[id] = ToolCallUiState(id: id, name: name);
        transcript.blocks.add(ConversationEntry.toolCallRef(id));

        if (permissionGateFactory().needsEarlyConfirmation(name)) {
          _promptEarlyConfirmation(id: id, name: name);
          return;
        }
        render();

      case AgentToolCall(:final call):
        final uiState = transcript.toolUi[call.id];
        if (uiState != null) {
          uiState.args = call.arguments;
        } else {
          // Ollama path: no prior pending event, create the ref now.
          if (transcript.streamingText.isNotEmpty) {
            transcript.blocks
                .add(ConversationEntry.assistant(transcript.streamingText));
            transcript.streamingText = '';
          }
          transcript.toolUi[call.id] = ToolCallUiState(
            id: call.id,
            name: call.name,
            phase: ToolPhase.preparing,
          )..args = call.arguments;
          transcript.blocks.add(ConversationEntry.toolCallRef(call.id));
        }

        session.ensureStore();
        session.logEvent('tool_call', {
          'id': call.id,
          'name': call.name,
          'arguments': call.arguments,
        });

        // Early-approved at pending time — re-check with full args.
        if (_earlyApprovedIds.remove(call.id)) {
          final approval = permissionGateFactory().resolve(call);
          if (approval == PermissionDecision.allow) {
            _approveTool(call);
            return;
          }
          // Full arguments may still change the decision; fall through.
        }

        switch (permissionGateFactory().resolve(call)) {
          case PermissionDecision.allow:
            _traceToolApproval(call, 'allow');
            _approveTool(call);
          case PermissionDecision.deny:
            _traceToolApproval(call, 'deny');
            _denyTool(call);
          case PermissionDecision.ask:
            _showToolConfirmModal(call);
        }

      case AgentToolResult(:final result):
        transcript.toolUi[result.callId]?.phase = ToolPhase.done;
        session.logEvent('tool_result', {
          'call_id': result.callId,
          'content': result.content,
          if (result.summary != null) 'summary': result.summary,
          if (result.metadata.isNotEmpty) 'metadata': result.metadata,
        });
        transcript.blocks.add(
            ConversationEntry.toolResult(result.summary ?? result.content));
        setMode(AppMode.streaming);
        renderer.startSpinner(render);
        render();

      case AgentDone():
        if (transcript.streamingText.isNotEmpty) {
          session.ensureStore();
          session.logEvent(
              'assistant_message', {'text': transcript.streamingText});
          transcript.blocks
              .add(ConversationEntry.assistant(transcript.streamingText));
          transcript.streamingText = '';
        }
        onTurnComplete();
        renderer.stopSpinner();
        setMode(AppMode.idle);
        render();

      case AgentError(:final error):
        transcript.blocks.add(ConversationEntry.error(error.toString()));
        renderer.stopSpinner();
        setMode(AppMode.idle);
        render();
    }
  }

  // ---------------------------------------------------------------------------
  // Tool approval flow
  // ---------------------------------------------------------------------------

  void _promptEarlyConfirmation({required String id, required String name}) {
    transcript.toolUi[id]?.phase = ToolPhase.awaitingApproval;
    renderer.stopSpinner();
    setMode(AppMode.confirming);
    final modal = ConfirmModal(
      title: 'Allow $name?',
      bodyLines: const ['(arguments still streaming…)'],
      choices: const [
        ModalChoice('Yes', 'y'),
        ModalChoice('No', 'n'),
        ModalChoice('Always', 'a'),
      ],
    );
    setActiveModal(modal);
    render();

    modal.result.then((choiceIndex) {
      if (identical(getActiveModal(), modal)) setActiveModal(null);
      final span =
          obs?.startSpan('tool.approval', kind: 'tool.approval', attributes: {
        'openinference.span.kind': 'TOOL',
        'tool_call.id': id,
        'tool.name': name,
        'tool.approval.stage': 'early',
        'tool.approval.choice': choiceIndex,
      });
      if (span != null) {
        span.setStatus('ok');
        obs!.endSpan(span);
      }
      switch (choiceIndex) {
        case 0: // Yes
          _earlyApprovedIds.add(id);
          transcript.toolUi[id]?.phase = ToolPhase.preparing;
          setMode(AppMode.streaming);
          renderer.startSpinner(render);
          render();
        case 2: // Always
          config.trustTool(name);
          _earlyApprovedIds.add(id);
          transcript.toolUi[id]?.phase = ToolPhase.preparing;
          setMode(AppMode.streaming);
          renderer.startSpinner(render);
          render();
        default: // No
          cancel();
          agent.completeToolCall(ToolResult.denied(id));
      }
    });
  }

  void _showToolConfirmModal(ToolCall call) {
    transcript.toolUi[call.id]?.phase = ToolPhase.awaitingApproval;
    renderer.stopSpinner();
    setMode(AppMode.confirming);
    final bodyLines =
        call.arguments.entries.map((e) => '${e.key}: ${e.value}').toList();
    if (bodyLines.isEmpty) bodyLines.add('(no arguments)');
    final modal = ConfirmModal(
      title: 'Approve tool: ${call.name}',
      bodyLines: bodyLines,
      choices: const [
        ModalChoice('Yes', 'y'),
        ModalChoice('No', 'n'),
        ModalChoice('Always', 'a'),
      ],
    );
    setActiveModal(modal);
    render();

    modal.result.then((choiceIndex) {
      if (identical(getActiveModal(), modal)) setActiveModal(null);
      switch (choiceIndex) {
        case 0: // Yes
          _traceToolApproval(call, 'allow');
          _approveTool(call);
        case 2: // Always
          config.trustTool(call.name);
          _traceToolApproval(call, 'always');
          _approveTool(call);
        default: // No
          _traceToolApproval(call, 'deny');
          _denyTool(call);
      }
    });
  }

  void _approveTool(ToolCall call) {
    transcript.toolUi[call.id]?.phase = ToolPhase.running;
    renderer.stopSpinner();
    setMode(AppMode.toolRunning);
    render();
    unawaited(_executeAndCompleteTool(call));
  }

  void _denyTool(ToolCall call) {
    transcript.toolUi[call.id]?.phase = ToolPhase.denied;
    setMode(AppMode.streaming);
    renderer.startSpinner(render);
    agent.completeToolCall(ToolResult.denied(call.id));
    render();
  }

  Future<void> _executeAndCompleteTool(ToolCall call) async {
    try {
      final result = await agent.executeTool(call);
      agent.completeToolCall(result);
    } catch (e) {
      agent.completeToolCall(ToolResult(
        callId: call.id,
        content: 'Tool error: $e',
        success: false,
      ));
    }
  }

  void _traceToolApproval(ToolCall call, String decision) {
    final span = obs?.startSpan(
      'tool.approval',
      kind: 'tool.approval',
      attributes: {
        'openinference.span.kind': 'TOOL',
        'tool_call.id': call.id,
        'tool.name': call.name,
        'tool.approval.decision': decision,
      },
    );
    if (span == null) return;
    span.setStatus('ok');
    obs!.endSpan(span);
  }

  // ---------------------------------------------------------------------------
  // Span lifecycle
  // ---------------------------------------------------------------------------

  void _endSpan({Map<String, dynamic>? extra}) {
    final span = _span;
    if (span != null && obs != null) {
      obs!.endSpan(span, extra: extra);
      if (obs!.activeSpan == span) obs!.activeSpan = null;
      _span = null;
    }
  }
}
