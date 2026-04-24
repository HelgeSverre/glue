part of 'package:glue/src/app.dart';

void _endTurnSpanImpl(App app, {Map<String, dynamic>? extra}) {
  final span = app._turnSpan;
  final obs = app._obs;
  if (span != null && obs != null) {
    obs.endSpan(span, extra: extra);
    if (obs.activeSpan == span) obs.activeSpan = null;
    app._turnSpan = null;
  }
}

void _startAgentImpl(
  App app,
  String displayMessage, {
  String? expandedMessage,
}) {
  app._transcript.blocks.add(
      ConversationEntry.user(displayMessage, expandedText: expandedMessage));
  app._mode = AppMode.streaming;
  app._startSpinner();
  app._transcript.streamingText = '';
  app._transcript.subagentGroups.clear();
  app._render();

  app._turnSpan = app._obs?.startSpan(
    'agent.turn',
    kind: 'agent',
    attributes: {
      'openinference.span.kind': 'AGENT',
      'session.id': app._sessionManager.currentSessionId ?? '',
      'llm.model_name': app._modelId,
      'process.command': 'interactive',
      'user.message_length': displayMessage.length,
      'input.value': redactBody(expandedMessage ?? displayMessage),
    },
  );
  if (app._turnSpan != null) app._obs!.activeSpan = app._turnSpan;

  final stream = app.agent.run(expandedMessage ?? displayMessage);
  app._agentSub = stream.listen(
    app._handleAgentEvent,
    onError: (Object e) {
      app._endTurnSpan(extra: {'error': e.toString()});
      app._transcript.blocks.add(ConversationEntry.error(e.toString()));
      app._stopSpinner();
      app._mode = AppMode.idle;
      app._render();
    },
    onDone: () {
      app._endTurnSpan();
      if (app._transcript.streamingText.isNotEmpty) {
        app._transcript.blocks
            .add(ConversationEntry.assistant(app._transcript.streamingText));
        app._transcript.streamingText = '';
      }
      app._stopSpinner();
      app._mode = AppMode.idle;
      app._render();
    },
  );
}

void _handleAgentEventImpl(App app, AgentEvent event) {
  switch (event) {
    case AgentTextDelta(:final delta):
      app._transcript.streamingText += delta;
      app._render();

    case AgentToolCallPending(:final id, :final name):
      // Flush any accumulated assistant text so the ordering in _transcript.blocks
      // matches the actual conversation flow.
      if (app._transcript.streamingText.isNotEmpty) {
        app._sessionManager.logEvent(
            'assistant_message', {'text': app._transcript.streamingText});
        app._transcript.blocks
            .add(ConversationEntry.assistant(app._transcript.streamingText));
        app._transcript.streamingText = '';
      }
      app._transcript.toolUi[id] = ToolCallUiState(id: id, name: name);
      app._transcript.blocks.add(ConversationEntry.toolCallRef(id));

      // Early confirmation — ask before arguments finish streaming.
      if (app._permissionGate.needsEarlyConfirmation(name)) {
        app._transcript.toolUi[id]?.phase = ToolPhase.awaitingApproval;
        app._stopSpinner();
        app._mode = AppMode.confirming;
        app._activeModal = ConfirmModal(
          title: 'Allow $name?',
          bodyLines: ['(arguments still streaming…)'],
          choices: [
            const ModalChoice('Yes', 'y'),
            const ModalChoice('No', 'n'),
            const ModalChoice('Always', 'a'),
          ],
        );
        app._render();

        app._activeModal!.result.then((choiceIndex) {
          app._activeModal = null;
          final span = app._obs
              ?.startSpan('tool.approval', kind: 'tool.approval', attributes: {
            'openinference.span.kind': 'TOOL',
            'tool_call.id': id,
            'tool.name': name,
            'tool.approval.stage': 'early',
            'tool.approval.choice': choiceIndex,
          });
          if (span != null) {
            span.setStatus('ok');
            app._obs!.endSpan(span);
          }
          switch (choiceIndex) {
            case 0: // Yes
              app._earlyApprovedIds.add(id);
              app._transcript.toolUi[id]?.phase = ToolPhase.preparing;
              app._mode = AppMode.streaming;
              app._startSpinner();
              app._render();
            case 2: // Always
              app._persistTrustedTool(name);
              app._earlyApprovedIds.add(id);
              app._transcript.toolUi[id]?.phase = ToolPhase.preparing;
              app._mode = AppMode.streaming;
              app._startSpinner();
              app._render();
            default: // No
              app._cancelAgent();
              app.agent.completeToolCall(ToolResult.denied(id));
          }
        });
        return;
      }

      app._render();

    case AgentToolCall(:final call):
      final uiState = app._transcript.toolUi[call.id];
      if (uiState != null) {
        uiState.args = call.arguments;
      } else {
        // Ollama path — no prior pending event, create the ref now.
        if (app._transcript.streamingText.isNotEmpty) {
          app._transcript.blocks
              .add(ConversationEntry.assistant(app._transcript.streamingText));
          app._transcript.streamingText = '';
        }
        app._transcript.toolUi[call.id] = ToolCallUiState(
          id: call.id,
          name: call.name,
          phase: ToolPhase.preparing,
        )..args = call.arguments;
        app._transcript.blocks.add(ConversationEntry.toolCallRef(call.id));
      }

      app._ensureSessionStore();
      app._sessionManager.logEvent('tool_call', {
        'id': call.id,
        'name': call.name,
        'arguments': call.arguments,
      });

      // Early-approved at ToolCallPending time — re-check with full args.
      if (app._earlyApprovedIds.remove(call.id)) {
        final approval = app._permissionGate.resolve(call);
        if (approval == PermissionDecision.allow) {
          app._approveTool(call);
          return;
        }
        // Full arguments may still change the decision, so fall through.
      }

      // Permission-based approval.
      switch (app._permissionGate.resolve(call)) {
        case PermissionDecision.allow:
          app._traceToolApproval(call, 'allow');
          app._approveTool(call);
        case PermissionDecision.deny:
          app._traceToolApproval(call, 'deny');
          app._denyTool(call);
        case PermissionDecision.ask:
          app._showToolConfirmModal(call);
      }

    case AgentToolResult(:final result):
      app._transcript.toolUi[result.callId]?.phase = ToolPhase.done;
      app._sessionManager.logEvent('tool_result', {
        'call_id': result.callId,
        'content': result.content,
        if (result.summary != null) 'summary': result.summary,
        if (result.metadata.isNotEmpty) 'metadata': result.metadata,
      });
      app._transcript.blocks
          .add(ConversationEntry.toolResult(result.summary ?? result.content));
      app._mode = AppMode.streaming;
      app._startSpinner();
      app._render();

    case AgentDone():
      if (app._transcript.streamingText.isNotEmpty) {
        app._ensureSessionStore();
        app._sessionManager.logEvent(
            'assistant_message', {'text': app._transcript.streamingText});
        app._transcript.blocks
            .add(ConversationEntry.assistant(app._transcript.streamingText));
        app._transcript.streamingText = '';
      }
      _reevaluateTitleImpl(app);
      app._stopSpinner();
      app._mode = AppMode.idle;
      app._render();

    case AgentError(:final error):
      app._transcript.blocks.add(ConversationEntry.error(error.toString()));
      app._stopSpinner();
      app._mode = AppMode.idle;
      app._render();
  }
}

