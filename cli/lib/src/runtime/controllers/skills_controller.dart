import 'dart:async';
import 'package:glue/src/runtime/transcript.dart';

import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/skills/skills_docked_panel.dart';
import 'package:glue/src/ui/services/docks.dart';

class SkillsController {
  const SkillsController({
    required this.skillRuntime,
    required this.docks,
    required this.render,
    required this.transcript,
    required this.activateSkill,
  });

  final SkillRuntime skillRuntime;
  final Docks docks;
  final void Function() render;
  final Transcript transcript;
  final Future<void> Function(String skillName) activateSkill;

  void openSkillsPanel() {
    final registry = skillRuntime.refresh();
    if (registry.isEmpty) {
      transcript.system('No skills found.\n\n${skillDiscoveryHelpText()}');
      render();
      return;
    }

    var panel = _findSkillsDockedPanel();
    if (panel == null) {
      panel = SkillsDockedPanel(skills: registry.list());
      docks.add(panel);
    } else {
      panel.updateSkills(registry.list());
    }

    if (panel.visible) {
      panel.dismiss();
      render();
      return;
    }

    panel.show();
    unawaited(panel.selection.then((skillName) async {
      if (skillName != null) {
        await activateSkill(skillName);
      }
      render();
    }));
    render();
  }

  SkillsDockedPanel? _findSkillsDockedPanel() {
    for (final panel in docks.panels) {
      if (panel is SkillsDockedPanel) return panel;
    }
    return null;
  }

  String activateSkillByName(String skillName) {
    final normalized = skillName.trim();
    if (normalized.isEmpty) return 'Usage: /skills [skill-name]';
    unawaited(activateSkill(normalized).then((_) => render()));
    return 'Activating skill "$normalized"...';
  }
}
