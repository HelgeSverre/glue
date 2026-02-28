import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/skills/skill_registry.dart';
import 'package:glue/src/skills/skill_parser.dart';

class SkillTool extends Tool {
  final SkillRegistry _registry;

  SkillTool(this._registry);

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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final skillName = args['name'] as String?;

    if (skillName == null || skillName.isEmpty) {
      return [TextPart(_listSkills())];
    }

    return [TextPart(_activateSkill(skillName))];
  }

  String _listSkills() {
    final skills = _registry.list();
    if (skills.isEmpty) {
      return 'No skills available.\n\n'
          'To add skills, create directories with SKILL.md files in:\n'
          '  ~/.glue/skills/<skill-name>/SKILL.md (global)\n'
          '  .glue/skills/<skill-name>/SKILL.md (project-local)';
    }

    final buf = StringBuffer('Available skills (${skills.length}):\n\n');
    for (final s in skills) {
      final tag = switch (s.source) {
        SkillSource.project => 'project',
        SkillSource.global => 'global',
        SkillSource.custom => 'custom',
      };
      buf.writeln('  ${s.name} [$tag]');
      buf.writeln('    ${s.description}');
      buf.writeln('');
    }
    buf.write('Use skill(name: "skill-name") to activate a skill.');
    return buf.toString();
  }

  String _activateSkill(String skillName) {
    final meta = _registry.findByName(skillName);
    if (meta == null) {
      final available = _registry.list().map((s) => s.name).join(', ');
      return 'Error: skill "$skillName" not found.\n'
          'Available skills: ${available.isEmpty ? "(none)" : available}';
    }

    try {
      final body = _registry.loadBody(skillName);
      final buf = StringBuffer();
      buf.writeln('# Skill: ${meta.name}');
      if (meta.license != null) buf.writeln('License: ${meta.license}');
      if (meta.compatibility != null) {
        buf.writeln('Compatibility: ${meta.compatibility}');
      }
      buf.writeln('Source: ${meta.skillDir}');
      buf.writeln('');
      buf.writeln(body);
      return buf.toString();
    } on SkillParseError catch (e) {
      return 'Error loading skill "$skillName": $e';
    }
  }
}
