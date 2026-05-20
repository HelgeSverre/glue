import 'dart:io';

import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/daytona/config.dart';
import 'package:glue_runtimes/src/daytona/runtime.dart';

/// Builds a [DaytonaConfig] from a `runtime_options` map and the
/// process environment. Used by the registration helper below; exposed
/// so tests can verify the parsing independently of the live API.
///
/// Region selection: set `api_base_url` (or `DAYTONA_API_BASE_URL`)
/// to `https://app-eu.daytona.io/api` for EU accounts. The toolbox
/// URL is always discovered per-sandbox from the create response, so
/// no toolbox config is needed unless you're routing through a proxy
/// (`toolbox_base_url` override).
DaytonaConfig daytonaConfigFromOptions(
  Map<String, Object?> options, {
  Map<String, String>? env,
}) {
  final e = env ?? Platform.environment;
  final apiKey = (options['api_key'] as String?) ?? e['DAYTONA_API_KEY'] ?? '';
  final apiBaseUrl = (options['api_base_url'] as String?) ??
      e['DAYTONA_API_BASE_URL'] ??
      'https://app.daytona.io/api';
  final toolboxOverride =
      (options['toolbox_base_url'] as String?) ?? e['DAYTONA_TOOLBOX_BASE_URL'];
  final snapshot = (options['snapshot'] as String?) ?? e['DAYTONA_SNAPSHOT'];
  return DaytonaConfig(
    apiKey: apiKey,
    apiBaseUrl: apiBaseUrl,
    toolboxBaseUrlOverride: toolboxOverride,
    snapshot: snapshot,
  );
}

/// Registers the Daytona adapter with [RuntimeFactory]. Call once at
/// startup before [ServiceLocator.create]:
///
/// ```dart
/// void main() async {
///   registerDaytonaRuntime();
///   await runGlue();
/// }
/// ```
void registerDaytonaRuntime() {
  RuntimeFactory.register(
    'daytona',
    ({required cwd, required options, eventSink}) async {
      final daytonaConfig = daytonaConfigFromOptions(options);
      // DaytonaRuntime implements RuntimeSession directly, so the
      // adapter just constructs and returns it.
      return DaytonaRuntime.start(
        config: daytonaConfig,
        hostCwd: cwd,
        eventSink: eventSink,
      );
    },
  );
}
