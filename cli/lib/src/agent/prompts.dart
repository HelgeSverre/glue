import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:glue/src/skills/skill_parser.dart';

String _escapeXml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

class Prompts {
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
''';

  static const _maxGuidanceBytes = 50 * 1024;

  static const _guidanceFiles = ['AGENTS.md', 'CLAUDE.md'];

  static String build({
    String? cwd,
    String? projectContext,
    List<SkillMeta> skills = const [],
  }) {
    final buf = StringBuffer(system);

    if (cwd != null) {
      for (final filename in _guidanceFiles) {
        final file = File(p.join(cwd, filename));
        if (file.existsSync()) {
          var content = file.readAsStringSync();
          if (content.length > _maxGuidanceBytes) {
            content =
                '${content.substring(0, _maxGuidanceBytes)}\n\n(truncated — file exceeded 50KB)';
          }
          buf.write('\n\n## Project Instructions ($filename)\n\n$content');
        }
      }
    }

    if (skills.isNotEmpty) {
      buf.write('\n\n## Skills\n\n');
      buf.write(
          'The following skills provide specialized instructions for specific tasks.\n');
      buf.write(
          'Use the skill tool to load a skill when the task matches its description.\n\n');
      buf.write('<available_skills>\n');
      for (final s in skills) {
        buf.write('  <skill>\n');
        buf.write('    <name>${_escapeXml(s.name)}</name>\n');
        buf.write(
            '    <description>${_escapeXml(s.description)}</description>\n');
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
}
