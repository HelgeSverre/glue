import 'dart:async';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/storage/session_store.dart';

enum SessionReplayKind { user, assistant, toolCall, toolResult }

class SessionReplayEntry {
  final SessionReplayKind kind;
  final String text;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;

  const SessionReplayEntry._({
    required this.kind,
    required this.text,
    this.toolName,
    this.toolArguments,
  });

  factory SessionReplayEntry.user(String text) =>
      SessionReplayEntry._(kind: SessionReplayKind.user, text: text);

  factory SessionReplayEntry.assistant(String text) =>
      SessionReplayEntry._(kind: SessionReplayKind.assistant, text: text);

  factory SessionReplayEntry.toolCall(
    String name,
    Map<String, dynamic> arguments,
  ) =>
      SessionReplayEntry._(
        kind: SessionReplayKind.toolCall,
        text: name,
        toolName: name,
        toolArguments: arguments,
      );

  factory SessionReplayEntry.toolResult(String text) =>
      SessionReplayEntry._(kind: SessionReplayKind.toolResult, text: text);
}

class SessionReplay {
  final List<SessionReplayEntry> entries;
  final int userCount;
  final int assistantCount;
  final String? firstUserMessage;

  const SessionReplay({
    required this.entries,
    required this.userCount,
    required this.assistantCount,
    this.firstUserMessage,
  });
}

class SessionResumeResult {
  final String message;
  final bool hasConversation;
  final SessionReplay replay;

  const SessionResumeResult({
    required this.message,
    required this.hasConversation,
    required this.replay,
  });
}

class SessionForkResult {
  final String message;
  final String draftText;
  final SessionReplay replay;

  const SessionForkResult({
    required this.message,
    required this.draftText,
    required this.replay,
  });
}

/// Handles session lifecycle operations independent of UI rendering.
class SessionManager {
  final Environment environment;
  SessionStore? _store;

  SessionManager({
    required this.environment,
    SessionStore? sessionStore,
  }) : _store = sessionStore;

  SessionStore? get currentStore => _store;
  String? get currentSessionId => _store?.meta.id;

  List<SessionMeta> listSessions() =>
      SessionStore.listSessions(environment.sessionsDir);

  SessionStore ensureSessionStore({
    required String cwd,
    required String modelRef,
  }) {
    final id = _newSessionId();
    return _store ??= SessionStore(
      sessionDir: environment.sessionDir(id),
      meta: SessionMeta(
        id: id,
        cwd: cwd,
        modelRef: modelRef,
        startTime: DateTime.now(),
      ),
    );
  }

  void switchToSessionStore(SessionMeta meta) {
    final oldStore = _store;
    if (oldStore?.meta.id == meta.id) return;
    if (oldStore != null) {
      unawaited(oldStore.close());
    }
    _store = SessionStore(
      sessionDir: environment.sessionDir(meta.id),
      meta: meta,
    );
  }

  void updateSessionModel({required String modelRef}) {
    final store = _store;
    if (store == null) return;
    store.meta.modelRef = modelRef;
    store.updateMeta();
  }

  void logEvent(String type, Map<String, dynamic> data) {
    _store?.logEvent(type, data);
  }

  Future<void> closeCurrent() async {
    final store = _store;
    if (store == null) return;
    await store.close();
  }

  Future<void> generateTitle({
    required String userMessage,
    required Future<String?> Function(String userMessage) generate,
  }) async {
    final store = _store;
    if (store == null) return;
    final title = await generate(userMessage);
    if (title != null) {
      store.setTitle(title);
      store.logEvent('title_generated', {'title': title});
    }
  }

  SessionResumeResult resumeSession({
    required SessionMeta session,
    required AgentCore agent,
  }) {
    final events =
        SessionStore.loadConversation(environment.sessionDir(session.id));
    switchToSessionStore(session);
    agent.clearConversation();

    if (events.isEmpty) {
      return const SessionResumeResult(
        message: 'Session has no conversation data.',
        hasConversation: false,
        replay: SessionReplay(entries: [], userCount: 0, assistantCount: 0),
      );
    }

    final replay = _replayEventsIntoAgent(events, agent);
    return SessionResumeResult(
      message:
          'Restored ${replay.userCount} user + ${replay.assistantCount} assistant messages.',
      hasConversation: true,
      replay: replay,
    );
  }

