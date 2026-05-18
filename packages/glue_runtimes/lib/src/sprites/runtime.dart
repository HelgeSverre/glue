import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

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
      final executor = SpritesExecutor(cli: cli, spriteName: name);
      final workspace = TransportWorkspace(
        fs: SpritesFsTransport(cli: cli, spriteName: name),
        mapping: mapping,
      );
      return SpritesRuntime._(
        cli: cli,
        config: config,
        spriteName: name,
        executor: executor,
        workspace: workspace,
        bootstrapSha: result.bootstrapSha,
        resumed: result.resumed,
      );
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
}
