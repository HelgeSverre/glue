/// Represents a context-window overflow error from any LLM provider.
///
/// Thrown (or classified) when the provider rejects the request because
/// the prompt exceeds its context limit.
///
/// {@category Context}
class ContextOverflowException implements Exception {
  final String provider;
  final String rawMessage;
  final int? estimatedTokens;
  final int? contextLimit;

  const ContextOverflowException({
    required this.provider,
    required this.rawMessage,
    this.estimatedTokens,
    this.contextLimit,
  });

  @override
  String toString() =>
      'ContextOverflowException($provider): context window exceeded. '
      '$rawMessage';
}

/// Classifies raw LLM provider errors as context-overflow errors.
///
/// Checks the error message for provider-specific patterns from Anthropic,
/// OpenAI, and Ollama.
///
/// {@category Context}
class OverflowClassifier {
  const OverflowClassifier._();

  /// Returns a [ContextOverflowException] when [error] looks like a context
  /// overflow, or `null` for any other error type.
  static ContextOverflowException? classify(Object error) {
    final msg = error.toString().toLowerCase();

    final isOverflow = (msg.contains('context') &&
            (msg.contains('length') ||
                msg.contains('exceeded') ||
                msg.contains('window'))) ||
        msg.contains('too long') ||
        msg.contains('too many tokens') ||
        msg.contains('prompt is too long') ||
        // Ollama truncation signal
        msg.contains('context length exceeded');

    if (!isOverflow) return null;

    return ContextOverflowException(
      provider: _guessProvider(msg),
      rawMessage: error.toString(),
    );
  }

  static String _guessProvider(String msg) {
    if (msg.contains('anthropic')) return 'anthropic';
    if (msg.contains('openai')) return 'openai';
    if (msg.contains('ollama')) return 'ollama';
    return 'unknown';
  }
}