  SessionForkResult? forkSession({
    required int userMessageIndex,
    required String messageText,
    required AgentCore agent,
  }) {
    final oldStore = _store;
    if (oldStore == null) return null;

    final oldSessionId = oldStore.meta.id;
    final allEvents = SessionStore.loadConversation(oldStore.sessionDir);
    var userCount = 0;
    final truncatedEvents = <Map<String, dynamic>>[];
    for (final event in allEvents) {
      truncatedEvents.add(event);
      if (event['type'] == 'user_message') {
        if (userCount == userMessageIndex) break;
        userCount++;
      }
    }

    unawaited(oldStore.close());

    final newId = _newSessionId();
    final newStore = SessionStore(
      sessionDir: environment.sessionDir(newId),
      meta: SessionMeta(
        id: newId,
        cwd: oldStore.meta.cwd,
        modelRef: oldStore.meta.modelRef,
        startTime: DateTime.now(),
        forkedFrom: oldSessionId,
      ),
    );

    for (final event in truncatedEvents) {
      final type = event['type'] as String? ?? '';
      final data = Map<String, dynamic>.from(event)
        ..remove('type')
        ..remove('timestamp');
      newStore.logEvent(type, data);
    }

    _store = newStore;
    agent.clearConversation();
    final replay = _replayEventsIntoAgent(truncatedEvents, agent);
    final shortId =
        oldSessionId.length > 8 ? oldSessionId.substring(0, 8) : oldSessionId;
    return SessionForkResult(
      message: 'Forked from session $shortId…',
      draftText: messageText,
      replay: replay,
    );
  }

  static SessionReplay _replayEventsIntoAgent(
    List<Map<String, dynamic>> events,
    AgentCore agent,
  ) {
    final entries = <SessionReplayEntry>[];
    var userCount = 0;
    var assistantCount = 0;
    String? firstUserMessage;

    String? pendingAssistantText;
    var pendingToolCalls = <ToolCall>[];
    var pendingToolResults = <Message>[];

    void flushPending() {
      if (pendingAssistantText != null) {
        agent.addMessage(Message.assistant(
          text: pendingAssistantText,
          toolCalls: pendingToolCalls,
        ));
        entries.add(SessionReplayEntry.assistant(pendingAssistantText!));
        assistantCount++;
        for (final tr in pendingToolResults) {
          agent.addMessage(tr);
        }
      }
      pendingAssistantText = null;
      pendingToolCalls = [];
      pendingToolResults = [];
    }

    for (final event in events) {
      final type = event['type'] as String?;
      final text = event['text'] as String? ?? '';
      switch (type) {
        case 'user_message':
          flushPending();
          if (text.isEmpty) continue;
          firstUserMessage ??= text;
          agent.addMessage(Message.user(text));
          entries.add(SessionReplayEntry.user(text));
          userCount++;

        case 'assistant_message':
          flushPending();
          if (text.isEmpty) continue;
          pendingAssistantText = text;

        case 'tool_call':
          final name = event['name'] as String? ?? '';
          final id =
              event['id'] as String? ?? 'replay_${pendingToolCalls.length}';
          final args = event['arguments'] as Map<String, dynamic>? ?? {};
          if (name.isNotEmpty) {
            pendingToolCalls.add(ToolCall(id: id, name: name, arguments: args));
            entries.add(SessionReplayEntry.toolCall(name, args));
          }

        case 'tool_result':
          final callId = event['call_id'] as String?;
          final content = event['content'] as String? ?? '';
          if (callId != null) {
            pendingToolResults.add(
              Message.toolResult(callId: callId, content: content),
            );
            entries.add(SessionReplayEntry.toolResult(content));
          }

        default:
          break;
      }
    }
    flushPending();

    return SessionReplay(
      entries: entries,
      userCount: userCount,
      assistantCount: assistantCount,
      firstUserMessage: firstUserMessage,
    );
  }

  String _newSessionId() {
    final now = DateTime.now();
    return '${now.millisecondsSinceEpoch}-${now.microsecond.toRadixString(36)}';
  }
}
