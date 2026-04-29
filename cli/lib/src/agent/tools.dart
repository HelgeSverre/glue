import 'dart:async';
import 'dart:io';

import 'package:glue/src/_proposed_core/tool.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/shell/command_executor.dart';

// Re-export the abstract tool surface. The data types (Tool, ToolParameter,
// ToolResult, ToolTrust, ForwardingTool) now live in `_proposed_core/tool.dart`
// so strategies can depend on them without crossing the harness layer.
// Tool *implementations* (ReadFileTool, BashTool, …) stay in this file because
// they pull in I/O and runtime dependencies.
export 'package:glue/src/_proposed_core/tool.dart';

// ---------------------------------------------------------------------------
// Built-in tools
// ---------------------------------------------------------------------------

/// A tool that reads file contents from disk.
class ReadFileTool extends Tool {
  @override
  String get name => 'read_file';

  @override
  String get description => 'Read the contents of a file at the given path.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'path',
          type: 'string',
          description: 'Absolute or relative path to the file.',
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) {
      return ToolResult(
        success: false,
        content: 'Error: no path provided',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      return ToolResult(
        success: false,
        content: 'Error: file not found: $path',
        metadata: {'path': path},
      );
    }
    final stat = await file.stat();
    if (stat.size > 1024 * 1024) {
      return ToolResult(
        success: false,
        content: 'Error: file too large (${stat.size} bytes, max 1MB): $path',
        metadata: {'path': path, 'bytes': stat.size},
      );
    }
    final text = await file.readAsString();
    final lineCount = _countLines(text);
    return ToolResult(
      content: text,
      summary: 'Read $path ($lineCount lines, ${stat.size} bytes)',
      metadata: {
        'path': path,
        'bytes': stat.size,
        'line_count': lineCount,
      },
    );
  }
}

/// Counts newlines + 1 for a trailing non-newline-terminated line.
/// Returns 0 for an empty string.
int _countLines(String s) {
  if (s.isEmpty) return 0;
  final newlines = '\n'.allMatches(s).length;
  return s.endsWith('\n') ? newlines : newlines + 1;
}

/// A tool that writes content to a file on disk.
class WriteFileTool extends Tool {
  @override
  String get name => 'write_file';

  @override
  ToolTrust get trust => ToolTrust.fileEdit;

  @override
  String get description =>
      'Write content to a file, creating it if it does not exist.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'path',
          type: 'string',
          description: 'Absolute or relative path to the file.',
        ),
        ToolParameter(
          name: 'content',
          type: 'string',
          description: 'The content to write.',
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    final content = args['content'];
    if (path is! String || path.isEmpty) {
      return ToolResult(
        success: false,
        content: 'Error: no path provided',
      );
    }
    if (content is! String) {
      return ToolResult(
        success: false,
        content: 'Error: no content provided',
      );
    }
    final file = File(path);
    final isNew = !await file.exists();
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    final lineCount = _countLines(content);
    return ToolResult(
      content: 'Wrote ${content.length} bytes to $path',
      summary: isNew
          ? 'Created $path ($lineCount lines)'
          : 'Wrote $path ($lineCount lines)',
      metadata: {
        'path': path,
        'bytes': content.length,
        'line_count': lineCount,
        'is_new_file': isNew,
      },
    );
  }
}

/// A tool that runs shell commands and returns their output.
class BashTool extends Tool {
  final CommandExecutor executor;

  BashTool(this.executor);

  @override
  String get name => 'bash';

  @override
  ToolTrust get trust => ToolTrust.command;

