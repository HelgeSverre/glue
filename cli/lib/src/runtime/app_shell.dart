import 'dart:async';
import 'dart:io';

import 'package:glue/src/app.dart';
import 'package:glue/src/runtime/app_launch_options.dart';

/// Lifecycle shell for the interactive and print runtimes.
///
/// The shell owns process-level concerns such as signal handling and launch
/// options. The current UI runtime still lives in [App], but [AppShell] is the
/// new entrypoint that future runtime modules hang off.
class AppShell {
  AppShell._(this.runtime, this.options);

  final App runtime;
  final AppLaunchOptions options;

  static Future<AppShell> create({
    String? model,
    String? prompt,
    bool printMode = false,
    bool jsonMode = false,
    String? resumeSessionId,
    bool startupContinue = false,
    bool debug = false,
  }) async {
    final options = AppLaunchOptions(
      model: model,
      prompt: prompt,
      printMode: printMode,
      jsonMode: jsonMode,
      resumeSessionId: resumeSessionId,
      startupContinue: startupContinue,
      debug: debug,
    );

    final runtime = await App.create(
      model: options.model,
      prompt: options.prompt,
      printMode: options.printMode,
      jsonMode: options.jsonMode,
      resumeSessionId: options.resumeSessionId,
      startupContinue: options.startupContinue,
      debug: options.debug,
    );
    return AppShell._(runtime, options);
  }

  Future<void> run() async {
    final sigintSub =
        ProcessSignal.sigint.watch().listen((_) => runtime.requestExit());
    try {
      await runtime.run();
    } finally {
      await sigintSub.cancel();
    }
  }

  void requestExit() => runtime.requestExit();
}
