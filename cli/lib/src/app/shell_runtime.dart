part of 'package:glue/src/app.dart';

void _handleBashSubmitImpl(App app, String text) {
  if (text.isEmpty) return;

  if (text.startsWith('& ') || text == '&') {
    final command = text.substring(1).trim();
    if (command.isEmpty) return;
    app._startBackgroundJob(command);
    return;
  }

  app._mode = AppMode.bashRunning;
  app._render();
  unawaited(app._runBlockingBash(text));
}

Future<void> _runBlockingBashImpl(App app, String command) async {
  final span = app._obs?.startSpan(
    'shell.command',
    kind: 'shell.command',
    attributes: {
      'process.command': redactBody(command, maxBytes: 8192),
      'process.background': false,
    },
  );
  app._bashSpan = span;
  try {
    final running = await app._executor.startStreaming(command);
    app._bashRunProcess = running.process;

    final stdoutFuture =
        running.stdout.transform(const SystemEncoding().decoder).join();
    final stderrFuture =
        running.stderr.transform(const SystemEncoding().decoder).join();

    final exitCode = await running.exitCode;
    app._bashRunProcess = null;

    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;

    final output = StringBuffer();
    if (stdout.isNotEmpty) output.write(stdout);
    if (stderr.isNotEmpty) {
      if (output.isNotEmpty) output.write('\n');
      output.write(stderr);
    }

    final stripped = stripAnsi(output.toString().trimRight());
    app._blocks.add(_ConversationEntry.bash(command, stripped));
    if (exitCode != 0) {
      app._blocks.add(_ConversationEntry.system('Exit code: $exitCode'));
    }
    if (span != null && app._obs != null && span.endTime == null) {
      app._obs!.endSpan(span, extra: {
        'process.exit_code': exitCode,
        'process.output_length': stripped.length,
      });
    }
  } catch (e) {
    app._bashRunProcess = null;
    app._blocks.add(_ConversationEntry.error('Bash error: $e'));
    if (span != null && app._obs != null && span.endTime == null) {
      app._obs!.endSpan(span, extra: {
        'error': true,
        'error.type': e.runtimeType.toString(),
        'error.message': e.toString(),
      });
    }
  }
  app._bashSpan = null;
  app._mode = AppMode.idle;
  app._render();
}

void _cancelBashImpl(App app) {
  final span = app._bashSpan;
  if (span != null && app._obs != null && span.endTime == null) {
    app._obs!.endSpan(span, extra: {
      'cancelled': true,
    });
  }
  app._bashSpan = null;
  app._bashRunProcess?.kill(ProcessSignal.sigterm);
  app._bashRunProcess = null;
  // Mirror the agent-cancel contract: every transition back to idle also
  // stops the spinner, even if this particular path didn't start it.
  // Cheap insurance against future reorderings that begin with a spinner.
  app._stopSpinner();
  app._mode = AppMode.idle;
  app._blocks.add(_ConversationEntry.system('[bash command cancelled]'));
  app._render();
}

void _startBackgroundJobImpl(App app, String command) {
  unawaited(() async {
    try {
      await app._jobManager.start(command);
    } catch (e) {
      app._blocks.add(_ConversationEntry.error('Failed to start job: $e'));
      app._render();
    }
  }());
}

void _handleJobEventImpl(App app, JobEvent event) {
  switch (event) {
    case JobStarted(:final id, :final command):
      app._blocks
          .add(_ConversationEntry.system('↳ Started job #$id: $command'));
      app._render();
    case JobExited(:final id, :final exitCode):
      final job = app._jobManager.getJob(id);
      final cmd = job?.command ?? '?';
      final label = exitCode == 0 ? 'exited' : 'failed';
      app._blocks.add(
          _ConversationEntry.system('↳ Job #$id $label ($exitCode): $cmd'));
      app._render();
    case JobError(:final id, :final error):
      app._blocks.add(_ConversationEntry.system('↳ Job #$id error: $error'));
      app._render();
  }
}
