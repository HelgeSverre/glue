/// Event-emission helpers for [CommandExecutor] implementations.
///
/// Extracts the repetitive event-sink boilerplate that [HostExecutor] and
/// [DockerExecutor] both duplicate so each executor only provides the
/// process-startup logic and the optional cancel-action.
library;

import 'dart:io';

import 'package:glue_core/glue_core.dart';

import 'package:glue_strategies/src/shell/command_executor.dart';

/// Convenience wrappers on the nullable event sink so callers don't repeat
/// the `?.call(...)` + object-construction pattern in every executor.
extension CommandEventSink on RuntimeEventSink? {
  void emitStarted({
    required String commandId,
    required String runtimeId,
    required String command,
    required String runtimeCwd,
  }) {
    this?.call(
      RuntimeCommandStarted(
        commandId: commandId,
        runtimeId: runtimeId,
        at: DateTime.now(),
        command: command,
        runtimeCwd: runtimeCwd,
      ),
    );
  }

  void emitCompleted({
    required String commandId,
    required String runtimeId,
    required int exitCode,
    required Duration duration,
    int? stdoutBytes,
    int? stderrBytes,
  }) {
    this?.call(
      RuntimeCommandCompleted(
        commandId: commandId,
        runtimeId: runtimeId,
        at: DateTime.now(),
        exitCode: exitCode,
        duration: duration,
        stdoutBytes: stdoutBytes,
        stderrBytes: stderrBytes,
      ),
    );
  }

  void emitCancelled({
    required String commandId,
    required String runtimeId,
    required String reason,
  }) {
    this?.call(
      RuntimeCommandCancelled(
        commandId: commandId,
        runtimeId: runtimeId,
        at: DateTime.now(),
        reason: reason,
      ),
    );
  }

  void emitFailed({
    required String commandId,
    required String runtimeId,
    required String errorType,
    required String message,
  }) {
    this?.call(
      RuntimeCommandFailed(
        commandId: commandId,
        runtimeId: runtimeId,
        at: DateTime.now(),
        errorType: errorType,
        message: message,
      ),
    );
  }

  /// Attaches an exit handler that emits [RuntimeCommandCompleted] when the
  /// process finishes. Used by the `startStreaming` method in each executor.
  void monitorStreamExit({
    required Process process,
    required String commandId,
    required String runtimeId,
    required DateTime started,
  }) {
    final sink = this;
    if (sink != null) {
      process.exitCode.then((code) {
        sink(
          RuntimeCommandCompleted(
            commandId: commandId,
            runtimeId: runtimeId,
            at: DateTime.now(),
            exitCode: code,
            duration: DateTime.now().difference(started),
          ),
        );
      });
    }
  }
}

/// Shared utility to wait for a process to exit, optionally with a timeout.
///
/// When [timeout] is provided and the process does not exit within that
/// duration, [onCancel] is called (for Docker this stops the container)
/// before killing the process. Returns `-1` on timeout.
///
/// Both [HostExecutor] and [DockerExecutor] use this instead of duplicating
/// the timeout-or-exit logic.
Future<int> waitForExit(
  Process process,
  Duration? timeout, {
  void Function()? onCancel,
}) async {
  if (timeout == null) return process.exitCode;
  return process.exitCode.timeout(
    timeout,
    onTimeout: () {
      onCancel?.call();
      process.kill();
      return -1;
    },
  );
}
