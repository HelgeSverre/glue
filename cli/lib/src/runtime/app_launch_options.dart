class AppLaunchOptions {
  const AppLaunchOptions({
    this.model,
    this.prompt,
    this.printMode = false,
    this.jsonMode = false,
    this.resumeSessionId,
    this.startupContinue = false,
    this.debug = false,
  });

  final String? model;
  final String? prompt;
  final bool printMode;
  final bool jsonMode;
  final String? resumeSessionId;
  final bool startupContinue;
  final bool debug;
}
