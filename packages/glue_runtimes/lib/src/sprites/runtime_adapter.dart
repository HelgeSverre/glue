import 'dart:io';

import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/sprites/config.dart';
import 'package:glue_runtimes/src/sprites/runtime.dart';

/// Builds a [SpritesConfig] from a `runtime_options` map and env.
SpritesConfig spritesConfigFromOptions(
  Map<String, Object?> options, {
  Map<String, String>? env,
}) {
  final e = env ?? Platform.environment;
  final spriteCliPath =
      (options['sprite_cli'] as String?) ?? e['SPRITES_CLI'] ?? 'sprite';
  final spriteName = (options['sprite_name'] as String?) ?? e['SPRITES_NAME'];
  final deleteOnClose = options['delete_on_close'] is bool
      ? options['delete_on_close'] as bool
      : (e['SPRITES_DELETE_ON_CLOSE']?.toLowerCase() != 'false');
  return SpritesConfig(
    spriteCliPath: spriteCliPath,
    spriteName: spriteName,
    deleteOnClose: deleteOnClose,
  );
}

/// Registers the Sprites adapter with [RuntimeFactory]. Call once at
/// startup before [ServiceLocator.create].
void registerSpritesRuntime() {
  RuntimeFactory.register('sprites', ({
    required cwd,
    required options,
    eventSink,
  }) async {
    final spritesConfig = spritesConfigFromOptions(options);
    return SpritesRuntime.start(
      config: spritesConfig,
      hostCwd: cwd,
      eventSink: eventSink,
    );
  });
}
