import 'package:glue/src/session/session_manager.dart';
import 'package:glue/src/session/session_title_state_controller.dart';
import 'package:glue/src/storage/session_store.dart';

/// Feature-facing handle to the current session and session lifecycle ops.
///
/// Wraps [SessionManager] plus app-layer hooks (resume, fork, ensureStore)
/// so controllers don't carry 5–8 separate closures for session plumbing.
///
/// Disk-level persistence stays in [SessionManager] / `storage/session_store`
/// underneath — this service is just the controller-facing facade.
class Session {
  Session({
    required this.manager,
    required void Function() ensureStore,
    required String Function(SessionMeta meta) resume,
    required void Function(int userMessageIndex, String messageText) fork,
    required this.titleState,
  })  : _ensureStore = ensureStore,
        _resume = resume,
        _fork = fork;

  final SessionManager manager;
  final SessionTitleStateController titleState;
  final void Function() _ensureStore;
  final String Function(SessionMeta meta) _resume;
  final void Function(int userMessageIndex, String messageText) _fork;

  /// Metadata for the currently open session, or null if none yet.
  SessionMeta? get currentMeta => manager.currentStore?.meta;

  /// Id of the currently open session, or null if none.
  String? get currentId => manager.currentSessionId;

  /// The disk-backed store for the current session, or null.
  SessionStore? get currentStore => manager.currentStore;

  /// All saved sessions, most-recent-first.
  List<SessionMeta> list() => manager.listSessions();

  /// Resume a specific session. Returns the system-visible status string
  /// (empty on success / silent paths).
  String resume(SessionMeta meta) => _resume(meta);

  /// Fork the current conversation at the given user-message index.
  void fork(int userMessageIndex, String messageText) =>
      _fork(userMessageIndex, messageText);

  /// Rename the current session's title.
  Future<void> rename(String title) => manager.renameTitle(title);

  /// Update the model-ref stored on the current session's metadata.
  void updateModel(String modelRef) =>
      manager.updateSessionModel(modelRef: modelRef);

  /// Create the session store if not already created.
  void ensureStore() => _ensureStore();

  /// Flush and close the current session's on-disk store.
  Future<void> closeCurrent() => manager.closeCurrent();
}
