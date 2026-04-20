import 'package:glue/src/config/version_generated.dart';

/// Application-wide configuration constants.
///
/// Centralizes magic values for timeouts, limits, and defaults to improve
/// maintainability and enable easy tuning of behavior.
class AppConstants {
  /// Package version — sourced from `pubspec.yaml` via
  /// `tool/gen_version.dart`. Do not edit by hand; bump `pubspec.yaml`
  /// and run `just gen` (or `just release <version>`).
  static const String version = packageVersion;

  // App behavior
  static const int maxConversationBlocks = 200;
  static const Duration ctrlCDoubleTapWindow = Duration(seconds: 2);

  // Tool timeouts
  static const int bashTimeoutSeconds = 30;
  static const int grepTimeoutSeconds = 15;
  static const int shellCompletionTimeoutMs = 2000;

  // LLM configuration
  static const String defaultOllamaBaseUrl = 'http://localhost:11434';
  static const String defaultTitleModel = 'claude-haiku-4-5-20251001';

  // UI limits
  static const int maxVisibleDropdownItems = 8;
  static const int atFileHintCacheTtlSeconds = 2;
  static const int atFileHintMaxTreeEntries = 2000;
  static const int atFileHintMaxTreeDepth = 3;

  // Agent configuration
  static const int maxSubagentDepth = 2;
  static const int bashMaxLinesDefault = 50;

  // Tool limits
  static const int globMaxEntries = 1000;
  static const int maxFileExpansionBytes = 100 * 1024;
  static const int debugLogBodySizeLimit = 1000;

  // Terminal/Layout
  static const int inputAreaDivisor = 3; // Input area = terminal.rows ~/ 3
  static const int maxInputVisibleLines = 10;

  // Web tool configuration
  static const int webFetchTimeoutSeconds = 30;
  static const int webFetchMaxBytes = 5 * 1024 * 1024; // 5MB
  static const int webFetchDefaultMaxTokens = 50000;
  static const int webSearchTimeoutSeconds = 15;
  static const int webSearchDefaultMaxResults = 5;

  // PDF extraction configuration
  static const int pdfMaxBytes = 20 * 1024 * 1024; // 20MB
  static const int pdfTimeoutSeconds = 60;

  // Browser tool configuration
  static const int browserNavigationTimeoutSeconds = 30;
  static const int browserActionTimeoutSeconds = 10;
  static const int browserDockerPort = 3000;
  static const String browserDockerImage = 'browserless/chrome:latest';

  AppConstants._(); // Prevent instantiation
}
