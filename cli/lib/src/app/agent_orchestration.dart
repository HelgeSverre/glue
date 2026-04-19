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
  app._blocks.add(
      _ConversationEntry.user(displayMessage, expandedText: expandedMessage));
  app._mode = AppMode.streaming;
  app._startSpinner();
  app._streamingText = '';
  app._subagentGroups.clear();
  app._render();

  app._turnSpan = app._obs?.startSpan(
    'agent.turn',
    kind: 'internal',
    attributes: {'user.message_length': displayMessage.length},
  );
  if (app._turnSpan != null) app._obs!.activeSpan = app._turnSpan;

  final stream = app.agent.run(expandedMessage ?? displayMessage);
  app._agentSub = stream.listen(
    app._handleAgentEvent,
    onError: (Object e) {
      app._endTurnSpan(extra: {'error': e.toString()});
      app._blocks.add(_ConversationEntry.error(e.toString()));
      app._stopSpinner();
      app._mode = AppMode.idle;
      app._render();
    },
    onDone: () {
      app._endTurnSpan();
      if (app._streamingText.isNotEmpty) {
        app._blocks.add(_ConversationEntry.assistant(app._streamingText));
        app._streamingText = '';
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
      app._streamingText += delta;
      app._render();

    case AgentToolCallPending(:final id, :final name):
      // Flush any accumulated assistant text so the ordering in _blocks
      // matches the actual conversation flow.
      if (app._streamingText.isNotEmpty) {
        app._sessionManager
            .logEvent('assistant_message', {'text': app._streamingText});
        app._blocks.add(_ConversationEntry.assistant(app._streamingText));
        app._streamingText = '';
      }
      app._toolUi[id] = _ToolCallUiState(id: id, name: name);
      app._blocks.add(_ConversationEntry.toolCallRef(id));

      // Early confirmation — ask before arguments finish streaming.
      if (app._permissionGate.needsEarlyConfirmation(name)) {
        app._toolUi[id]?.phase = _ToolPhase.awaitingApproval;
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
          switch (choiceIndex) {
            case 0: // Yes
              app._earlyApprovedIds.add(id);
              app._toolUi[id]?.phase = _ToolPhase.preparing;
              app._mode = AppMode.streaming;
              app._startSpinner();
              app._render();
            case 2: // Always
              app._persistTrustedTool(name);
              app._earlyApprovedIds.add(id);
              app._toolUi[id]?.phase = _ToolPhase.preparing;
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
      final uiState = app._toolUi[call.id];
      if (uiState != null) {
        uiState.args = call.arguments;
      } else {
        // Ollama path — no prior pending event, create the ref now.
        if (app._streamingText.isNotEmpty) {
          app._blocks.add(_ConversationEntry.assistant(app._streamingText));
          app._streamingText = '';
        }
        app._toolUi[call.id] = _ToolCallUiState(
          id: call.id,
          name: call.name,
          phase: _ToolPhase.preparing,
        )..args = call.arguments;
        app._blocks.add(_ConversationEntry.toolCallRef(call.id));
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
          app._approveTool(call);
        case PermissionDecision.deny:
          app._denyTool(call);
        case PermissionDecision.ask:
          app._showToolConfirmModal(call);
      }

    case AgentToolResult(:final result):
      app._toolUi[result.callId]?.phase = _ToolPhase.done;
      app._sessionManager.logEvent('tool_result', {
        'call_id': result.callId,
        'content': result.content,
      });
      app._blocks.add(_ConversationEntry.toolResult(result.content));
      app._mode = AppMode.streaming;
      app._startSpinner();
      app._render();

    case AgentDone():
      if (app._streamingText.isNotEmpty) {
        app._ensureSessionStore();
        app._sessionManager
            .logEvent('assistant_message', {'text': app._streamingText});
        app._blocks.add(_ConversationEntry.assistant(app._streamingText));
        app._streamingText = '';
      }
      app._stopSpinner();
      app._mode = AppMode.idle;
      app._render();

    case AgentError(:final error):
      app._blocks.add(_ConversationEntry.error(error.toString()));
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
  app._mode = AppMode.idle;
  if (app._streamingText.isNotEmpty) {
    app._blocks.add(
        _ConversationEntry.assistant('${app._streamingText}\n[cancelled]'));
    app._streamingText = '';
  }
  for (final state in app._toolUi.values) {
    if (state.phase == _ToolPhase.preparing ||
        state.phase == _ToolPhase.running) {
      state.phase = _ToolPhase.error;
    }
  }
  app.agent.ensureToolResultsComplete();
  app._render();
}

void _persistTrustedToolImpl(App app, String name) {
  app._autoApprovedTools.add(name);
  try {
    final store = ConfigStore(
      app._environment.configPath,
      legacyPath: app._environment.legacyConfigPath,
    );
    store.update((c) {
      final tools = (c['trusted_tools'] as List?)?.cast<String>() ?? [];
      if (!tools.contains(name)) {
        tools.add(name);
        c['trusted_tools'] = tools;
      }
    });
  } catch (_) {}
}

void _approveToolImpl(App app, ToolCall call) {
  app._toolUi[call.id]?.phase = _ToolPhase.running;
  app._stopSpinner();
  app._mode = AppMode.toolRunning;
  app._render();
  unawaited(app._executeAndCompleteTool(call));
}

void _denyToolImpl(App app, ToolCall call) {
  app._toolUi[call.id]?.phase = _ToolPhase.denied;
  app._mode = AppMode.streaming;
  app._startSpinner();
  app.agent.completeToolCall(ToolResult.denied(call.id));
  app._render();
}

void _showToolConfirmModalImpl(App app, ToolCall call) {
  app._toolUi[call.id]?.phase = _ToolPhase.awaitingApproval;
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
        app._approveTool(call);
      case 2: // Always
        app._persistTrustedTool(call.name);
        app._approveTool(call);
      default: // No
        app._denyTool(call);
    }
  });
}
