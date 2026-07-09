import 'dart:async';
import 'dart:io';

import 'package:glue_runtimes/src/sprites/cli.dart';

/// In-memory fake of [SpritesCliBase] for unit tests.
///
/// Records every call into [executedCommands]; canned exec results
/// can be primed via [execCaptureResults].
class FakeSpritesCli implements SpritesCliBase {
  final List<String> executedCommands = [];

  /// command-string → canned result. Falls back to exit 0/empty.
  final Map<String, SpritesExecResult> execCaptureResults = {};

  /// Names of sprites that should appear to exist.
  final Set<String> existingSprites = {};

  /// Sprite names that have been created via this fake.
  final List<String> createdSprites = [];

  /// Sprite names that have been deleted via this fake.
  final List<String> deletedSprites = [];

  bool available = true;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> spriteExists(String name) async =>
      existingSprites.contains(name);

  @override
  Future<void> createSprite(String name) async {
    createdSprites.add(name);
    existingSprites.add(name);
  }

  @override
  Future<void> deleteSprite(String name) async {
    deletedSprites.add(name);
    existingSprites.remove(name);
  }

  /// Records `(command, stdinBytes)` pairs fed to [execCaptureStdin].
  final List<({String command, List<int> stdin})> stdinCommands = [];

  /// When true, [execCaptureStdin] returns a non-zero result — lets
  /// tests exercise the write-failure path without reconstructing the
  /// exact command string.
  bool failStdinWrites = false;

  @override
  Future<SpritesExecResult> execCapture(
    String spriteName,
    String command, {
    Duration? timeout,
  }) async {
    executedCommands.add(command);
    return execCaptureResults[command] ??
        SpritesExecResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<SpritesExecResult> execCaptureStdin(
    String spriteName,
    String command,
    List<int> stdinBytes, {
    Duration? timeout,
  }) async {
    executedCommands.add(command);
    stdinCommands.add((command: command, stdin: stdinBytes));
    if (failStdinWrites) {
      return SpritesExecResult(exitCode: 1, stdout: '', stderr: 'write failed');
    }
    return execCaptureResults[command] ??
        SpritesExecResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<Process> execStream(String spriteName, String command) {
    throw UnimplementedError(
      'FakeSpritesCli.execStream not implemented — extend if streaming '
      'tests are needed.',
    );
  }
}
