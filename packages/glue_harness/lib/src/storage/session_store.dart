import 'dart:convert';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/src/storage/file_utils.dart';
import 'package:path/path.dart' as p;

/// Metadata for a saved session, including model ref and timing.
enum SessionTitleSource { auto, user }

enum SessionTitleState { provisional, stable }

class SessionMeta {
  static const int currentSchemaVersion = 4;

  final int schemaVersion;
  final SessionId id;
  final String cwd;
  final String? projectPath;

  /// Fully-qualified model reference: `<provider>/<model>`.
  ///
  /// Schema v3+ writes this as `model_ref`. Schema ≤ 2 is read-compatible:
  /// if the stored value has no slash, the legacy `provider` field is
  /// prepended on read (see [fromJson]).
  String modelRef;
  String? reasoningEffort;
  bool? showThoughts;
  final DateTime startTime;
  DateTime? endTime;
  final String? forkedFrom;

  // Git context.
  final String? worktreePath;
  final String? branch;
  final String? baseBranch;
  final String? repoRemote;
  final String? headSha;

  // Display & organization.
  String? title;
  SessionTitleSource? titleSource;
  SessionTitleState? titleState;
  int titleGenerationCount;
  DateTime? titleGeneratedAt;
  DateTime? titleLastEvaluatedAt;
  DateTime? titleRenamedAt;
  final List<String> tags;

  // PR lifecycle.
  String? prUrl;
  String? prStatus;

  // Metrics. tokenCount tracks total LLM tokens billed across the
  // session — main agent + subagents + title generation. cacheReadTokens
  // and cacheCreationTokens are non-null on providers that report cache
  // statistics (Anthropic, OpenAI, OpenRouter); null on Ollama and
  // others that don't.
  int? tokenCount;
  int? cacheReadTokens;
  int? cacheCreationTokens;
  int? messageCount;

  // Summary.
  String? summary;

  // Runtime — populated when the session ran in a cloud sandbox.
  // Phase 3 of cloud-runtimes-correctness-plan: lets `/resume` and
  // `glue session …` reason about prior cloud sessions, detect
  // leaked sandboxes, and locate the on-disk patch.
  String? runtimeId;
  String? sandboxId;
  String? runtimeBootstrapSha;
  String? runtimeRemoteUrl;
  String? runtimePatchPath;
  DateTime? runtimeClosedAt;

  SessionMeta({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.cwd,
    this.projectPath,
    required this.modelRef,
    this.reasoningEffort,
    this.showThoughts,
    required this.startTime,
    this.endTime,
    this.forkedFrom,
    this.worktreePath,
    this.branch,
    this.baseBranch,
    this.repoRemote,
    this.headSha,
    this.title,
    this.titleSource,
    this.titleState,
    this.titleGenerationCount = 0,
    this.titleGeneratedAt,
    this.titleLastEvaluatedAt,
    this.titleRenamedAt,
    this.tags = const [],
    this.prUrl,
    this.prStatus,
    this.tokenCount,
    this.cacheReadTokens,
    this.cacheCreationTokens,
    this.messageCount,
    this.summary,
    this.runtimeId,
    this.sandboxId,
    this.runtimeBootstrapSha,
    this.runtimeRemoteUrl,
    this.runtimePatchPath,
    this.runtimeClosedAt,
  });

