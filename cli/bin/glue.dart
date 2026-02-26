import 'dart:io';

import 'package:args/args.dart';
import 'package:glue/glue.dart';

const version = '0.1.0';

const logo = '''
        .__
   ____ |  |  __ __   ____
  / ___\\|  | |  |  \\_/ __ \\
 / /_/  >  |_|  |  /\\  ___/
 \\___  /|____/____/  \\___  >
/_____/                  \\/''';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage information.')
    ..addFlag('version', abbr: 'v', negatable: false, help: 'Print version.')
    ..addOption('provider', abbr: 'p', help: 'LLM provider (anthropic, openai, ollama).')
    ..addOption('model', abbr: 'm', help: 'LLM model to use.');

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Usage: glue [options]');
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (results.flag('help')) {
    stdout.writeln(logo);
    stdout.writeln();
    stdout.writeln('glue v$version — the coding agent that holds it all together.');
    stdout.writeln();
    stdout.writeln('Usage: glue [options]');
    stdout.writeln();
    stdout.writeln(parser.usage);
    return;
  }

  if (results.flag('version')) {
    stdout.writeln('glue v$version');
    return;
  }

  final provider = results.option('provider');
  final model = results.option('model');

  final app = App.create(provider: provider, model: model);

  final sigintSub = ProcessSignal.sigint.watch().listen((_) => app.requestExit());

  await app.run();

  await sigintSub.cancel();
  exit(0);
}
