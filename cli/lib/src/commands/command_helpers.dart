import 'dart:io';

import 'package:glue_harness/glue_harness.dart';

GlueConfig? safeLoadConfig() {
  try {
    return GlueConfig.load(environment: Environment.detect());
  } on ConfigError catch (e) {
    stderr.writeln('Failed to load config: ${e.message}');
    return null;
  }
}