  Map<String, Object?> toJson() => {
    // Always emit the version of the shape we actually write (v3: `model_ref`,
    // no legacy `model`/`provider`). Writing back the loaded `schemaVersion`
    // for a legacy session tagged the v3 body as v1/v2, so `fromJson` then
    // ignored `model_ref` and resolved the model to `anthropic/unknown` (H4).
    'schema_version': currentSchemaVersion,
    'id': id.value,
    'cwd': cwd,
    if (projectPath != null) 'project_path': projectPath,
    'model_ref': modelRef,
    if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
    if (showThoughts != null) 'show_thoughts': showThoughts,
    'start_time': startTime.toUtc().toIso8601String(),
    if (endTime != null) 'end_time': endTime!.toUtc().toIso8601String(),
    if (forkedFrom != null) 'forked_from': forkedFrom,
    if (worktreePath != null) 'worktree_path': worktreePath,
    if (branch != null) 'branch': branch,
    if (baseBranch != null) 'base_branch': baseBranch,
    if (repoRemote != null) 'repo_remote': repoRemote,
    if (headSha != null) 'head_sha': headSha,
    if (title != null) 'title': title,
    if (titleSource != null) 'title_source': titleSource!.name,
    if (titleState != null) 'title_state': titleState!.name,
    if (titleGenerationCount > 0)
      'title_generation_count': titleGenerationCount,
    if (titleGeneratedAt != null)
      'title_generated_at': titleGeneratedAt!.toUtc().toIso8601String(),
    if (titleLastEvaluatedAt != null)
      'title_last_evaluated_at': titleLastEvaluatedAt!
          .toUtc()
          .toIso8601String(),
    if (titleRenamedAt != null)
      'title_renamed_at': titleRenamedAt!.toUtc().toIso8601String(),
    if (tags.isNotEmpty) 'tags': tags,
    if (prUrl != null) 'pr_url': prUrl,
    if (prStatus != null) 'pr_status': prStatus,
    if (tokenCount != null) 'token_count': tokenCount,
    if (cacheReadTokens != null) 'cache_read_tokens': cacheReadTokens,
    if (cacheCreationTokens != null)
      'cache_creation_tokens': cacheCreationTokens,
    if (messageCount != null) 'message_count': messageCount,
    if (summary != null) 'summary': summary,
    if (runtimeId != null) 'runtime_id': runtimeId,
    if (sandboxId != null) 'sandbox_id': sandboxId,
    if (runtimeBootstrapSha != null)
      'runtime_bootstrap_sha': runtimeBootstrapSha,
    if (runtimeRemoteUrl != null) 'runtime_remote_url': runtimeRemoteUrl,
    if (runtimePatchPath != null) 'runtime_patch_path': runtimePatchPath,
    if (runtimeClosedAt != null)
      'runtime_closed_at': runtimeClosedAt!.toUtc().toIso8601String(),
  };

  factory SessionMeta.fromJson(Map<String, dynamic> json) {
    final schema = json['schema_version'] as int? ?? 1;
    final String resolvedRef;
    if (schema >= 3 && json['model_ref'] is String) {
      resolvedRef = json['model_ref'] as String;
    } else {
      // Legacy schema: synthesize from separate model + provider fields.
      final legacyModel = json['model'] as String? ?? 'unknown';
      final legacyProvider = json['provider'] as String? ?? 'anthropic';
      resolvedRef = legacyModel.contains('/')
          ? legacyModel
          : '$legacyProvider/$legacyModel';
    }
    final title = json['title'] as String?;
    final titleSource = _parseTitleSource(json['title_source'] as String?);
    final titleState = _parseTitleState(json['title_state'] as String?);
    return SessionMeta(
      schemaVersion: schema,
      id: SessionId(json['id'] as String),
      cwd: json['cwd'] as String? ?? '',
      projectPath: json['project_path'] as String?,
      modelRef: resolvedRef,
      reasoningEffort: json['reasoning_effort'] as String?,
      showThoughts: json['show_thoughts'] as bool?,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      forkedFrom: json['forked_from'] as String?,
      worktreePath: json['worktree_path'] as String?,
      branch: json['branch'] as String?,
      baseBranch: json['base_branch'] as String?,
      repoRemote: json['repo_remote'] as String?,
      headSha: json['head_sha'] as String?,
      title: title,
      titleSource:
          titleSource ?? (title != null ? SessionTitleSource.auto : null),
      titleState:
          titleState ?? (title != null ? SessionTitleState.stable : null),
      titleGenerationCount:
          json['title_generation_count'] as int? ?? (title != null ? 1 : 0),
      titleGeneratedAt: json['title_generated_at'] != null
          ? DateTime.parse(json['title_generated_at'] as String)
          : null,
      titleLastEvaluatedAt: json['title_last_evaluated_at'] != null
          ? DateTime.parse(json['title_last_evaluated_at'] as String)
          : null,
      titleRenamedAt: json['title_renamed_at'] != null
          ? DateTime.parse(json['title_renamed_at'] as String)
          : null,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      prUrl: json['pr_url'] as String?,
      prStatus: json['pr_status'] as String?,
      tokenCount: json['token_count'] as int?,
      cacheReadTokens: json['cache_read_tokens'] as int?,
      cacheCreationTokens: json['cache_creation_tokens'] as int?,
      messageCount: json['message_count'] as int?,
      summary: json['summary'] as String?,
      runtimeId: json['runtime_id'] as String?,
      sandboxId: json['sandbox_id'] as String?,
      runtimeBootstrapSha: json['runtime_bootstrap_sha'] as String?,
      runtimeRemoteUrl: json['runtime_remote_url'] as String?,
      runtimePatchPath: json['runtime_patch_path'] as String?,
      runtimeClosedAt: json['runtime_closed_at'] != null
          ? DateTime.parse(json['runtime_closed_at'] as String)
          : null,
    );
  }