  @override
  String get description => 'Run a shell command and return stdout/stderr.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'command',
          type: 'string',
          description: 'The shell command to execute.',
        ),
        ToolParameter(
          name: 'timeout_seconds',
          type: 'integer',
          description:
              'Timeout in seconds. 0 for no timeout. Default: ${AppConstants.bashTimeoutSeconds}.',
          required: false,
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final command = args['command'];
    if (command is! String || command.isEmpty) {
      return ToolResult(
        success: false,
        content: 'Error: no command provided',
      );
    }
    final t = args['timeout_seconds'];
    final timeoutSeconds =
        (t is num) ? t.toInt() : AppConstants.bashTimeoutSeconds;
    final timeout =
        timeoutSeconds == 0 ? null : Duration(seconds: timeoutSeconds);

    final result = await executor.runCapture(command, timeout: timeout);

    if (result.exitCode == -1 && timeout != null) {
      return ToolResult(
        success: false,
        content: 'Error: command timed out after $timeoutSeconds seconds',
        summary: 'bash: timed out',
        metadata: {
          'command': command,
          'timeout_seconds': timeoutSeconds,
          'timed_out': true,
        },
      );
    }

    final buf = StringBuffer();
    if (result.stdout.isNotEmpty) buf.writeln(result.stdout);
    if (result.stderr.isNotEmpty) buf.writeln('STDERR: ${result.stderr}');
    buf.writeln('Exit code: ${result.exitCode}');
    return ToolResult(
      success: result.exitCode == 0,
      content: buf.toString(),
      summary: 'bash: ${_snippet(command)} (exit ${result.exitCode})',
      metadata: {
        'command': command,
        'exit_code': result.exitCode,
        'stdout_bytes': result.stdout.length,
        'stderr_bytes': result.stderr.length,
      },
    );
  }
}

String _snippet(String s, {int max = 40}) {
  final oneLine = s.replaceAll('\n', ' ');
  return oneLine.length <= max ? oneLine : '${oneLine.substring(0, max)}…';
}

/// A tool that searches for patterns in files using ripgrep-style semantics.
class GrepTool extends Tool {
  @override
  String get name => 'grep';

  @override
  String get description =>
      'Search for a regex pattern in files under a directory.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'pattern',
          type: 'string',
          description: 'Regex pattern to search for.',
        ),
        ToolParameter(
          name: 'path',
          type: 'string',
          description: 'Directory to search in.',
          required: false,
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final pattern = args['pattern'];
    if (pattern is! String || pattern.isEmpty) {
      return ToolResult(
        success: false,
        content: 'Error: no pattern provided',
      );
    }
    final path = args['path'];
    final dir = (path is String && path.isNotEmpty) ? path : '.';

    // Try ripgrep first, fall back to grep.
    final executable = await _which('rg') != null ? 'rg' : 'grep';

    final arguments = executable == 'rg'
        ? ['--line-number', '--no-heading', pattern, dir]
        : ['-rn', pattern, dir];

    try {
      final result = await Process.run(executable, arguments)
          .timeout(const Duration(seconds: AppConstants.grepTimeoutSeconds));
      final output = result.stdout as String;
      if (output.isEmpty) {
        return ToolResult(
          content: 'No matches found.',
          summary: 'grep "$pattern": 0 matches',
          metadata: {
            'pattern': pattern,
            'path': dir,
            'match_count': 0,
          },
        );
      }
      final matchCount =
          '\n'.allMatches(output).length + (output.endsWith('\n') ? 0 : 1);
      return ToolResult(
        content: output,
        summary:
            'grep "$pattern": $matchCount match${matchCount == 1 ? '' : 'es'}',
        metadata: {
          'pattern': pattern,
          'path': dir,
          'match_count': matchCount,
        },
      );
    } on TimeoutException {
      return ToolResult(
        success: false,
        content:
            'Error: grep timed out after ${AppConstants.grepTimeoutSeconds} seconds',
        summary: 'grep: timed out',
        metadata: {
          'pattern': pattern,
          'path': dir,
          'timed_out': true,
        },
      );
    }
  }

  Future<String?> _which(String cmd) async {
    try {
      final result = await Process.run('which', [cmd]);
      return result.exitCode == 0 ? (result.stdout as String).trim() : null;
    } catch (_) {
      return null;
    }
  }
}

/// A tool that edits files by replacing exact string matches.
class EditFileTool extends Tool {
  @override
  String get name => 'edit_file';

  @override
  ToolTrust get trust => ToolTrust.fileEdit;

