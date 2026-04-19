/// Compatibility profiles capture per-vendor quirks around an otherwise
/// OpenAI-shaped Chat Completions API.
///
/// The profile lives on [ProviderDef.compatibility]; when omitted, callers
/// default to [CompatibilityProfile.openai] (vanilla). Each variant mutates
/// a request body and/or headers just enough to keep the common 90% working.
library;

enum CompatibilityProfile {
  openai,
  groq,
  ollama,
  openrouter,
  vllm,
  mistral;

  /// Parse the catalog's `compatibility:` string. Unknown / null → [openai].
  static CompatibilityProfile fromString(String? id) => switch (id) {
        'groq' => groq,
        'ollama' => ollama,
        'openrouter' => openrouter,
        'vllm' => vllm,
        'mistral' => mistral,
        _ => openai,
      };

  /// Auth header to attach. Ollama (and other auth-less local gateways) omits
  /// the header entirely — returning an empty map means "do not set".
  Map<String, String> authHeaders(String apiKey) => switch (this) {
        ollama => const {},
        _ => {'Authorization': 'Bearer $apiKey'},
      };

  /// Whether this endpoint supports `stream_options.include_usage`. When
  /// false, the body field is stripped to avoid 400 responses.
  bool get supportsStreamOptionsUsage => switch (this) {
        groq || ollama || vllm => false,
        openai || openrouter || mistral => true,
      };

  /// Strip / adjust body fields that specific endpoints reject.
  void mutateBody(Map<String, dynamic> body) {
    if (!supportsStreamOptionsUsage) {
      body.remove('stream_options');
    }
    if (this == vllm && body['tool_choice'] == null) {
      // vLLM rejects explicit `null` on tool_choice.
      body.remove('tool_choice');
    }
  }
}
