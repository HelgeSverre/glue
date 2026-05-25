import 'dart:io';

import 'package:glue_harness/src/skills/skill_parser.dart';
import 'package:path/path.dart' as p;

class Prompts {
  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  Prompts._();

  static const String system = '''
You are Glue, an expert coding agent that helps developers with software engineering tasks.

You operate inside a terminal. You have access to tools for reading files, writing files,
editing files, running shell commands, searching code, and listing directories.

Guidelines:
- Be direct and technical. Respect the developer's expertise.
- Use tools proactively to gather context before answering.
- When modifying code, read the file first to understand conventions.
- Prefer edit_file over write_file for existing files (smaller diffs, less error-prone).
- Make the smallest reasonable change. Don't over-engineer.
- If a task requires multiple steps, work through them sequentially.
- Always verify your work by reading back files you've written.
- Anchor conclusions in fetched sources. When you fetch a document, surface
  its key claims verbatim before proposing actions; do not silently drop a
  doc's main conclusion.
- Match output scope to the question asked. If asked whether X applies,
  answer that first; do not pivot to a generic plan for X unless explicitly
  requested.
''';

  // 50KB cap to prevent runaway context growth from large files
  static const _maxGuidanceBytes = 50 * 1024;

  static const _guidanceFiles = ['AGENTS.md', 'CLAUDE.md'];

  static String build({
    String? cwd,
    String? projectContext,
    List<SkillMeta> skills = const [],
    String? homeDir,
  }) {
    final buf = StringBuffer(system);

    if (cwd != null) {
      final guidance = _collectGuidance(cwd, homeDir: homeDir);
      for (final entry in guidance) {
        buf.write(
          '\n\n## Project Instructions (${entry.label})\n\n${entry.content}',
        );
      }
    }

    if (skills.isNotEmpty) {
      buf.write('\n\n## Skills\n\n');
      buf.write(
        'The following skills provide specialized instructions for specific tasks.\n',
      );
      buf.write(
        'Skill trigger rules:\n'
        '- If the user explicitly names a skill, call the skill tool for that skill.\n'
        '- If the task clearly matches a skill description, call the skill tool before doing substantive work.\n'
        '- If a named skill is unavailable, say so and continue with the best fallback approach.\n'
        '- After loading a skill, follow its SKILL.md instructions and only load referenced files as needed.\n\n',
      );
      buf.write('<available_skills>\n');
      for (final s in skills) {
        buf.write('  <skill>\n');
        buf.write('    <name>${_escapeXml(s.name)}</name>\n');
        buf.write(
          '    <description>${_escapeXml(s.description)}</description>\n',
        );
        if (s.allowedTools.isNotEmpty) {
          buf.write(
            '    <allowed_tools>${_escapeXml(s.allowedTools.join(', '))}</allowed_tools>\n',
          );
        }
        if (s.resources.isNotEmpty) {
          buf.write('    <resources count="${s.resources.length}" />\n');
        }
        buf.write('    <location>${_escapeXml(s.skillMdPath)}</location>\n');
        buf.write('  </skill>\n');
      }
      buf.write('</available_skills>');
    }

    if (projectContext != null && projectContext.isNotEmpty) {
      buf.write('\n\n## Project Context\n\n$projectContext');
    }
    return buf.toString();
  }

  /// Walks from [cwd] up to the workspace root and collects every `AGENTS.md`
  /// and `CLAUDE.md` along the way. The workspace root is the first ancestor
  /// containing `.git`; the walk also stops at [homeDir] to prevent personal
  /// `~/AGENTS.md` files from leaking into project sessions. If no `.git` root
  /// is reachable, only [cwd] itself is consulted (preserves prior behavior).
  ///
  /// Returns entries in **root → leaf** order so the closest file appears last
  /// and wins on conflicts when the model resolves the prompt top-down.
  static List<_GuidanceEntry> _collectGuidance(String cwd, {String? homeDir}) {
    final start = p.normalize(p.absolute(cwd));
    final normalizedHome = homeDir == null ? null : p.normalize(homeDir);

    final dirs = _discoverDirectories(start, normalizedHome);
    final workspaceRoot = dirs.last;

    final entries = <_GuidanceEntry>[];
    for (final dir in dirs.reversed) {
      for (final filename in _guidanceFiles) {
        final file = File(p.join(dir, filename));
        if (!file.existsSync()) continue;
        var content = file.readAsStringSync();
        if (content.length > _maxGuidanceBytes) {
          content =
              '${content.substring(0, _maxGuidanceBytes)}\n\n(truncated — file exceeded 50KB)';
        }
        final rel = p.relative(p.join(dir, filename), from: workspaceRoot);
        final label = rel == filename ? filename : rel;
        entries.add(_GuidanceEntry(label: label, content: content));
      }
    }
    return entries;
  }

  /// Returns [start] alone when no `.git` ancestor is reachable within
  /// [homeBoundary]. Otherwise returns the full chain from [start] up to
  /// (and including) the `.git`-bearing root, so guidance files at every
  /// level between cwd and repo root are discovered.
  static List<String> _discoverDirectories(String start, String? homeBoundary) {
    if (Directory(p.join(start, '.git')).existsSync()) {
      return [start];
    }

    final dirs = <String>[start];
    var current = start;
    while (true) {
      if (homeBoundary != null && current == homeBoundary) {
        return [start];
      }
      final parent = p.dirname(current);
      if (parent == current) return [start];
      current = parent;
      dirs.add(current);
      if (Directory(p.join(current, '.git')).existsSync()) {
        return dirs;
      }
    }
  }
}

class _GuidanceEntry {
  _GuidanceEntry({required this.label, required this.content});

  final String label;
  final String content;
}
