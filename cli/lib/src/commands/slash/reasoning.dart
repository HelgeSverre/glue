import 'package:glue_core/glue_core.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/select_panel.dart';

class ReasoningCommand extends SlashCommand {
  ReasoningCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'reasoning';

  @override
  String get description => 'Set model reasoning effort and thought display';

  @override
  SlashArgCompleter get argCompleter => (prior, partial) {
    if (prior.isEmpty) {
      final model = ctx.config?.resolveModel(ctx.config!.activeModel).def;
      final supported = model?.reasoning?.efforts ?? const <ReasoningEffort>{};
      return [
        ...ReasoningEffort.values
            .where(
              (effort) =>
                  effort == ReasoningEffort.auto || supported.contains(effort),
            )
            .map((effort) => SlashArgCandidate(value: effort.name)),
        const SlashArgCandidate(value: 'thoughts', continues: true),
      ].where((candidate) => candidate.value.startsWith(partial)).toList();
    }
    if (prior.first == 'thoughts') {
      return const [
        SlashArgCandidate(value: 'on'),
        SlashArgCandidate(value: 'off'),
      ].where((candidate) => candidate.value.startsWith(partial)).toList();
    }
    return const [];
  };

  @override
  String execute(List<String> args) {
    final config = ctx.config;
    if (config == null) return 'Config not ready.';
    if (args.isEmpty) {
      _openPicker();
      return '';
    }
    if (args.first == 'thoughts') {
      if (args.length != 2 || !const {'on', 'off'}.contains(args[1])) {
        return 'Usage: /reasoning thoughts <on|off>';
      }
      return ctx.setReasoning(
        config.reasoning.copyWith(showThoughts: args[1] == 'on'),
      );
    }
    final matches = ReasoningEffort.values.where(
      (effort) => effort.name == args.first,
    );
    if (matches.isEmpty || args.length != 1) {
      return 'Usage: /reasoning <${ReasoningEffort.values.map((e) => e.name).join('|')}>';
    }
    return ctx.setReasoning(config.reasoning.copyWith(effort: matches.first));
  }

  void _openPicker() {
    final config = ctx.config;
    if (config == null) return;
    final model = config.resolveModel(config.activeModel).def;
    final supported = model.reasoning?.efforts ?? const {ReasoningEffort.auto};
    final efforts = ReasoningEffort.values
        .where(
          (effort) =>
              effort == ReasoningEffort.auto || supported.contains(effort),
        )
        .toList();
    final panel = SelectPanel<ReasoningEffort>(
      title: 'Reasoning Effort',
      options: efforts
          .map(
            (effort) => SelectOption(
              value: effort,
              label:
                  '${effort == config.reasoning.effort ? '●' : ' '} ${effort.name}',
            ),
          )
          .toList(),
      searchEnabled: false,
      barrier: BarrierStyle.dim,
      width: PanelFixed(34),
      height: PanelFluid(0.5, 8),
      initialIndex: efforts.indexOf(config.reasoning.effort).clamp(0, 999),
    );
    ctx.panels.push(panel);
    panel.selection.then((effort) {
      ctx.panels.dismiss(panel);
      if (effort == null) return;
      ctx.conversation.notify(
        ctx.setReasoning(config.reasoning.copyWith(effort: effort)),
      );
    });
  }
}
