import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/common/diff.dart';
import 'package:glue_runtimes/src/sprites/bootstrap.dart';
import 'package:glue_runtimes/src/sprites/cli.dart';
import 'package:glue_runtimes/src/sprites/config.dart';
import 'package:glue_runtimes/src/sprites/executor.dart';
import 'package:glue_runtimes/src/sprites/workspace.dart';

/// The top-level Sprites runtime — owns one sprite for the lifetime
/// of a Glue session.
///
/// Sprites are persistent and named. If [SpritesConfig.spriteName] is
/// set, we resume the existing sprite instead of creating a new one;
/// if [SpritesConfig.deleteOnClose] is `false`, [close] leaves the
/// sprite to auto-sleep so the next session can resume it.
class SpritesRuntime implements RuntimeSession {
  final SpritesCliBase _cli;
  final SpritesConfig _config;
  final String spriteName;

  @override
  final CommandExecutor executor;

  @override
  final Workspace workspace;

  @override
  final String? bootstrapSha;

  @override
  final bool resumed;

  SpritesRuntime._({
    required SpritesCliBase cli,
    required SpritesConfig config,
    required this.spriteName,
    required this.executor,
    required this.workspace,
    required this.bootstrapSha,
    required this.resumed,
  })  : _cli = cli,
        _config = config;

  @override
  String get id => 'sprites';

  @override
  String get sandboxId => spriteName;

  /// Spins up (or resumes) a sprite and returns a fully-wired runtime.
  static Future<SpritesRuntime> start({
    required SpritesConfig config,
    required String hostCwd,
    String runtimeCwd = '/workspace',
    SpritesCliBase? cliOverride,
    RuntimeEventSink? eventSink,
  }) async {
    final cli = cliOverride ?? SpritesCli(config);
    if (!await cli.isAvailable()) {
      throw StateError(
        'Sprites runtime requires the `sprite` CLI to be installed '
        'and authenticated. Install from https://sprites.dev/install.sh '
        'and run `sprite login` before retrying.',
      );
    }

    final name = config.spriteName ??
        'glue-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

    var createdHere = false;
    try {
      if (!await cli.spriteExists(name)) {
        await cli.createSprite(name);
        createdHere = true;
      }

      final bootstrap = SpritesBootstrap(cli: cli, spriteName: name);
      final result = await bootstrap.bootstrap(
        hostCwd: hostCwd,
        runtimeCwd: runtimeCwd,
      );

      final mapping = WorkspaceMapping(
        hostCwd: hostCwd,
        runtimeCwd: runtimeCwd,
      );
      final executor = SpritesExecutor(
        cli: cli,
        spriteName: name,
        eventSink: eventSink,
      );
      final workspace = TransportWorkspace(
        fs: SpritesFsTransport(cli: cli, spriteName: name),
        mapping: mapping,
      );
      final runtime = SpritesRuntime._(
        cli: cli,
        config: config,
        spriteName: name,
        executor: executor,
        workspace: workspace,
        bootstrapSha: result.bootstrapSha,
        resumed: result.resumed,
      );
      // On resume there's no bootstrap SHA from the bootstrap helper
      // (we skipped the clone). Re-baseline against whatever the
      // sandbox's current HEAD is so a second session can still
      // produce a diff. If the resumed worktree is dirty (Q1: refuse
      // explicitly — silent is worse than blocking) we abort so the
      // user can commit/export inside the sandbox before retrying.
      if (result.resumed) {
        await runtime._rebaselineFromResumedSandbox(runtimeCwd);
      }
      return runtime;
    } catch (e) {
      // Only tear down a sprite we created ourselves — never delete
      // one we resumed.
      if (createdHere) {
        try {
          await cli.deleteSprite(name);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Releases the sprite. When [SpritesConfig.deleteOnClose] is true
  /// (default), the sprite is deleted; otherwise it's left to
  /// auto-sleep so the next session can resume.
  @override
  Future<void> close() async {
    if (_config.deleteOnClose) {
      await _cli.deleteSprite(spriteName);
    }
  }

  @override
  Future<RuntimeDiffOutcome> diffSinceBootstrap() async {
    final outcome = await captureWorkspaceDiff(
      executor: executor,
      runtimeCwd: workspace.mapping.runtimeCwd,
      bootstrapSha: _effectiveBootstrapSha,
      runtimeId: id,
      sandboxId: spriteName,
    );
    return outcome.toSurfaceOutcome();
  }

  /// On resume, [bootstrapSha] from the bootstrap call is null. We
  /// re-baseline against whatever the sandbox's current HEAD is so a
  /// second session can still produce a diff for changes made during
  /// that session. The re-baselined SHA is captured during [start].
  String? get _effectiveBootstrapSha =>
      bootstrapSha ?? _resumeBaselineSha;
  String? _resumeBaselineSha;

  Future<void> _rebaselineFromResumedSandbox(String runtimeCwd) async {
    final head = await executor.runCapture(
      'git -C $runtimeCwd rev-parse HEAD 2>/dev/null',
    );
    if (head.exitCode != 0 || head.stdout.trim().isEmpty) {
      // Resumed sprite without a git repo at runtimeCwd — no baseline
      // is possible. Surface this as DiffUnavailable later rather than
      // refuse to start (user may have intentionally non-git workspace).
      return;
    }
    final status = await executor.runCapture(
      'git -C $runtimeCwd status --porcelain=v1 --untracked-files=normal',
    );
    if (status.exitCode == 0 && status.stdout.trim().isNotEmpty) {
      throw StateError(
        'Sprite "$spriteName" has uncommitted changes from a previous '
        'session in $runtimeCwd. Commit or export them inside the '
        'sandbox before resuming, e.g.:\n'
        '  sprite exec $spriteName -- bash -lc "cd $runtimeCwd && '
        'git add -A && git commit -m \'resume baseline\'"\n'
        '(Q1 default: refuse silently broken cases — see '
        'docs/plans/2026-05-19-cloud-runtimes-correctness-plan.md)',
      );
    }
    _resumeBaselineSha = head.stdout.trim();
  }
}
