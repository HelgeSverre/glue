import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:cli_completion/parser.dart';
import 'package:glue/glue.dart';
import 'package:glue/src/commands/acp_command.dart';
import 'package:glue/src/commands/catalog_command.dart';
import 'package:glue/src/commands/completions_command.dart';
import 'package:glue/src/commands/config_command.dart';
import 'package:glue/src/commands/doctor_command.dart';
import 'package:glue/src/commands/mcp_command.dart';
import 'package:glue/src/commands/session_command.dart';
import 'package:glue/src/commands/setup_command.dart';
import 'package:glue/src/commands/trace_command.dart';
import 'package:glue/src/terminal/where_report.dart';
import 'package:glue_runtimes/daytona.dart';
import 'package:glue_runtimes/modal.dart';
import 'package:glue_runtimes/sprites.dart';

const appDescription = 'The coding agent that holds it all together.';

List<String> normalizeCliArgs(List<String> args) {
  final normalized = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--resume=')) {
      normalized.add('--resume-id=${arg.substring('--resume='.length)}');
      continue;
    }
    if (arg == '--resume' || arg == '-r') {
      final next = i + 1 < args.length ? args[i + 1] : null;
      if (next != null && !_looksLikeOption(next)) {
        normalized.add('--resume-id=$next');
        i++;
        continue;
      }
    }
    normalized.add(arg);
  }
  return normalized;
}

bool _looksLikeOption(String arg) => arg.startsWith('-');

void main(List<String> args) async {
  // Register cloud runtime adapters with RuntimeFactory before any
  // ServiceLocator.create() call. Each adapter package's registration
  // helper is a no-op when its runtime isn't selected, so listing them
  // here is safe regardless of config.
  registerDaytonaRuntime();
  registerModalRuntime();
  registerSpritesRuntime();

  final runner = GlueCommandRunner();
  try {
    final exitCode = await runner.run(normalizeCliArgs(args)) ?? 0;
    exit(exitCode);
  } on UsageException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln();
    stderr.writeln(e.usage);
    exit(64);
  } on ConfigError catch (e) {
    // Thrown from GlueConfig.load when --model / GLUE_MODEL / config.yaml
    // can't be resolved against the catalog. Surface the message cleanly;
    // suppress the Dart stack trace, which carries no user value here.
    stderr.writeln('Error: ${e.message}');
    exit(78); // EX_CONFIG
  } on ModelRefParseException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(78);
  }
}

class GlueCommandRunner extends CompletionCommandRunner<int> {
  GlueCommandRunner()
    : super(
        'glue',
        '\x1b[38;2;250;204;21m●\x1b[0m \x1b[1mglue\x1b[0m'
            ' v${AppConstants.version} — $appDescription',
      ) {
    argParser
      ..addFlag('version', abbr: 'v', negatable: false, help: 'Print version.')
      ..addFlag(
        'where',
        negatable: false,
        help:
            'Print the GLUE_HOME directory and resolved paths for config, '
            'credentials, sessions, logs, and cache.',
      )
      ..addFlag(
        'print',
        abbr: 'p',
        negatable: false,
        help: 'Print response to stdout without interactive mode.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Output session conversation as JSON (implies --print).',
      )
      ..addOption('model', abbr: 'm', help: 'LLM model to use.')
      ..addOption(
        'reasoning',
        allowed: ReasoningEffort.values.map((effort) => effort.name),
        help: 'Reasoning effort for supported models.',
      )
      ..addFlag(
        'resume',
        abbr: 'r',
        negatable: false,
        help:
            'Resume a session by ID/query, or open the resume panel when '
            'omitted.',
      )
      ..addOption('resume-id', hide: true)
      ..addFlag(
        'continue',
        negatable: false,
        help: 'Resume most recent session.',
      )
      ..addFlag(
        'debug',
        abbr: 'd',
        negatable: false,
        help: 'Enable debug mode (verbose logging).',
      );
    addCommand(CompletionsCommand());
    addCommand(CatalogCommand());
    addCommand(ConfigCommand());
    addCommand(DoctorCommand());
    addCommand(McpCommand());
    addCommand(AcpCommand());
    addCommand(SessionCommand());
    addCommand(SetupCommand());
    addCommand(TraceCommand());
  }

  @override
  String get invocation => '$executableName [options] [prompt]';

  @override
  bool get enableAutoInstall => false;

  @override
  void renderCompletionResult(CompletionResult completionResult) {
    final shell = systemShell;
    for (final entry in completionResult.completions.entries) {
      if (shell == SystemShell.zsh) {
        final suggestion = entry.key.replaceAll(':', r'\:');
        final description = entry.value?.replaceAll(':', r'\:');
        completionLogger.info(
          '$suggestion${description != null ? ':$description' : ''}',
        );
      } else {
        completionLogger.info(entry.key);
      }
    }
  }

