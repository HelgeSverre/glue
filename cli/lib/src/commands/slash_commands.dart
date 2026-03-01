/// A registered slash command.
class SlashCommand {
  final String name;
  final String description;
  final List<String> aliases;
  final List<String> hiddenAliases;
  final String Function(List<String> args) execute;

  const SlashCommand({
    required this.name,
    required this.description,
    this.aliases = const [],
    this.hiddenAliases = const [],
    required this.execute,
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

    SlashCommand? command;
    for (final c in _commands) {
      if (c.name == cmdName ||
          c.aliases.contains(cmdName) ||
          c.hiddenAliases.contains(cmdName)) {
        command = c;
        break;
      }
    }

    if (command == null) {
      return 'Unknown command: /$cmdName. Type /help for available commands.';
    }

    return command.execute(args);
  }

  /// All registered commands.
  List<SlashCommand> get commands => List.unmodifiable(_commands);
}
