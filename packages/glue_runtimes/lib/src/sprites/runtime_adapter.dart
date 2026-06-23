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
  RuntimeFactory.registerDiagnostics('sprites', spritesDiagnostics);
}

/// Sprites readiness probe. Glue wraps the official `sprite` CLI (the
/// API's wire protocol is in RC flux and there's no stable
/// `/filesystem` REST endpoint today), so the readiness check is
/// "binary on PATH, user is logged in", plus the resolved sprite name.
Iterable<RuntimeDiagnostic> spritesDiagnostics(RuntimeDiagnosticContext ctx) {
  final cliPath = ctx.optionOrEnv('sprite_cli', 'SPRITES_CLI') ?? 'sprite';
  String? failureReason;
  try {
    final res = Process.runSync(cliPath, ['list']);
    if (res.exitCode != 0) {
      failureReason = 'not authenticated — run `sprite login`';
    }
  } on ProcessException {
    failureReason = 'not found on PATH';
  }
  final spriteName = ctx.optionOrEnv('sprite_name', 'SPRITES_NAME');
  return [
    failureReason == null
        ? RuntimeDiagnostic.ok('`$cliPath` CLI installed and authenticated')
        : RuntimeDiagnostic.error('`$cliPath` CLI: $failureReason'),
    RuntimeDiagnostic.info(
      spriteName == null
          ? 'Sprite name: auto (a fresh sprite per session)'
          : 'Sprite name: $spriteName (resumes on each session)',
    ),
  ];
}
