/// A candidate produced by a command's argument completer.
class SlashArgCandidate {
  final String value;
  final String description;

  /// When true, `SlashAutocomplete.accept()` appends a trailing space
  /// so the user can keep typing further args. Use for subcommands
  /// that expect another token (e.g. `/provider add ` → await ID).
  final bool continues;

  const SlashArgCandidate({
    required this.value,
    this.description = '',
    this.continues = false,
  });
}

/// Produces candidates for the argument token currently under the cursor.
///
/// [priorArgs] holds the complete arg tokens typed before the one being
/// completed. [partial] is the lowercased partial text of the token under
/// the cursor (empty string when the buffer ends with a space).
typedef SlashArgCompleter =
    List<SlashArgCandidate> Function(List<String> priorArgs, String partial);

/// Base type for a registered slash command.
///
/// Class-based commands (those owning their domain logic) extend this and
/// override `name`, `description`, `execute`, and optionally `aliases`,
/// `hiddenAliases`, `argCompleter`. Legacy inline registrations use
/// [SlashCommand.inline] to construct an anonymous subclass.
abstract class SlashCommand {
  String get name;
  String get description;
  List<String> get aliases => const [];
  List<String> get hiddenAliases => const [];

  /// Returns inline output. `''` for async paths (the command later posts
  /// results via `ctx.conversation.notify`).
  String execute(List<String> args);

  /// Optional argument autocomplete. Override to expose suggestions; default
  /// returns no completions.
  SlashArgCompleter? get argCompleter => null;

  SlashCommand();

  /// Convenience constructor for legacy registrations that don't yet have a
  /// dedicated class. Prefer subclassing for new commands.
  factory SlashCommand.inline({
    required String name,
    required String description,
    List<String> aliases,
    List<String> hiddenAliases,
    required String Function(List<String> args) execute,
    SlashArgCompleter? argCompleter,
  }) = _InlineSlashCommand;
}

class _InlineSlashCommand extends SlashCommand {
  @override
  final String name;
  @override
  final String description;
  @override
  final List<String> aliases;
  @override
  final List<String> hiddenAliases;
  final String Function(List<String> args) _execute;
  @override
  final SlashArgCompleter? argCompleter;

  _InlineSlashCommand({
    required this.name,
    required this.description,
    this.aliases = const [],
    this.hiddenAliases = const [],
    required this._execute,
    this.argCompleter,
  });

  @override
  String execute(List<String> args) => _execute(args);
}

/// Registry of all slash commands.
class SlashCommandRegistry {
  final List<SlashCommand> _commands = [];

  void register(SlashCommand command) => _commands.add(command);

  void registerAll(Iterable<SlashCommand> commands) =>
      _commands.addAll(commands);

  /// Parse and execute a slash command string.
  /// Returns the output text, or null if not found.
  String? execute(String input) {
    final parts = input.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || !parts[0].startsWith('/')) return null;

    final cmdName = parts[0].substring(1).toLowerCase();
    final args = parts.sublist(1);

    final command = findByName(cmdName);
    if (command == null) {
      return 'Unknown command: /$cmdName. Type /help for available commands.';
    }

    return command.execute(args);
  }

  /// All registered commands.
  List<SlashCommand> get commands => List.unmodifiable(_commands);

  /// Find a command by its primary name or any alias/hidden alias.
  /// Matching is case-insensitive.
  SlashCommand? findByName(String name) {
    final needle = name.toLowerCase();
    for (final c in _commands) {
      if (c.name == needle ||
          c.aliases.contains(needle) ||
          c.hiddenAliases.contains(needle)) {
        return c;
      }
    }
    return null;
  }
}