Future<void> _executeAndCompleteToolImpl(App app, ToolCall call) async {
  try {
    final result = await app.agent.executeTool(call);
    app.agent.completeToolCall(result);
  } catch (e) {
    app.agent.completeToolCall(ToolResult(
      callId: call.id,
      content: 'Tool error: $e',
      success: false,
    ));
  }
}

void _cancelAgentImpl(App app) {
  app._agentSub?.cancel();
  app._endTurnSpan(extra: {'cancelled': true});
  // Stop the spinner before flipping mode — otherwise the timer keeps
  // repainting the status bar even though nothing is happening.
  app._stopSpinner();
  app._mode = AppMode.idle;
  if (app._transcript.streamingText.isNotEmpty) {
    app._transcript.blocks.add(ConversationEntry.assistant(
        '${app._transcript.streamingText}\n[cancelled]'));
    app._transcript.streamingText = '';
  }
  for (final state in app._transcript.toolUi.values) {
    if (state.phase == ToolPhase.preparing ||
        state.phase == ToolPhase.awaitingApproval ||
        state.phase == ToolPhase.running) {
      // The tool never completed cleanly — but it wasn't an intrinsic tool
      // error either. Use the dedicated cancelled phase so the transcript
      // doesn't misleadingly read as a failure. awaitingApproval covers the
      // case where the user cancelled while the approval modal was open.
      state.phase = ToolPhase.cancelled;
    }
  }
  app.agent.ensureToolResultsComplete();
  app._render();
}

void _persistTrustedToolImpl(App app, String name) {
  app._configService.trustTool(name);
}

void _approveToolImpl(App app, ToolCall call) {
  app._transcript.toolUi[call.id]?.phase = ToolPhase.running;
  app._stopSpinner();
  app._mode = AppMode.toolRunning;
  app._render();
  unawaited(app._executeAndCompleteTool(call));
}

void _denyToolImpl(App app, ToolCall call) {
  app._transcript.toolUi[call.id]?.phase = ToolPhase.denied;
  app._mode = AppMode.streaming;
  app._startSpinner();
  app.agent.completeToolCall(ToolResult.denied(call.id));
  app._render();
}

void _showToolConfirmModalImpl(App app, ToolCall call) {
  app._transcript.toolUi[call.id]?.phase = ToolPhase.awaitingApproval;
  app._stopSpinner();
  app._mode = AppMode.confirming;
  final bodyLines =
      call.arguments.entries.map((e) => '${e.key}: ${e.value}').toList();
  if (bodyLines.isEmpty) bodyLines.add('(no arguments)');
  app._activeModal = ConfirmModal(
    title: 'Approve tool: ${call.name}',
    bodyLines: bodyLines,
    choices: [
      const ModalChoice('Yes', 'y'),
      const ModalChoice('No', 'n'),
      const ModalChoice('Always', 'a'),
    ],
  );
  app._render();

  app._activeModal!.result.then((choiceIndex) {
    app._activeModal = null;
    switch (choiceIndex) {
      case 0: // Yes
        app._traceToolApproval(call, 'allow');
        app._approveTool(call);
      case 2: // Always
        app._persistTrustedTool(call.name);
        app._traceToolApproval(call, 'always');
        app._approveTool(call);
      default: // No
        app._traceToolApproval(call, 'deny');
        app._denyTool(call);
    }
  });
}

void _traceToolApprovalImpl(App app, ToolCall call, String decision) {
  final span = app._obs?.startSpan(
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
  app._obs!.endSpan(span);
}
