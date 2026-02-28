/// Application-wide configuration constants.
///
/// Centralizes magic values for timeouts, limits, and defaults to improve
/// maintainability and enable easy tuning of behavior.
class AppConstants {
  // App behavior
  static const int maxConversationBlocks = 200;
  static const Duration ctrlCDoubleTapWindow = Duration(seconds: 2);

  // Tool timeouts
  static const int bashTimeoutSeconds = 30;
  static const int grepTimeoutSeconds = 15;

  // LLM configuration
  static const String defaultOllamaBaseUrl = 'http://localhost:11434';

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

  // Web tool configuration
  static const int webFetchTimeoutSeconds = 30;
  static const int webFetchMaxBytes = 5 * 1024 * 1024; // 5MB
  static const int webFetchDefaultMaxTokens = 50000;
  static const int webSearchTimeoutSeconds = 15;
  static const int webSearchDefaultMaxResults = 5;

  AppConstants._(); // Prevent instantiation
}
