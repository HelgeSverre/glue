import 'package:glue/src/conversation/entry.dart';

/// Read/write surface over the on-screen conversation transcript.
///
/// App owns the underlying storage (`_blocks` list, `_streamingText`,
/// `_streamingThinking`, the terminal). The view holds references and
/// callbacks so commands and other consumers can interact with the transcript
/// without reaching into App.
class ConversationView {
  ConversationView({
    required List<ConversationEntry> blocks,
    required String Function() streamingTextGetter,
    required void Function() render,
    required void Function() resetStreamingText,
    required void Function() clearScreen,
    required void Function() resetScrollOffset,
  })  : _blocks = blocks,
        _streamingTextGetter = streamingTextGetter,
        _render = render,
        _resetStreamingText = resetStreamingText,
        _clearScreen = clearScreen,
        _resetScrollOffset = resetScrollOffset;

  final List<ConversationEntry> _blocks;
  final String Function() _streamingTextGetter;
  final void Function() _render;
  final void Function() _resetStreamingText;
  final void Function() _clearScreen;
  final void Function() _resetScrollOffset;

  /// Read-only iterable of currently rendered transcript entries.
  Iterable<ConversationEntry> get entries => List.unmodifiable(_blocks);

  /// In-flight streaming assistant text (empty when no stream is active).
  String get streamingText => _streamingTextGetter();

  /// Returns the most recent assistant text the user can see, including the
  /// in-flight streaming response if any. Returns null if no assistant
  /// content has appeared yet.
  String? lastAssistantText({bool includeStreaming = true}) {
    if (includeStreaming) {
      final partial = _streamingTextGetter();
      if (partial.isNotEmpty) return partial;
    }
    for (var i = _blocks.length - 1; i >= 0; i--) {
      final entry = _blocks[i];
      if (entry.kind == EntryKind.assistant && entry.text.isNotEmpty) {
        return entry.text;
      }
    }
    return null;
  }

  /// Adds a system message and re-renders.
  void notify(String message) {
    _blocks.add(ConversationEntry.system(message));
    _render();
  }

  /// Trigger a re-render without mutating the transcript. Used by panels
  /// that want to refresh their display while polling external state
  /// (e.g., the `/provider add` device-code flow's countdown).
  void render() => _render();

  /// Append an entry to the rendered transcript and re-render. Used when a
  /// command needs to inject something other than a system message
  /// (e.g., tool calls / tool results from skill activation).
  void addEntry(ConversationEntry entry) {
    _blocks.add(entry);
    _render();
  }

  /// Clears the transcript: blocks, in-flight streaming text, screen state.
  /// Used by `/clear`.
  void clear() {
    _blocks.clear();
    _resetStreamingText();
    _resetScrollOffset();
    _clearScreen();
    _render();
  }
}
