import 'dart:async';
import 'dart:io';

import 'package:glue/src/app.dart' show AppMode;
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/redaction.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:glue/src/ui/rendering/ansi_utils.dart';

/// "Bash mode" — the state the editor enters when the user presses `!` at
/// an empty prompt. Commands typed in this mode bypass the LLM entirely
/// and run through [CommandExecutor]; `&`-prefixed commands fire and
/// forget via [ShellJobManager] so they don't block the UI.
///
/// Lifecycle is independent of an agent [Turn] because bash commands
/// don't involve the LLM at all — the observability span hierarchy and
/// process handle are this class's private state, not the turn's.
class BashMode {
  BashMode({
    required this.transcript,
    required this.executor,
    required this.jobs,
    required this.obs,
    required this.setMode,
    required this.stopSpinner,
    required this.render,
  });

  final Transcript transcript;
  final CommandExecutor executor;
  final ShellJobManager jobs;
  final Observability? obs;
  final void Function(AppMode) setMode;
  final void Function() stopSpinner;
  final void Function() render;

  /// Whether the `!` prompt is currently showing. Toggled by the input
  /// router when the user enters/leaves bash mode at the empty prompt.
  bool active = false;

  Process? _runProcess;
  ObservabilitySpan? _span;

  /// Handle the user submitting a command while in bash mode. Lines
  /// prefixed with `& ` (or bare `&`) run as background jobs; everything
  /// else runs synchronously and blocks the UI until the command exits.
  void submit(String text) {
    if (text.isEmpty) return;
    if (text.startsWith('& ') || text == '&') {
      final command = text.substring(1).trim();
      if (command.isEmpty) return;
      startBackground(command);
      return;
    }

    setMode(AppMode.bashRunning);
    render();
    unawaited(runBlocking(text));
  }

  Future<void> runBlocking(String command) async {
    final span = obs?.startSpan(
      'shell.command',
      kind: 'shell.command',
      attributes: {
        'process.command': redactBody(command, maxBytes: 8192),
        'process.background': false,
      },
    );
    _span = span;
    try {
      final running = await executor.startStreaming(command);
      _runProcess = running.process;

      final stdoutFuture =
          running.stdout.transform(const SystemEncoding().decoder).join();
      final stderrFuture =
          running.stderr.transform(const SystemEncoding().decoder).join();

      final exitCode = await running.exitCode;
      _runProcess = null;

      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;

      final output = StringBuffer();
      if (stdout.isNotEmpty) output.write(stdout);
      if (stderr.isNotEmpty) {
        if (output.isNotEmpty) output.write('\n');
        output.write(stderr);
      }

      final stripped = stripAnsi(output.toString().trimRight());
      transcript.blocks.add(ConversationEntry.bash(command, stripped));
      if (exitCode != 0) {
        transcript.blocks
            .add(ConversationEntry.system('Exit code: $exitCode'));
      }
      if (span != null && obs != null && span.endTime == null) {
        obs!.endSpan(span, extra: {
          'process.exit_code': exitCode,
          'process.output_length': stripped.length,
        });
      }
    } catch (e) {
      _runProcess = null;
      transcript.blocks.add(ConversationEntry.error('Bash error: $e'));
      if (span != null && obs != null && span.endTime == null) {
        obs!.endSpan(span, extra: {
          'error': true,
          'error.type': e.runtimeType.toString(),
          'error.message': e.toString(),
        });
      }
    }
    _span = null;
    setMode(AppMode.idle);
    render();
  }

  /// Cancel the blocking command (if any). Sends SIGTERM to the process,
  /// closes the span, and returns the app to idle. Mirrors the agent
  /// cancel contract: also stops the spinner even though this path
  /// doesn't start one, as cheap insurance against future reorderings.
  void cancel() {
    final span = _span;
    if (span != null && obs != null && span.endTime == null) {
      obs!.endSpan(span, extra: {'cancelled': true});
    }
    _span = null;
    _runProcess?.kill(ProcessSignal.sigterm);
    _runProcess = null;
    stopSpinner();
    setMode(AppMode.idle);
    transcript.blocks
        .add(ConversationEntry.system('[bash command cancelled]'));
    render();
  }

  /// Start a background job (`&`-prefixed command). Fire-and-forget —
  /// progress is reported via [handleJobEvent] when the underlying
  /// [ShellJobManager] emits `JobStarted` / `JobExited` / `JobError`.
  void startBackground(String command) {
    unawaited(() async {
      try {
        await jobs.start(command);
      } catch (e) {
        transcript.blocks
            .add(ConversationEntry.error('Failed to start job: $e'));
        render();
      }
    }());
  }

  /// Fold a [JobEvent] from [ShellJobManager] into the transcript as a
  /// system-visible notice. Called from App's subscription to
  /// `jobs.events` since background jobs aren't bound to any one
  /// [BashMode] lifetime.
  void handleJobEvent(JobEvent event) {
    switch (event) {
      case JobStarted(:final id, :final command):
        transcript.blocks
            .add(ConversationEntry.system('↳ Started job #$id: $command'));
        render();
      case JobExited(:final id, :final exitCode):
        final job = jobs.getJob(id);
        final cmd = job?.command ?? '?';
        final label = exitCode == 0 ? 'exited' : 'failed';
        transcript.blocks.add(
            ConversationEntry.system('↳ Job #$id $label ($exitCode): $cmd'));
        render();
      case JobError(:final id, :final error):
        transcript.blocks
            .add(ConversationEntry.system('↳ Job #$id error: $error'));
        render();
    }
  }
}
