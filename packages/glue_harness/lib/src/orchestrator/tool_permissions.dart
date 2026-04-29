/// Shared tool permission presets used by interactive sessions and subagents.
class ToolPermissions {
  ToolPermissions._();

  /// Read-only tools that are safe to auto-allow for subagents.
  static const Set<String> subagentSafeTools = {
    'read_file',
    'list_directory',
    'grep',
  };

  /// Interactive session defaults for trusted tools.
  static const Set<String> defaultTrustedTools = {
    ...subagentSafeTools,
    'spawn_subagent',
    'spawn_parallel_subagents',
    'web_fetch',
    'web_search',
    'web_browser',
    'skill',
  };
}