  @override
  String get description =>
      'Edit a file by replacing an exact match of old_string with new_string. '
      'old_string must match exactly one location in the file (include enough '
      'context lines to be unambiguous). If old_string is empty, creates the '
      'file with new_string as content. Supports multi-line strings.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'path',
          type: 'string',
          description: 'Absolute or relative path to the file.',
        ),
        ToolParameter(
          name: 'old_string',
          type: 'string',
          description: 'The exact text to find (multi-line supported). '
              'Must be unique in the file. Empty string to create a new file.',
        ),
        ToolParameter(
          name: 'new_string',
          type: 'string',
          description: 'The replacement text (multi-line supported). '
              'Empty string to delete the matched text.',
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) {
      return ToolResult(
        success: false,
        content: 'Error: no path provided',
      );
    }
    final oldString = args['old_string'] as String? ?? '';
    final newString = args['new_string'] as String? ?? '';

    final file = File(path);

    if (oldString.isEmpty) {
      await file.parent.create(recursive: true);
      await file.writeAsString(newString);
      final newLines = _countLines(newString);
      return ToolResult(
        content: 'Created ${file.path} (${newString.length} bytes)',
        summary: 'Created $path ($newLines lines)',
        metadata: {
          'path': path,
          'bytes': newString.length,
          'old_lines': 0,
          'new_lines': newLines,
          'is_new_file': true,
        },
      );
    }

    if (!await file.exists()) {
      return ToolResult(
        success: false,
        content: 'Error: file not found: $path',
        metadata: {'path': path},
      );
    }

    final content = await file.readAsString();

    final firstIndex = content.indexOf(oldString);
    if (firstIndex == -1) {
      return ToolResult(
        success: false,
        content: 'Error: old_string not found in $path. '
            'Make sure it matches the file content exactly, '
            'including whitespace and indentation.',
        metadata: {'path': path},
      );
    }

    final lastIndex = content.lastIndexOf(oldString);
    if (firstIndex != lastIndex) {
      return ToolResult(
        success: false,
        content: 'Error: old_string appears multiple times in $path. '
            'Include more surrounding context lines to make the match unique.',
        metadata: {'path': path},
      );
    }

    final newContent = content.substring(0, firstIndex) +
        newString +
        content.substring(firstIndex + oldString.length);

    await file.writeAsString(newContent);

    final oldLines = oldString.split('\n').length;
    final newLines = newString.split('\n').length;
    return ToolResult(
      content:
          'Applied edit to $path: replaced $oldLines line(s) with $newLines line(s)',
      summary: 'Edited $path ($oldLines→$newLines lines)',
      metadata: {
        'path': path,
        'old_lines': oldLines,
        'new_lines': newLines,
        'is_new_file': false,
      },
    );
  }
}

/// A tool that lists directory contents.
class ListDirectoryTool extends Tool {
  @override
  String get name => 'list_directory';

  @override
  String get description => 'List the contents of a directory.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'path',
          type: 'string',
          description: 'Path to the directory.',
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) {
      return ToolResult(
        success: false,
        content: 'Error: no path provided',
      );
    }
    final dir = Directory(path);
    if (!await dir.exists()) {
      return ToolResult(
        success: false,
        content: 'Error: directory not found: $path',
        metadata: {'path': path},
      );
    }
    final entries = await dir.list().take(AppConstants.globMaxEntries).toList();
    final buf = StringBuffer();
    for (final entry in entries) {
      final suffix = entry is Directory ? '/' : '';
      buf.writeln('${entry.path}$suffix');
    }
    final capped = entries.length == AppConstants.globMaxEntries;
    if (capped) {
      buf.writeln('(output capped at ${AppConstants.globMaxEntries} entries)');
    }
    return ToolResult(
      content: buf.toString(),
      summary: '$path: ${entries.length}'
          '${capped ? "+" : ""} '
          'entr${entries.length == 1 ? "y" : "ies"}',
      metadata: {
        'path': path,
        'entry_count': entries.length,
        'capped': capped,
      },
    );
  }
}