  static SessionTitleSource? _parseTitleSource(String? value) {
    return switch (value) {
      'auto' => SessionTitleSource.auto,
      'user' => SessionTitleSource.user,
      _ => null,
    };
  }

  static SessionTitleState? _parseTitleState(String? value) {
    return switch (value) {
      'provisional' => SessionTitleState.provisional,
      'stable' => SessionTitleState.stable,
      _ => null,
    };
  }
}

/// Thrown when a session directory is already claimed by another live Glue
/// process (M11) and cannot be opened for writing.
class SessionInUseException implements Exception {
  SessionInUseException(this.sessionDir, {this.holderPid});

  final String sessionDir;
  final int? holderPid;

  @override
  String toString() =>
      'SessionInUseException: session at $sessionDir is already open'
      '${holderPid != null ? ' in process $holderPid' : ''}';
}

/// Advisory PID lock guarding a session directory against two Glue processes
/// writing the same `conversation.jsonl` concurrently (M11).
///
/// It is a plain `.lock` file recording the owning PID — deliberately *not* an
/// OS file lock, which would keep an open handle and (on Windows) block temp
/// dir cleanup. Re-entry by the same process is allowed; a `.lock` owned by a
/// different PID fails acquisition. Released (file deleted) on [release].
///
/// Limitation: a hard crash leaves a stale `.lock`. There is no portable
/// liveness probe in Dart (no signal-0), so a stale lock blocks resume until
/// removed — the raised [SessionInUseException] names the file so it can be
/// deleted manually. TODO: portable staleness detection.
class SessionLock {
  SessionLock._(this._file);

  final File _file;
  bool _released = false;

  /// Claims [sessionDir] for the current process, or throws
  /// [SessionInUseException] if a foreign PID already holds it.
  static SessionLock acquire(String sessionDir) {
    Directory(sessionDir).createSync(recursive: true);
    final file = File(p.join(sessionDir, '.lock'));
    if (file.existsSync()) {
      final holder = _readPid(file);
      if (holder != null && holder != pid) {
        throw SessionInUseException(sessionDir, holderPid: holder);
      }
    }
    file.writeAsStringSync('$pid\n', flush: true);
    return SessionLock._(file);
  }

  static int? _readPid(File file) {
    try {
      return int.tryParse(file.readAsStringSync().trim());
    } catch (_) {
      return null;
    }
  }

  /// Releases the lock if we still own it. Idempotent.
  void release() {
    if (_released) return;
    _released = true;
    try {
      if (_file.existsSync() && _readPid(_file) == pid) {
        _file.deleteSync();
      }
    } catch (_) {}
  }
}

/// Persistent storage for a single session's metadata and conversation log.
class SessionStore {
  final String sessionDir;
  final SessionMeta meta;
  late final File _conversationFile;

  /// Advisory lock held for the lifetime of this store (M11). Null for stores
  /// opened without a lock (e.g. read-only inspection, tests). Released by
  /// [close].
  final SessionLock? _lock;

  /// Whether the owner-only permissions have been applied to the conversation
  /// log yet. Set on the first append so the chmod runs once, not per event.
  bool _conversationPermsSet = false;

