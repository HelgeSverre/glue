import 'dart:async';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/redaction.dart';
import 'package:glue/src/session/session_event_normalizer.dart';
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
  final String? latestUserMessage;
  final String? firstAssistantMessage;
  final String? latestAssistantMessage;
  final List<String> toolNames;

  const SessionReplay({
    required this.entries,
    required this.userCount,
    required this.assistantCount,
    this.firstUserMessage,
    this.latestUserMessage,
    this.firstAssistantMessage,
    this.latestAssistantMessage,
    this.toolNames = const [],
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
class TitleContext {
  final String? firstUserMessage;
  final String? latestUserMessage;
  final String? firstAssistantMessage;
  final String? latestAssistantMessage;
  final List<String> toolNames;
  final String? cwdBasename;

  const TitleContext({
    this.firstUserMessage,
    this.latestUserMessage,
    this.firstAssistantMessage,
    this.latestAssistantMessage,
    this.toolNames = const [],
    this.cwdBasename,
  });
}

class SessionManager {
  final Environment environment;
  final Observability? _obs;
  SessionStore? _store;

  SessionManager({
    required this.environment,
    SessionStore? sessionStore,
    Observability? observability,
  })  : _obs = observability,
        _store = sessionStore;

  SessionStore? get currentStore => _store;
  String? get currentSessionId => _store?.meta.id;

  List<SessionMeta> listSessions() =>
      SessionStore.listSessions(environment.sessionsDir);

  SessionStore ensureSessionStore({
    required String cwd,
    required String modelRef,
  }) {
    final existing = _store;
    if (existing != null) return existing;

    final span = _startSpan('session.create', attributes: {
      'session.cwd': cwd,
      'llm.model_name': modelRef,
    });
    try {
      final id = _newSessionId();
      final store = SessionStore(
        sessionDir: environment.sessionDir(id),
        meta: SessionMeta(
          id: id,
          cwd: cwd,
          modelRef: modelRef,
          startTime: DateTime.now(),
        ),
      );
      _store = store;
      _endSpan(span, extra: {'session.id': store.meta.id});
      return store;
    } catch (e, st) {
      _endSpan(span, extra: {
        'error': true,
        'error.type': e.runtimeType.toString(),
        'error.message': e.toString(),
        'error.stack': st.toString(),
      });
      rethrow;
    }
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

    // Track message counts
    if (type == 'user_message' || type == 'assistant_message') {
      final store = _store;
      if (store != null) {
        store.meta.messageCount = (store.meta.messageCount ?? 0) + 1;
        store.updateMeta();
      }
    }
  }

  Future<void> closeCurrent() async {
    final store = _store;
    if (store == null) return;
    final span = _startSpan('session.close', attributes: {
      'session.id': store.meta.id,
    });
    try {
      await store.close();
      _endSpan(span, extra: {'session.closed': true});
    } catch (e, st) {
      _endSpan(span, extra: {
        'error': true,
        'error.type': e.runtimeType.toString(),
        'error.message': e.toString(),
        'error.stack': st.toString(),
      });
      rethrow;
    }
  }

  Future<void> generateTitle({
    required String userMessage,
    required Future<String?> Function(String userMessage) generate,
  }) async {
    final store = _store;
    if (store == null) return;
    final meta = store.meta;
    if (meta.titleSource == SessionTitleSource.user) return;
    final span = _startSpan('session.title.generate', attributes: {
      'session.id': meta.id,
      'title.input_length': userMessage.length,
      'input.value': redactBody(userMessage, maxBytes: 8192),
    });
    try {
      final title = await generate(userMessage);
      if (title != null) {
        final now = DateTime.now().toUtc();
        store.setTitle(
          title,
          source: SessionTitleSource.auto,
          state: SessionTitleState.provisional,
          generationCount: 1,
          generatedAt: now,
          lastEvaluatedAt: now,
          renamedAt: null,
        );
        store.logEvent('title_generated', {'title': title});
      }
      _endSpan(span, extra: {
        'title.generated': title != null,
        if (title != null) 'output.value': title,
        if (title != null) 'title.output_length': title.length,
      });
    } catch (e, st) {
      _endSpan(span, extra: {
        'error': true,
        'error.type': e.runtimeType.toString(),
        'error.message': e.toString(),
        'error.stack': st.toString(),
      });
      rethrow;
    }
  }

  Future<void> renameTitle(String title) async {
    final store = _store;
    if (store == null) return;
    final span = _startSpan('session.title.rename', attributes: {
      'session.id': store.meta.id,
      'title.output_length': title.length,
      'output.value': title,
    });
    try {
      final now = DateTime.now().toUtc();
      store.setTitle(
        title,
        source: SessionTitleSource.user,
        state: SessionTitleState.stable,
        generatedAt: store.meta.titleGeneratedAt ?? now,
        lastEvaluatedAt: now,
        renamedAt: now,
      );
      _endSpan(span, extra: {'title.renamed': true});
    } catch (e, st) {
      _endSpan(span, extra: {
        'error': true,
        'error.type': e.runtimeType.toString(),
        'error.message': e.toString(),
        'error.stack': st.toString(),
      });
      rethrow;
    }
  }

  Future<void> reevaluateTitle({
    required TitleContext context,
    required Future<String?> Function(TitleContext context) generate,
  }) async {
    final store = _store;
    if (store == null) return;
    final meta = store.meta;
    if (meta.titleSource != SessionTitleSource.auto ||
        meta.titleState != SessionTitleState.provisional ||
        meta.titleGenerationCount >= 2) {
      return;
    }

    final span = _startSpan('session.title.reevaluate', attributes: {
      'session.id': meta.id,
      'title.tool_count': context.toolNames.length,
      if (context.firstUserMessage != null)
        'title.first_user_length': context.firstUserMessage!.length,
      if (context.latestAssistantMessage != null)
        'title.latest_assistant_length': context.latestAssistantMessage!.length,
    });
    try {
      final now = DateTime.now().toUtc();
      final currentTitle = meta.title;
      final proposed = await generate(context);
      final shouldReplace = _shouldReplaceTitle(
        currentTitle: currentTitle,
        proposedTitle: proposed,
      );

      if (currentTitle != null) {
        store.setTitle(
          shouldReplace ? proposed! : currentTitle,
          source: SessionTitleSource.auto,
          state: SessionTitleState.stable,
          generationCount: meta.titleGenerationCount + 1,
          generatedAt: meta.titleGeneratedAt ?? now,
          lastEvaluatedAt: now,
        );
      } else if (proposed != null) {
        store.setTitle(
          proposed,
          source: SessionTitleSource.auto,
          state: SessionTitleState.stable,
          generationCount: meta.titleGenerationCount + 1,
          generatedAt: meta.titleGeneratedAt ?? now,
          lastEvaluatedAt: now,
        );
      } else {
        meta.titleState = SessionTitleState.stable;
        meta.titleGenerationCount = meta.titleGenerationCount + 1;
        meta.titleLastEvaluatedAt = now;
        store.updateMeta();
      }

      if (shouldReplace && proposed != null) {
        store.logEvent('title_reevaluated', {'title': proposed});
      }
      _endSpan(span, extra: {
        'title.generated': proposed != null,
        'title.replaced': shouldReplace,
        if (proposed != null) 'output.value': proposed,
        if (proposed != null) 'title.output_length': proposed.length,
      });
    } catch (e, st) {
      _endSpan(span, extra: {
        'error': true,
        'error.type': e.runtimeType.toString(),
        'error.message': e.toString(),
        'error.stack': st.toString(),
      });
      rethrow;
    }
  }

  SessionResumeResult resumeSession({
    required SessionMeta session,
    required Agent agent,
  }) {
    final span = _startSpan('session.resume', attributes: {
      'session.id': session.id,
    });
    try {
      final events =
          SessionStore.loadConversation(environment.sessionDir(session.id));
      switchToSessionStore(session);
      agent.clearConversation();

      if (events.isEmpty) {
        const result = SessionResumeResult(
          message: 'Session has no conversation data.',
          hasConversation: false,
          replay: SessionReplay(entries: [], userCount: 0, assistantCount: 0),
        );
        _endSpan(span, extra: {
          'session.event_count': 0,
          'session.has_conversation': false,
        });
        return result;
      }

      final replay = _replayEventsIntoAgent(events, agent);

      final currentStore = _store;
      if (currentStore != null) {
        currentStore.meta.messageCount =
            replay.userCount + replay.assistantCount;
        currentStore.updateMeta();
      }

      final result = SessionResumeResult(
        message:
            'Restored ${replay.userCount} user + ${replay.assistantCount} assistant messages.',
        hasConversation: true,
        replay: replay,
      );
      _endSpan(span, extra: {
        'session.event_count': events.length,
        'session.has_conversation': true,
        'session.replay.entry_count': replay.entries.length,
        'session.user_count': replay.userCount,
        'session.assistant_count': replay.assistantCount,
      });
      return result;
    } catch (e, st) {
      _endSpan(span, extra: {
        'error': true,
        'error.type': e.runtimeType.toString(),
        'error.message': e.toString(),
        'error.stack': st.toString(),
      });
      rethrow;
    }
  }

  SessionForkResult? forkSession({
    required int userMessageIndex,
    required String messageText,
    required Agent agent,
  }) {
    final oldStore = _store;
    if (oldStore == null) return null;
    final span = _startSpan('session.fork', attributes: {
      'session.id': oldStore.meta.id,
      'session.fork.user_message_index': userMessageIndex,
      'session.fork.draft_length': messageText.length,
      'input.value': redactBody(messageText, maxBytes: 8192),
    });

    try {
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
      final result = SessionForkResult(
        message: 'Forked from session $shortId…',
        draftText: messageText,
        replay: replay,
      );
      _endSpan(span, extra: {
        'session.id': newStore.meta.id,
        'session.fork.source_session_id': oldSessionId,
        'session.fork.event_count': truncatedEvents.length,
        'session.replay.entry_count': replay.entries.length,
      });
      return result;
    } catch (e, st) {
      _endSpan(span, extra: {
        'error': true,
        'error.type': e.runtimeType.toString(),
        'error.message': e.toString(),
        'error.stack': st.toString(),
      });
      rethrow;
    }
  }

  static SessionReplay _replayEventsIntoAgent(
    List<Map<String, dynamic>> events,
    Agent agent,
  ) {
    final entries = <SessionReplayEntry>[];
    var userCount = 0;
    var assistantCount = 0;
    String? firstUserMessage;
    String? latestUserMessage;
    String? firstAssistantMessage;
    String? latestAssistantMessage;
    final toolNames = <String>[];

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

    for (final event in normalizeSessionEvents(events)) {
      switch (event.kind) {
        case NormalizedSessionEventKind.user:
          flushPending();
          firstUserMessage ??= event.visibleText;
          latestUserMessage = event.visibleText;
          agent.addMessage(Message.user(event.text));
          entries.add(SessionReplayEntry.user(event.visibleText));
          userCount++;

        case NormalizedSessionEventKind.assistant:
          flushPending();
          firstAssistantMessage ??= event.visibleText;
          latestAssistantMessage = event.visibleText;
          pendingAssistantText = event.text;

        case NormalizedSessionEventKind.toolCall:
          final name = event.toolName!;
          final id = event.toolCallId ?? 'replay_${pendingToolCalls.length}';
          final args = event.toolArguments ?? const <String, dynamic>{};
          pendingToolCalls.add(ToolCall(id: id, name: name, arguments: args));
          toolNames.add(name);
          entries.add(SessionReplayEntry.toolCall(name, args));

        case NormalizedSessionEventKind.toolResult:
          final callId = event.toolCallId;
          if (callId != null) {
            pendingToolResults.add(
              Message.toolResult(callId: callId, content: event.text),
            );
          }
          entries.add(SessionReplayEntry.toolResult(event.visibleText));
      }
    }
    flushPending();

    return SessionReplay(
      entries: entries,
      userCount: userCount,
      assistantCount: assistantCount,
      firstUserMessage: firstUserMessage,
      latestUserMessage: latestUserMessage,
      firstAssistantMessage: firstAssistantMessage,
      latestAssistantMessage: latestAssistantMessage,
      toolNames: toolNames,
    );
  }

  bool _shouldReplaceTitle({
    required String? currentTitle,
    required String? proposedTitle,
  }) {
    final current = _normalizeTitle(currentTitle);
    final proposed = _normalizeTitle(proposedTitle);
    if (current == null || proposed == null) return false;
    if (current == proposed) return false;
    if (proposed.length < current.length && _looksGeneric(current)) {
      return false;
    }
    if (_looksGeneric(current) && !_looksGeneric(proposed)) {
      return true;
    }
    return proposed.length > current.length;
  }

  String? _normalizeTitle(String? title) {
    final sanitized = title?.trim().toLowerCase();
    if (sanitized == null || sanitized.isEmpty) return null;
    return sanitized
        .replaceAll(RegExp(r'^[^a-z0-9]+|[^a-z0-9]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _looksGeneric(String title) {
    const generic = {
      'investigate issue',
      'help debug this',
      'fix problem',
      'check code',
      'session question',
    };
    return generic.contains(_normalizeTitle(title));
  }

  String _newSessionId() {
    final now = DateTime.now();
    return '${now.millisecondsSinceEpoch}-${now.microsecond.toRadixString(36)}';
  }

  ObservabilitySpan? _startSpan(
    String name, {
    Map<String, dynamic>? attributes,
  }) {
    final obs = _obs;
    if (obs == null) return null;
    return obs.startSpan(name, kind: 'session', attributes: attributes);
  }

  void _endSpan(
    ObservabilitySpan? span, {
    Map<String, dynamic>? extra,
  }) {
    final obs = _obs;
    if (span == null || obs == null) return;
    obs.endSpan(span, extra: extra);
  }
}
