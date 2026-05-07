/// Shared tool permission presets used by interactive sessions and subagents.
class ToolPermissions {
  ToolPermissions._();

  /// Read-only tools that are safe to auto-allow for subagents.
  ///
  /// Includes web fetch/search/browser: these are external reads with no
  /// local side effects, and a subagent that can't pull a URL or hit a
  /// search engine can't meaningfully decompose research tasks. Spawn
  /// tools are intentionally omitted here and added by [AgentManager]
  /// per depth, so recursion stays bounded.
  static const Set<String> subagentSafeTools = {
    'read_file',
    'list_directory',
    'grep',
    'web_fetch',
    'web_search',
    'web_browser',
  };

  /// Interactive session defaults for trusted tools.
  static const Set<String> defaultTrustedTools = {
    ...subagentSafeTools,
    'spawn_subagent',
    'spawn_parallel_subagents',
    'skill',
  };
}
