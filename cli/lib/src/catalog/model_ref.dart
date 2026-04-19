/// A fully-qualified model identifier: `<provider-id>/<model-id>`.
///
/// The split is on the **first** slash only, so model ids that themselves
/// contain slashes round-trip correctly — e.g. a user-typed OpenRouter slug:
/// `openrouter/anthropic/claude-sonnet-4.6` → provider `openrouter`,
/// model `anthropic/claude-sonnet-4.6`.
library;

class ModelRef {
  const ModelRef({required this.providerId, required this.modelId});

  final String providerId;
  final String modelId;

  /// Parse a `provider/model` string. Throws [ModelRefParseException] if
  /// either side is empty or the separator is missing.
  static ModelRef parse(String input) {
    final slash = input.indexOf('/');
    if (slash <= 0) {
      throw ModelRefParseException(
        'expected "<provider>/<model>", got "$input"',
      );
    }
    final providerId = input.substring(0, slash);
    final modelId = input.substring(slash + 1);
    if (modelId.isEmpty) {
      throw ModelRefParseException(
        'model id is empty in "$input"',
      );
    }
    return ModelRef(providerId: providerId, modelId: modelId);
  }

  /// Non-throwing variant — returns null if [input] is malformed.
  static ModelRef? tryParse(String input) {
    try {
      return parse(input);
    } on ModelRefParseException {
      return null;
    }
  }

  @override
  String toString() => '$providerId/$modelId';

  @override
  bool operator ==(Object other) =>
      other is ModelRef &&
      other.providerId == providerId &&
      other.modelId == modelId;

  @override
  int get hashCode => Object.hash(providerId, modelId);
}

class ModelRefParseException implements Exception {
  ModelRefParseException(this.message);

  final String message;

  @override
  String toString() => 'ModelRefParseException: $message';
}
