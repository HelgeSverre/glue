import 'dart:io';

import 'package:args/args.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:cli_completion/parser.dart';
import 'package:glue/src/boot/wire.dart';
import 'package:glue/src/cli/completions.dart';
import 'package:glue/src/cli/config.dart';
import 'package:glue/src/cli/doctor.dart';
import 'package:glue/src/config/build_info.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/core/where_report.dart';

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

class GlueCommandRunner extends CompletionCommandRunner<int> {
  GlueCommandRunner()
      : super(
          'glue',
          '\x1b[38;2;250;204;21m\u25cf\x1b[0m \x1b[1mglue\x1b[0m'
              ' v${AppConstants.version} — $appDescription',
        ) {
    argParser
      ..addFlag('version', abbr: 'v', negatable: false, help: 'Print version.')
      ..addFlag('where',
          negatable: false,
          help: 'Print the GLUE_HOME directory and resolved paths for config, '
              'credentials, sessions, logs, and cache.')
      ..addFlag('print',
          abbr: 'p',
          negatable: false,
          help: 'Print response to stdout without interactive mode.')
      ..addFlag('json',
          negatable: false,
          help: 'Output session conversation as JSON (implies --print).')
      ..addOption('model', abbr: 'm', help: 'LLM model to use.')
      ..addFlag(
        'resume',
        abbr: 'r',
        negatable: false,
        help: 'Resume a session by ID/query, or open the resume panel when '
            'omitted.',
      )
      ..addOption('resume-id', hide: true)
      ..addFlag('continue',
          negatable: false, help: 'Resume most recent session.')
      ..addFlag('debug',
          abbr: 'd',
          negatable: false,
          help: 'Enable debug mode (verbose logging).');
    addCommand(CompletionsCommand());
    addCommand(ConfigCommand());
    addCommand(DoctorCommand());
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
        stdout.writeln(
          'glue v${AppConstants.version} (${BuildInfo.summary})',
        );
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
    final jsonMode = topLevelResults.flag('json');
    final printMode = topLevelResults.flag('print') || jsonMode;
    final resumeSessionId = topLevelResults.option('resume-id');
    final openResumePanel = topLevelResults.flag('resume');
    final debug = topLevelResults.flag('debug');

    if (debug && !jsonMode) {
      stderr.writeln(
        '[glue] v${AppConstants.version} (${BuildInfo.summary})',
      );
    }

    // Positional args form the prompt.
    final prompt =
        topLevelResults.rest.isNotEmpty ? topLevelResults.rest.join(' ') : null;

    final app = await wireApp(
      model: model,
      prompt: prompt,
      printMode: printMode,
      jsonMode: jsonMode,
      resumeSessionId: openResumePanel ? '' : resumeSessionId,
      startupContinue: topLevelResults.flag('continue'),
      debug: debug,
    );
    await app.run();
  }
}