  SessionStore({required this.sessionDir, required this.meta, this._lock}) {
    Directory(sessionDir).createSync(recursive: true);
    _restrictDirPerms(sessionDir);
    _conversationFile = File(p.join(sessionDir, 'conversation.jsonl'));
    _writeMeta();
  }

  /// Restricts [dir] to owner-only (0700) on non-Windows. Session dirs hold
  /// full transcripts, so they should not be group/world traversable (L3).
  static void _restrictDirPerms(String dir) {
    if (Platform.isWindows) return;
    try {
      Process.runSync('chmod', ['700', dir]);
    } catch (_) {}
  }

  void _writeMeta() {
    const encoder = JsonEncoder.withIndent('  ');
    final file = File(p.join(sessionDir, 'meta.json'));
    atomicWrite(file, encoder.convert(meta.toJson()));
  }

  void setTitle(
    String title, {
    SessionTitleSource? source,
    SessionTitleState? state,
    int? generationCount,
    DateTime? generatedAt,
    DateTime? lastEvaluatedAt,
    DateTime? renamedAt,
  }) {
    meta.title = title;
    meta.titleSource = source ?? meta.titleSource;
    meta.titleState = state ?? meta.titleState;
    if (generationCount != null) {
      meta.titleGenerationCount = generationCount;
    }
    meta.titleGeneratedAt = generatedAt ?? meta.titleGeneratedAt;
    meta.titleLastEvaluatedAt = lastEvaluatedAt ?? meta.titleLastEvaluatedAt;
    meta.titleRenamedAt = renamedAt ?? meta.titleRenamedAt;
    _writeMeta();
  }

  /// Writes the current metadata to disk.
  void updateMeta() => _writeMeta();

  /// Appends a timestamped event record to the conversation log. Uses a
  /// single append-mode write — the session dir already exists (constructor).
  ///
  /// Flushes each append so a crash can't strip the tail line (M12). The log
  /// is chmod'd to owner-only (0600) on its first write (L3).
  ///
  /// TODO(L7): the conversation log grows unbounded — full request/response
  /// content is retained forever. A size/age cap or rollup should be added
  /// before this becomes a disk-usage problem on long-lived sessions.
  void logEvent(String type, Map<String, dynamic> data) {
    final record = {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'type': type,
      ...data,
    };
    _conversationFile.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
    _restrictConversationPerms();
  }

  void _restrictConversationPerms() {
    if (_conversationPermsSet || Platform.isWindows) return;
    _conversationPermsSet = true;
    try {
      Process.runSync('chmod', ['600', _conversationFile.path]);
    } catch (_) {}
  }

  /// Closes this session, recording the end time and releasing the advisory
  /// lock (M11) so another process may resume it.
  Future<void> close() async {
    meta.endTime = DateTime.now().toUtc();
    _writeMeta();
    _lock?.release();
  }

  /// Lists all saved sessions in [sessionsDir], sorted newest first.
  static List<SessionMeta> listSessions(String sessionsDir) {
    final dir = Directory(sessionsDir);
    if (!dir.existsSync()) return [];

    final sessions = <SessionMeta>[];
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final metaFile = File(p.join(entry.path, 'meta.json'));
      if (!metaFile.existsSync()) continue;
      try {
        final json =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        sessions.add(SessionMeta.fromJson(json));
      } catch (_) {}
    }

    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    return sessions;
  }

  /// Loads the conversation log for a session from its [sessionDir].
  static List<Map<String, dynamic>> loadConversation(String sessionDir) {
    final file = File(p.join(sessionDir, 'conversation.jsonl'));
    if (!file.existsSync()) return [];

    final events = <Map<String, dynamic>>[];
    var skipped = 0;
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        events.add(jsonDecode(line) as Map<String, dynamic>);
      } catch (_) {
        // A torn tail line (partial write interrupted by a crash) or an
        // otherwise corrupt record. Count it rather than dropping it
        // silently, so the loss is at least observable (M12).
        skipped++;
      }
    }
    if (skipped > 0) {
      stderr.writeln('glue: skipped $skipped corrupt line(s) in ${file.path}');
    }
    return events;
  }
}
