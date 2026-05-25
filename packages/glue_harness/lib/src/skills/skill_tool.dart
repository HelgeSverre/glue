import 'package:glue_harness/src/agent/tools.dart';
import 'package:glue_harness/src/skills/skill_runtime.dart';
import 'package:glue_harness/src/skills/skill_registry.dart';
import 'package:glue_harness/src/skills/skill_parser.dart';

class SkillTool extends Tool {
  final SkillRuntime _runtime;

  SkillTool(this._runtime);

  @override
  String get name => 'skill';

  @override
  String get description =>
      'Load a skill\'s instructions into context. Call with a skill name to '
      'activate it, or with no arguments to list available skills.';

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'name',
      type: 'string',
      description:
          'The name of the skill to activate. Omit to list all available skills.',
      required: false,
    ),
  ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final registry = _runtime.refresh();
    final skillName = args['name'] as String?;

    if (skillName == null || skillName.isEmpty) {
      final skills = registry.list();
      return ToolResult(
        content: _listSkills(registry),
        summary:
            'Listed ${skills.length} skill${skills.length == 1 ? '' : 's'}',
        metadata: {'skill_count': skills.length},
      );
    }

    final meta = registry.findByName(skillName);
    final text = _activateSkill(registry, skillName);
    return ToolResult(
      success: meta != null,
      content: text,
      summary: meta != null
          ? 'Activated skill: $skillName'
          : 'Skill not found: $skillName',
      metadata: {'skill_name': skillName, 'found': meta != null},
    );
  }

  String _listSkills(SkillRegistry registry) {
    final skills = registry.list();
    if (skills.isEmpty) {
      return 'No skills available.\n\n${skillDiscoveryHelpText()}';
    }

    final buf = StringBuffer('Available skills (${skills.length}):\n\n');
    for (final s in skills) {
      final tag = s.source.label;
      buf.writeln('  ${s.name} [$tag]');
      buf.writeln('    ${s.description}');
      if (s.allowedTools.isNotEmpty) {
        buf.writeln('    allowed-tools: ${s.allowedTools.join(', ')}');
      }
      if (s.resources.isNotEmpty) {
        buf.writeln('    resources: ${_resourceSummary(s.resources.length)}');
      }
      buf.writeln('');
    }
    final diagnostics = registry.diagnostics();
    if (diagnostics.isNotEmpty) {
      buf.writeln('Diagnostics:');
      for (final diagnostic in diagnostics.take(10)) {
        buf.writeln('  ${_formatDiagnostic(diagnostic)}');
      }
      if (diagnostics.length > 10) {
        buf.writeln('  ... ${diagnostics.length - 10} more');
      }
      buf.writeln('');
    }
    buf.write('Use skill(name: "skill-name") to activate a skill.');
    return buf.toString();
  }

  String _activateSkill(SkillRegistry registry, String skillName) {
    final meta = registry.findByName(skillName);
    if (meta == null) {
      final available = registry.list().map((s) => s.name).join(', ');
      return 'Error: skill "$skillName" not found.\n'
          'Available skills: ${available.isEmpty ? "(none)" : available}';
    }

    try {
      final body = registry.loadBody(skillName);
      final buf = StringBuffer();
      buf.writeln('# Skill: ${meta.name}');
      if (meta.license != null) buf.writeln('License: ${meta.license}');
      if (meta.compatibility != null) {
        buf.writeln('Compatibility: ${meta.compatibility}');
      }
      buf.writeln('Source: ${meta.skillDir}');
      if (meta.allowedTools.isNotEmpty) {
        buf.writeln('Allowed tools: ${meta.allowedTools.join(', ')}');
      }
      if (meta.resources.isNotEmpty) {
        buf.writeln('Resources:');
        for (final resource in meta.resources.take(50)) {
          final size = resource.sizeBytes == null
              ? ''
              : ', ${resource.sizeBytes} bytes';
          buf.writeln(
            '- ${resource.relativePath} (${resource.kind.name}$size)',
          );
        }
        if (meta.resources.length > 50) {
          buf.writeln('- ... ${meta.resources.length - 50} more resources');
        }
      }
      buf.writeln('Relative paths resolve from: ${meta.skillDir}');
      buf.writeln('');
      buf.writeln(body);
      return buf.toString();
    } on SkillParseError catch (e) {
      return 'Error loading skill "$skillName": $e';
    }
  }

  String _resourceSummary(int count) {
    return '$count resource file${count == 1 ? '' : 's'}';
  }

  String _formatDiagnostic(SkillDiagnostic diagnostic) {
    return '[${diagnostic.severity.name}] ${diagnostic.code}: '
        '${diagnostic.message}'
        '${diagnostic.path == null ? '' : ' (${diagnostic.path})'}';
  }
}
