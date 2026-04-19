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
typedef SlashArgCompleter = List<SlashArgCandidate> Function(
  List<String> priorArgs,
  String partial,
);

/// A registered slash command.
class SlashCommand {
  final String name;
  final String description;
  final List<String> aliases;
  final List<String> hiddenAliases;
  final String Function(List<String> args) execute;

  /// Optional arg-completer attached after registration via
  /// [SlashCommandRegistry.attachArgCompleter]. `null` means the command
  /// does not participate in argument autocomplete.
  SlashArgCompleter? completeArg;

  SlashCommand({
    required this.name,
    required this.description,
    this.aliases = const [],
    this.hiddenAliases = const [],
    required this.execute,
    this.completeArg,
  });
}

/// Registry of all slash commands.
class SlashCommandRegistry {
  final List<SlashCommand> _commands = [];

  void register(SlashCommand command) => _commands.add(command);

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

  /// Attach an argument completer to a previously-registered command.
  /// Resolves by primary name or any alias/hidden alias.
  /// Throws [StateError] if no command matches.
  void attachArgCompleter(String name, SlashArgCompleter completer) {
    final command = findByName(name);
    if (command == null) {
      throw StateError('No slash command registered for "$name"');
    }
    command.completeArg = completer;
  }
}
