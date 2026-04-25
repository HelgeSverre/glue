import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/cli/runner.dart';
import 'package:glue/src/config/glue_config.dart';

void main(List<String> args) async {
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
