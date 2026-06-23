import 'package:glue_core/glue_core.dart';

import 'package:glue_strategies/src/fs/local_workspace.dart';
import 'package:glue_strategies/src/fs/workspace.dart';
import 'package:glue_strategies/src/runtime/runtime_diagnostic.dart';
import 'package:glue_strategies/src/runtime/runtime_diff.dart';
import 'package:glue_strategies/src/shell/command_executor.dart';
import 'package:glue_strategies/src/shell/docker_config.dart';
import 'package:glue_strategies/src/shell/executor_factory.dart';
import 'package:glue_strategies/src/shell/shell_config.dart';

/// Per-session runtime — owns the [CommandExecutor] and [Workspace]
/// that tools route through, plus the lifecycle hook glue calls on
/// session shutdown.
///
/// Built-in implementations:
/// - `host` / `docker` — returned by [RuntimeFactory.create] directly;
///   exposed as anonymous instances via [_BuiltinRuntimeSession].
/// - Cloud adapters (`daytona`, `sprites`, `modal`) implement this
///   interface on their `*Runtime` class so callers can read
///   sandbox metadata uniformly.
///
/// [sandboxId] and [bootstrapSha] are best-effort diagnostics for
/// cloud runtimes; built-in runtimes return empty / null.
abstract class RuntimeSession {
  /// Adapter id: `'host'`, `'docker'`, `'daytona'`, `'sprites'`,
  /// `'modal'`, … Stable across sessions, used for capability lookup
  /// and `/runtime` display.
  String get id;

  /// Per-runtime sandbox identifier (Daytona sandbox id, sprite
  /// name, Modal sandbox object id). Empty string for host/docker
  /// runtimes that have no per-session sandbox.
  String get sandboxId;

  /// Commit SHA the workspace was bootstrapped from inside the
  /// sandbox. `null` for host/docker (no bootstrap) and for cloud
  /// sandboxes that were resumed from an existing
  /// `/workspace/.git`.
  String? get bootstrapSha;

  /// True when the runtime resumed an existing sandbox instead of
  /// creating a fresh one. Always `false` for host/docker.
  bool get resumed;

  /// The executor that [BashTool] and friends route through.
  CommandExecutor get executor;

  /// The workspace that [ReadFileTool] / [WriteFileTool] / etc.
  /// route through.
  Workspace get workspace;

  /// Releases runtime resources on session shutdown. Host/docker
  /// runtimes return immediately; cloud runtimes stop the sandbox
  /// (or leave it to auto-sleep when `delete_on_close: false`).
  Future<void> close();

  /// Returns the outcome of attempting to diff the runtime workspace
  /// against [bootstrapSha]. The default implementation reports
  /// [RuntimeDiffOutcomeUnavailable] (host/docker, no diff capture) via
  /// [diffNotSupported]. Cloud runtimes override this to return
  /// [RuntimeDiffOutcomeSuccess], [RuntimeDiffOutcomeEmpty], or
  /// [RuntimeDiffOutcomeUnavailable] with a typed reason and a hint.
  ///
  /// Returning `unavailable` is explicitly *not* the same as "no
  /// changes". Surfaces must turn `unavailable` into a visible warning
  /// so the user knows the session didn't silently lose their work.
  Future<RuntimeDiffOutcome> diffSinceBootstrap() async => diffNotSupported;

  /// Shared `notSupported` outcome for runtimes that capture no
  /// end-of-session diff (host/docker). Single source of truth so the
  /// interface default and the built-in session don't drift.
  static const RuntimeDiffOutcome diffNotSupported =
      RuntimeDiffOutcomeUnavailable(
        reason: RuntimeDiffUnavailableReason.notSupported,
        hint:
            'host/docker runtimes work directly on the host filesystem; '
            'no end-of-session diff is captured',
      );
}

/// Builds a [RuntimeSession] for `runtime: <name>` from config.
///
/// Two runtimes are built in: `host` and `docker`. Cloud adapters
/// (`daytona`, `sprites`, `modal`) register themselves via [register]
/// from a surface (`cli/bin/glue.dart`) at startup — this keeps
/// `glue_strategies` free of any dependency on cloud-specific packages.
class RuntimeFactory {
  RuntimeFactory._();

  static final Map<String, RuntimeAdapter> _adapters = {};

  static final Map<String, RuntimeDiagnoser> _diagnosers = {};

  /// Registers a cloud adapter under [name]. The surface (cli) calls
  /// this once at startup before [create] is invoked.
  static void register(String name, RuntimeAdapter adapter) {
    _adapters[name] = adapter;
  }

  /// Registers the readiness-probe function for runtime [name]. Each
  /// `register*Runtime()` helper calls this alongside [register] so the
  /// adapter — not the surface — owns its per-cloud probing logic.
  /// Optional: a runtime with no diagnoser simply produces no findings.
  static void registerDiagnostics(String name, RuntimeDiagnoser diagnoser) {
    _diagnosers[name] = diagnoser;
  }