  @override
  void printUsage() {
    stdout.writeln(usage);
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version')) {
      if (topLevelResults.flag('debug')) {
        stdout.writeln(BuildInfo.details(appVersion: AppConstants.version));
      } else {
        stdout.writeln('glue v${AppConstants.version} (${BuildInfo.summary})');
      }
      return 0;
    }

    if (topLevelResults.flag('where')) {
      _printWhere();
      return 0;
    }

    if (topLevelResults.command == null) {
      if (topLevelResults.flag('help')) {
        printUsage();
        return 0;
      }

      await _runApp(topLevelResults);
      return 0;
    }

    return super.runCommand(topLevelResults);
  }

  void _printWhere() {
    stdout.write(buildWhereReport(Environment.detect()));
  }

  Future<void> _runApp(ArgResults topLevelResults) async {
    final model = topLevelResults.option('model');
    final reasoning = topLevelResults.option('reasoning');
    final jsonMode = topLevelResults.flag('json');
    final printMode = topLevelResults.flag('print') || jsonMode;
    final resumeSessionId = topLevelResults.option('resume-id');
    final openResumePanel = topLevelResults.flag('resume');
    final debug = topLevelResults.flag('debug');

    if (debug && !jsonMode) {
      stderr.writeln('[glue] v${AppConstants.version} (${BuildInfo.summary})');
    }

    // Positional args form the prompt.
    final prompt = topLevelResults.rest.isNotEmpty
        ? topLevelResults.rest.join(' ')
        : null;

    final app = await App.create(
      model: model,
      reasoning: reasoning,
      prompt: prompt,
      printMode: printMode,
      jsonMode: jsonMode,
      resumeSessionId: openResumePanel ? '' : resumeSessionId,
      startupContinue: topLevelResults.flag('continue'),
      debug: debug,
    );

    // Print mode installs its own two-press SIGINT handler in
    // session_runtime.dart and never enters raw mode / the alt screen, so it
    // needs neither the interactive SIGINT handler nor the terminal-restore
    // guard below. (Installing the global SIGINT handler here would just be a
    // benign no-op that confuses the cancellation chain.)
    if (printMode) {
      await app.run();
      return;
    }

    await _runInteractive(app);
  }

  /// Runs the interactive TUI wrapped in a terminal-restore safety net (H6).
  ///
  /// The app's own `run()` `finally` restores the terminal, but it only
  /// executes for work awaited after the exit completer resolves. A
  /// synchronous throw in any fire-and-forget callback (terminal input, agent
  /// events, the spinner `Timer.periodic`, or `_render`'s `Future.delayed`)
  /// surfaces as an *unhandled async error* that would otherwise kill the
  /// isolate WITHOUT running that `finally` — stranding the user in raw mode
  /// with the alt screen, mouse capture, a hidden cursor, and a set scroll
  /// region still active. [runZonedGuarded] catches those and restores the TTY
  /// before exiting. SIGTERM/SIGHUP (which default to immediate termination)
  /// are routed to `requestExit()` so the normal `finally` restore runs.
  Future<void> _runInteractive(App app) async {
    void restoreTty() {
      try {
        app.terminal
          ..disableMouse()
          ..resetScrollRegion()
          ..showCursor()
          ..write('\x1b[0m')
          ..disableAltScreen()
          ..disableRawMode();
      } catch (_) {
        // Best-effort: never mask the original failure with a restore error.
      }
    }

    final signalSubs = <StreamSubscription<ProcessSignal>>[];
    // SIGINT keeps its existing behavior: request a clean exit, letting
    // run()'s finally restore the terminal.
    signalSubs.add(
      ProcessSignal.sigint.watch().listen((_) => app.requestExit()),
    );
    // SIGTERM / SIGHUP would otherwise terminate the process immediately,
    // skipping run()'s finally. Watch them where the platform allows and route
    // to the same clean-exit path. Windows can't watch these — guard each.
    for (final signal in const [ProcessSignal.sigterm, ProcessSignal.sighup]) {
      try {
        signalSubs.add(signal.watch().listen((_) => app.requestExit()));
      } catch (_) {
        // Signal not watchable on this platform; skip it.
      }
    }

    final done = Completer<void>();
    runZonedGuarded(
      () async {
        try {
          await app.run();
        } finally {
          if (!done.isCompleted) done.complete();
        }
      },
      (error, stack) {
        // An unhandled async error escaped a fire-and-forget callback; run()'s
        // finally may never run. Restore the terminal, report, and exit
        // non-zero so we never leave the user in a broken TTY.
        restoreTty();
        stderr.writeln('glue: fatal error: $error');
        stderr.writeln(stack);
        exit(70); // EX_SOFTWARE
      },
    );

    try {
      await done.future;
    } finally {
      for (final sub in signalSubs) {
        await sub.cancel();
      }
    }
  }
}
