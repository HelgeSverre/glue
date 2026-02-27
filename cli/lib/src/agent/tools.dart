import 'dart:async';
import 'dart:io';
import '../config/constants.dart';

/// Schema for a single tool parameter.
class ToolParameter {
  final String name;
  final String type;
  final String description;
  final bool required;

  const ToolParameter({
    required this.name,
    required this.type,
    required this.description,
    this.required = true,
  });

  Map<String, dynamic> toSchema() => {
        'type': type,
        'description': description,
      };
}

/// Base class for all tools available to the agent.
///
/// Each tool declares its [name], [description], and [parameters] so the
/// LLM can decide when and how to invoke it. The [execute] method
/// performs the actual work and returns a string result.
abstract class Tool {
  /// Machine-readable tool name (e.g. `read_file`).
  String get name;

  /// Human-readable description shown to the LLM.
  String get description;

  /// Parameter definitions used to build the JSON schema sent to the LLM.
  List<ToolParameter> get parameters;

  /// Execute the tool with the given [args] and return the output as a
  /// string.
  Future<String> execute(Map<String, dynamic> args);

  /// Build the JSON schema representation for this tool.
  Map<String, dynamic> toSchema() => {
        'name': name,
        'description': description,
        'input_schema': {
          'type': 'object',
          'properties': {
            for (final p in parameters) p.name: p.toSchema(),
          },
          'required': [
            for (final p in parameters)
              if (p.required) p.name,
          ],
        },
      };
}

// ---------------------------------------------------------------------------
// Built-in tools
// ---------------------------------------------------------------------------

/// Read a file from disk.
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
  Future<String> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) return 'Error: no path provided';
    final file = File(path);
    if (!await file.exists()) {
      return 'Error: file not found: $path';
    }
    final stat = await file.stat();
    if (stat.size > 1024 * 1024) {
      return 'Error: file too large (${stat.size} bytes, max 1MB): $path';
    }
    return file.readAsString();
  }
}

/// Write content to a file on disk.
class WriteFileTool extends Tool {
  @override
  String get name => 'write_file';

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
  Future<String> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    final content = args['content'];
    if (path is! String || path.isEmpty) return 'Error: no path provided';
    if (content is! String) return 'Error: no content provided';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return 'Wrote ${content.length} bytes to $path';
  }
}

/// Run a shell command and return its output.
class BashTool extends Tool {
  @override
  String get name => 'bash';

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
  Future<String> execute(Map<String, dynamic> args) async {
    final command = args['command'];
    if (command is! String || command.isEmpty) {
      return 'Error: no command provided';
    }
    final t = args['timeout_seconds'];
    final timeoutSeconds =
        (t is num) ? t.toInt() : AppConstants.bashTimeoutSeconds;
    try {
      final process = await Process.start('sh', ['-c', command]);
      final stdoutFuture =
          process.stdout.transform(const SystemEncoding().decoder).join();
      final stderrFuture =
          process.stderr.transform(const SystemEncoding().decoder).join();

      final int exitCode;
      if (timeoutSeconds == 0) {
        exitCode = await process.exitCode;
      } else {
        exitCode = await process.exitCode
            .timeout(Duration(seconds: timeoutSeconds), onTimeout: () {
          process.kill();
          return -1;
        });
      }

      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;

      if (exitCode == -1) {
        return 'Error: command timed out after $timeoutSeconds seconds';
      }

      final buf = StringBuffer();
      if (stdout.isNotEmpty) buf.writeln(stdout);
      if (stderr.isNotEmpty) buf.writeln('STDERR: $stderr');
      buf.writeln('Exit code: $exitCode');
      return buf.toString();
    } on TimeoutException {
      return 'Error: command timed out after $timeoutSeconds seconds';
    }
  }
}

/// Search for a pattern in files using ripgrep-style semantics.
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
  Future<String> execute(Map<String, dynamic> args) async {
    final pattern = args['pattern'];
    if (pattern is! String || pattern.isEmpty) {
      return 'Error: no pattern provided';
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
          .timeout(Duration(seconds: AppConstants.grepTimeoutSeconds));
      if ((result.stdout as String).isEmpty) {
        return 'No matches found.';
      }
      return result.stdout as String;
    } on TimeoutException {
      return 'Error: grep timed out after ${AppConstants.grepTimeoutSeconds} seconds';
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

/// Edit a file by replacing an exact string match.
class EditFileTool extends Tool {
  @override
  String get name => 'edit_file';

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
  Future<String> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) return 'Error: no path provided';
    final oldString = args['old_string'] as String? ?? '';
    final newString = args['new_string'] as String? ?? '';

    final file = File(path);

    if (oldString.isEmpty) {
      await file.parent.create(recursive: true);
      await file.writeAsString(newString);
      return 'Created ${file.path} (${newString.length} bytes)';
    }

    if (!await file.exists()) {
      return 'Error: file not found: $path';
    }

    final content = await file.readAsString();

    final firstIndex = content.indexOf(oldString);
    if (firstIndex == -1) {
      return 'Error: old_string not found in $path. '
          'Make sure it matches the file content exactly, '
          'including whitespace and indentation.';
    }

    final lastIndex = content.lastIndexOf(oldString);
    if (firstIndex != lastIndex) {
      return 'Error: old_string appears multiple times in $path. '
          'Include more surrounding context lines to make the match unique.';
    }

    final newContent = content.substring(0, firstIndex) +
        newString +
        content.substring(firstIndex + oldString.length);

    await file.writeAsString(newContent);

    final oldLines = oldString.split('\n').length;
    final newLines = newString.split('\n').length;
    return 'Applied edit to $path: replaced $oldLines line(s) with $newLines line(s)';
  }
}

/// List directory contents.
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
  Future<String> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) return 'Error: no path provided';
    final dir = Directory(path);
    if (!await dir.exists()) {
      return 'Error: directory not found: $path';
    }
    final entries = await dir.list().take(AppConstants.globMaxEntries).toList();
    final buf = StringBuffer();
    for (final entry in entries) {
      final suffix = entry is Directory ? '/' : '';
      buf.writeln('${entry.path}$suffix');
    }
    if (entries.length == AppConstants.globMaxEntries) {
      buf.writeln('(output capped at ${AppConstants.globMaxEntries} entries)');
    }
    return buf.toString();
  }
}