  /// Runs the registered readiness probe for [runtime] against [ctx],
  /// or returns no findings when the runtime has none registered
  /// (e.g. `host`/`docker`, which are diagnosed by the surface).
  static Iterable<RuntimeDiagnostic> diagnose(
    String runtime,
    RuntimeDiagnosticContext ctx,
  ) {
    final diagnoser = _diagnosers[runtime];
    if (diagnoser == null) return const [];
    return diagnoser(ctx);
  }

  /// Returns the set of registered cloud-adapter names. Useful for
  /// `glue doctor` and the `/runtime` slash command.
  static Iterable<String> registeredAdapters() => _adapters.keys;

  /// Resolves the runtime named [runtime] and returns its session.
  ///
  /// - `'host'` → [HostExecutor] + identity [LocalWorkspace].
  /// - `'docker'` → [DockerExecutor] + identity [LocalWorkspace]
  ///    (Docker bind-mounts the host cwd so the host filesystem stays
  ///    authoritative).
  /// - any other value → a registered adapter, or [StateError] if
  ///   none is registered.
  ///
  /// [runtimeOptions] holds the YAML section for the named runtime
  /// (e.g. the `daytona:` block when `runtime: daytona` is selected).
  /// Cloud adapters parse this on startup; host/Docker ignore it.
  static Future<RuntimeSession> create({
    required String runtime,
    required ShellConfig shellConfig,
    required DockerConfig dockerConfig,
    required String cwd,
    Map<String, Object?> runtimeOptions = const {},
    List<MountEntry> sessionMounts = const [],
    bool? dockerAvailable,
    RuntimeEventSink? eventSink,
  }) async {
    if (runtime == 'host' || runtime == 'docker') {
      // Force-disable docker when runtime=host even if `docker.enabled`
      // is true in user config (e.g. a leftover); pass through
      // unchanged for runtime=docker.
      final effectiveDockerConfig = runtime == 'docker'
          ? dockerConfig
          : const DockerConfig();
      final executor = await ExecutorFactory.create(
        shellConfig: shellConfig,
        dockerConfig: effectiveDockerConfig,
        cwd: cwd,
        sessionMounts: sessionMounts,
        dockerAvailable: dockerAvailable,
        eventSink: eventSink,
      );
      final mapping = WorkspaceMapping.host(cwd);
      return _BuiltinRuntimeSession(
        id: runtime,
        executor: executor,
        workspace: LocalWorkspace(mapping),
      );
    }
    final adapter = _adapters[runtime];
    if (adapter == null) {
      final known = ['host', 'docker', ..._adapters.keys].join(', ');
      throw StateError(
        'Unknown runtime "$runtime". Known runtimes: $known. '
        'Cloud adapters must be registered via RuntimeFactory.register '
        'before ServiceLocator.create.',
      );
    }
    return adapter(cwd: cwd, options: runtimeOptions, eventSink: eventSink);
  }
}

/// Built-in [RuntimeSession] for host / docker. Carries no sandbox
/// metadata since neither runtime has a per-session sandbox.
///
/// {@category Runtime}
class _BuiltinRuntimeSession implements RuntimeSession {
  @override
  final String id;
  @override
  final CommandExecutor executor;
  @override
  final Workspace workspace;

  _BuiltinRuntimeSession({
    required this.id,
    required this.executor,
    required this.workspace,
  });

  @override
  String get sandboxId => '';

  @override
  String? get bootstrapSha => null;

  @override
  bool get resumed => false;

  @override
  Future<void> close() async {}

  @override
  Future<RuntimeDiffOutcome> diffSinceBootstrap() async =>
      RuntimeSession.diffNotSupported;
}

/// Snapshot of the immutable runtime metadata that surfaces persist
/// alongside the session (`SessionMeta`) so `/resume`, `glue session
/// …`, and the cleanup sweep have a stable handle on what runtime
/// the session used.
class RuntimeInfoSnapshot {
  final String runtimeId;
  final String sandboxId;
  final String? bootstrapSha;
  final String? remoteUrl;
  const RuntimeInfoSnapshot({
    required this.runtimeId,
    required this.sandboxId,
    this.bootstrapSha,
    this.remoteUrl,
  });

  /// Builds a snapshot from a live [RuntimeSession]. Cheap — just
  /// reads getters and shapes the data.
  factory RuntimeInfoSnapshot.from(RuntimeSession session) {
    return RuntimeInfoSnapshot(
      runtimeId: session.id,
      sandboxId: session.sandboxId,
      bootstrapSha: session.bootstrapSha,
    );
  }
}

/// Signature a cloud runtime adapter must implement. [options] is the
/// YAML section from the user's config for this adapter (parsed by
/// the harness as a generic untyped map).
typedef RuntimeAdapter =
    Future<RuntimeSession> Function({
      required String cwd,
      required Map<String, Object?> options,
      RuntimeEventSink? eventSink,
    });
