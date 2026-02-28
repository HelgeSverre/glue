import 'dart:io';

import '../config/constants.dart';

/// The type of shell detected on the system.
enum ShellType { bash, fish, zsh, sh }

/// A single completion candidate from the shell.
class ShellCandidate {
  final String text;
  final String? description;
  final bool isDirectory;
  ShellCandidate(this.text, {this.description, this.isDirectory = false});
}

/// Spawns shell subprocesses to produce tab-completion candidates.
///
/// Uses `compgen` for bash/zsh/sh and `complete -C` for fish.
/// Results are cached with a short TTL to avoid repeated subprocess spawns.
class ShellCompleter {
  final ShellType shellType;

  // Cache
  String _cachedKey = '';
  List<ShellCandidate> _cachedResults = [];
  DateTime _cachedAt = DateTime(0);

  static const _maxResults = 50;

  ShellCompleter({ShellType? shellType})
      : shellType = shellType ?? _detectShell();

  /// Detect the user's shell from $SHELL.
  static ShellType _detectShell() {
    final shell = Platform.environment['SHELL'] ?? '';
    if (shell.isEmpty) return ShellType.sh;
    final base = shell.split('/').last;
    return switch (base) {
      'bash' => ShellType.bash,
      'fish' => ShellType.fish,
      'zsh' => ShellType.zsh,
      _ => ShellType.sh,
    };
  }

  /// Extract the start position of the completable token.
  ///
  /// Given "git checkout --fo", returns the index of "--fo" (15).
  /// Given "ls", returns 0. Given "cat ", returns 4 (empty token at end).
  int tokenStart(String buffer) {
    if (buffer.isEmpty) return 0;
    final lastSpace = buffer.lastIndexOf(' ');
    return lastSpace == -1 ? 0 : lastSpace + 1;
  }

  /// Get completions for the given command line buffer.
  Future<List<ShellCandidate>> complete(String buffer) async {
    if (buffer.isEmpty) return [];

    // Check cache.
    final now = DateTime.now();
    if (buffer == _cachedKey &&
        now.difference(_cachedAt).inSeconds <
            AppConstants.atFileHintCacheTtlSeconds) {
      return _cachedResults;
    }

    final start = tokenStart(buffer);
    final token = buffer.substring(start);
    final isFirstWord = !buffer.substring(0, start).contains(' ') && start == 0;

    List<ShellCandidate> candidates;
    if (shellType == ShellType.fish) {
      candidates = await _completeFish(buffer);
    } else {
      candidates = await _completeBash(token, isFirstWord);
    }

    // Cap results.
    if (candidates.length > _maxResults) {
      candidates = candidates.sublist(0, _maxResults);
    }

    // Cache.
    _cachedKey = buffer;
    _cachedResults = candidates;
    _cachedAt = now;

    return candidates;
  }

  Future<List<ShellCandidate>> _completeBash(
      String token, bool isFirstWord) async {
    if (isFirstWord) {
      // Command completion.
      final lines = await _runShellCommand(
          'bash', ['-c', 'compgen -c -- ${_shellEscape(token)}']);
      return lines.map((l) => ShellCandidate(l)).toList();
    }

    // File completion — also get directory list to mark dirs.
    final fileFuture = _runShellCommand(
        'bash', ['-c', 'compgen -f -- ${_shellEscape(token)}']);
    final dirFuture = _runShellCommand(
        'bash', ['-c', 'compgen -d -- ${_shellEscape(token)}']);

    final files = await fileFuture;
    final dirs = (await dirFuture).toSet();

    return files
        .map((f) => ShellCandidate(f, isDirectory: dirs.contains(f)))
        .toList();
  }

  Future<List<ShellCandidate>> _completeFish(String buffer) async {
    final lines = await _runShellCommand(
        'fish', ['-c', 'complete -C ${_shellEscape(buffer)}']);
    return lines.map((line) {
      // fish output is tab-separated: "candidate\tdescription"
      final parts = line.split('\t');
      final text = parts[0];
      final desc = parts.length > 1 ? parts[1] : null;
      return ShellCandidate(text, description: desc);
    }).toList();
  }

  /// Run a shell command and return stdout lines, with timeout.
  Future<List<String>> _runShellCommand(
      String executable, List<String> args) async {
    try {
      final result = await Process.run(executable, args,
              environment: {'LC_ALL': 'C'}, runInShell: false)
          .timeout(
        Duration(milliseconds: AppConstants.shellCompletionTimeoutMs),
      );
      if (result.exitCode != 0) return [];
      final output = (result.stdout as String).trim();
      if (output.isEmpty) return [];
      return output.split('\n').where((l) => l.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Shell-escape a string for safe embedding in a shell command.
  static String _shellEscape(String s) {
    if (s.isEmpty) return "''";
    // Use single quotes, escaping any existing single quotes.
    return "'${s.replaceAll("'", "'\\''")}'";
  }
}
