import 'dart:async';
import 'dart:io';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/shell/command_executor.dart';

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

/// Which group a tool belongs to for mode-based filtering.
enum ToolGroup {
  /// Read-only, side-effect-free tools (read_file, grep, list_directory, etc.).
  read,

  /// Tools that create or modify files (write_file, edit_file).
  edit,

  /// Tools that execute shell commands (bash).
  command,

  /// External integrations (MCP tools, web_search, web_browser).
  mcp,
}

/// How much trust a tool requires from the permission system.
enum ToolTrust {
  /// Read-only or side-effect-free tools. Auto-approved in most modes.
  safe,

  /// Tools that create or modify files.
  fileEdit,

  /// Tools that execute arbitrary shell commands.
  command,
}

/// Base class for all tools available to the agent.
///
/// Each tool declares its [name], [description], and [parameters] so the
/// LLM can decide when and how to invoke it. The [execute] method
/// performs the actual work and returns a string result.
///
/// {@category Tools}
abstract class Tool {
  /// Machine-readable tool name (e.g. `read_file`).
  String get name;

  /// Human-readable description shown to the LLM.
  String get description;

  /// Parameter definitions used to build the JSON schema sent to the LLM.
  List<ToolParameter> get parameters;

  /// Executes this tool with the given [args] and returns structured content.
  Future<List<ContentPart>> execute(Map<String, dynamic> args);

  /// The trust level this tool requires. Defaults to [ToolTrust.safe].
  ToolTrust get trust => ToolTrust.safe;

  /// Whether this tool can mutate state (files, shell commands, etc.).
  bool get isMutating => trust != ToolTrust.safe;

  /// The tool group for mode-based filtering. Defaults based on [trust].
  ToolGroup get group => switch (trust) {
        ToolTrust.safe => ToolGroup.read,
        ToolTrust.fileEdit => ToolGroup.edit,
        ToolTrust.command => ToolGroup.command,
      };

  /// Releases any resources held by this tool.
  Future<void> dispose() async {}

  /// Builds the JSON schema representation for this tool.
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

/// Base class for tool decorators. Forwards all methods to [inner].
///
/// Extend this and override only what you need. When new methods are
/// added to [Tool], only this class needs updating — all decorators
/// inherit the forwarding automatically.
class ForwardingTool extends Tool {
  final Tool inner;
  ForwardingTool(this.inner);

  @override
  String get name => inner.name;
  @override
  String get description => inner.description;
  @override
  List<ToolParameter> get parameters => inner.parameters;
  @override
  Future<List<ContentPart>> execute(Map<String, dynamic> args) =>
      inner.execute(args);
  @override
  ToolTrust get trust => inner.trust;
  @override
  bool get isMutating => inner.isMutating;
  @override
  ToolGroup get group => inner.group;
  @override
  Future<void> dispose() => inner.dispose();
  @override
  Map<String, dynamic> toSchema() => inner.toSchema();
}

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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) {
      return [const TextPart('Error: no path provided')];
    }
    final file = File(path);
    if (!await file.exists()) {
      return [TextPart('Error: file not found: $path')];
    }
    final stat = await file.stat();
    if (stat.size > 1024 * 1024) {
      return [
        TextPart('Error: file too large (${stat.size} bytes, max 1MB): $path')
      ];
    }
    return [TextPart(await file.readAsString())];
  }
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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    final content = args['content'];
    if (path is! String || path.isEmpty) {
      return [const TextPart('Error: no path provided')];
    }
    if (content is! String) {
      return [const TextPart('Error: no content provided')];
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return [TextPart('Wrote ${content.length} bytes to $path')];
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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final command = args['command'];
    if (command is! String || command.isEmpty) {
      return [const TextPart('Error: no command provided')];
    }
    final t = args['timeout_seconds'];
    final timeoutSeconds =
        (t is num) ? t.toInt() : AppConstants.bashTimeoutSeconds;
    final timeout =
        timeoutSeconds == 0 ? null : Duration(seconds: timeoutSeconds);

    final result = await executor.runCapture(command, timeout: timeout);

    if (result.exitCode == -1 && timeout != null) {
      return [
        TextPart('Error: command timed out after $timeoutSeconds seconds')
      ];
    }

    final buf = StringBuffer();
    if (result.stdout.isNotEmpty) buf.writeln(result.stdout);
    if (result.stderr.isNotEmpty) buf.writeln('STDERR: ${result.stderr}');
    buf.writeln('Exit code: ${result.exitCode}');
    return [TextPart(buf.toString())];
  }
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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final pattern = args['pattern'];
    if (pattern is! String || pattern.isEmpty) {
      return [const TextPart('Error: no pattern provided')];
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
      if ((result.stdout as String).isEmpty) {
        return [const TextPart('No matches found.')];
      }
      return [TextPart(result.stdout as String)];
    } on TimeoutException {
      return [
        const TextPart(
            'Error: grep timed out after ${AppConstants.grepTimeoutSeconds} seconds')
      ];
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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) {
      return [const TextPart('Error: no path provided')];
    }
    final oldString = args['old_string'] as String? ?? '';
    final newString = args['new_string'] as String? ?? '';

    final file = File(path);

    if (oldString.isEmpty) {
      await file.parent.create(recursive: true);
      await file.writeAsString(newString);
      return [TextPart('Created ${file.path} (${newString.length} bytes)')];
    }

    if (!await file.exists()) {
      return [TextPart('Error: file not found: $path')];
    }

    final content = await file.readAsString();

    final firstIndex = content.indexOf(oldString);
    if (firstIndex == -1) {
      return [
        TextPart('Error: old_string not found in $path. '
            'Make sure it matches the file content exactly, '
            'including whitespace and indentation.')
      ];
    }

    final lastIndex = content.lastIndexOf(oldString);
    if (firstIndex != lastIndex) {
      return [
        TextPart('Error: old_string appears multiple times in $path. '
            'Include more surrounding context lines to make the match unique.')
      ];
    }

    final newContent = content.substring(0, firstIndex) +
        newString +
        content.substring(firstIndex + oldString.length);

    await file.writeAsString(newContent);

    final oldLines = oldString.split('\n').length;
    final newLines = newString.split('\n').length;
    return [
      TextPart(
          'Applied edit to $path: replaced $oldLines line(s) with $newLines line(s)')
    ];
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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) {
      return [const TextPart('Error: no path provided')];
    }
    final dir = Directory(path);
    if (!await dir.exists()) {
      return [TextPart('Error: directory not found: $path')];
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
    return [TextPart(buf.toString())];
  }
}
