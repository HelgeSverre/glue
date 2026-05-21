import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/arg_completers.dart' as arg_completers;
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/conversation/entry.dart';
import 'package:glue/src/ui/skills_docked_panel.dart';

/// `/skills` — open a docked skills picker, or activate a skill by name.
class SkillsCommand extends SlashCommand {
  SkillsCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'skills';

  @override
  String get description => 'Browse skills or activate one by name';

  @override
  SlashArgCompleter? get argCompleter =>
      (prior, partial) => prior.isEmpty
      ? arg_completers.skillCandidates(ctx.skills.list(), partial)
      : const [];

  @override
  String execute(List<String> args) {
    if (args.isEmpty) {
      _openPicker();
      return '';
    }
    final name = args.join(' ').trim();
    if (name.isEmpty) return 'Usage: /skills [skill-name]';
    _activate(name);
    return 'Activating skill "$name"...';
  }

  void _openPicker() {
    final registry = ctx.skills.refresh();
    if (registry.isEmpty) {
      ctx.conversation.notify(
        'No skills found.\n\n${skillDiscoveryHelpText()}',
      );
      return;
    }
    final panel = _findOrCreatePanel();
    panel.updateSkills(registry.list());
    if (panel.visible) {
      panel.dismiss();
      return;
    }
    panel.show();
    panel.selection.then((skillName) async {
      if (skillName != null) await _activate(skillName);
    });
  }

  SkillsDockedPanel _findOrCreatePanel() {
    for (final p in ctx.dockManager.panels) {
      if (p is SkillsDockedPanel) return p;
    }
    final panel = SkillsDockedPanel(skills: ctx.skills.list());
    ctx.dockManager.add(panel);
    return panel;
  }

  Future<void> _activate(String skillName) async {
    try {
      final activation = await activateSkillIntoConversation(
        agent: ctx.agent,
        skillName: skillName,
      );
      ctx.ensureSession();
      ctx.session.logEvent('tool_call', {
        'name': 'skill',
        'arguments': {'name': skillName},
      });
      ctx.session.logEvent('tool_result', {
        'name': 'skill',
        'content': activation.content,
      });
      ctx.conversation.addEntry(
        ConversationEntry.toolCall('skill', {'name': skillName}),
      );
      ctx.conversation.addEntry(
        ConversationEntry.toolResult(activation.content),
      );
    } on SkillActivationError catch (e) {
      ctx.conversation.notify(e.message);
    } catch (e) {
      ctx.conversation.notify('Error activating skill "$skillName": $e');
    }
  }
}
