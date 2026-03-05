import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/skills/skill_registry.dart';
import 'package:glue/src/skills/skill_parser.dart';

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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final registry = _runtime.refresh();
    final skillName = args['name'] as String?;

    if (skillName == null || skillName.isEmpty) {
      return [TextPart(_listSkills(registry))];
    }

    return [TextPart(_activateSkill(registry, skillName))];
  }

  String _listSkills(SkillRegistry registry) {
    final skills = registry.list();
    if (skills.isEmpty) {
      return 'No skills available.\n\n'
          'Glue discovers skills from:\n'
          '  .glue/skills/<skill-name>/SKILL.md (project-local)\n'
          '  ~/.glue/skills/<skill-name>/SKILL.md (global)\n'
          '  configured skill_paths (custom)\n'
          '  bundled Glue skills (builtin)';
    }

    final buf = StringBuffer('Available skills (${skills.length}):\n\n');
    for (final s in skills) {
      final tag = s.source.label;
      buf.writeln('  ${s.name} [$tag]');
      buf.writeln('    ${s.description}');
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
      buf.writeln('');
      buf.writeln(body);
      return buf.toString();
    } on SkillParseError catch (e) {
      return 'Error loading skill "$skillName": $e';
    }
  }
}
