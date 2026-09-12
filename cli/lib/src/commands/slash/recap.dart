import 'dart:async';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/recap` — one-line LLM-generated summary of the current session.
///
/// Uses the small/title-generation model (`config.smallModel`, falling back
/// to the active model) so it stays cheap. Posts the result inline as a
/// system message.
class RecapCommand extends SlashCommand {
  RecapCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'recap';

  @override
  String get description => 'Summarize the current session in one line';

  @override
  List<String> get aliases => const ['summary'];

  @override
  String execute(List<String> args) {
    if (args.isNotEmpty) return 'Usage: /recap';

    final convo = ctx.agent.conversation;
    if (!convo.any((m) => m.role == Role.user) ||
        !convo.any((m) => m.role == Role.assistant)) {
      return 'Not enough conversation yet to summarize.';
    }

    final llm = _resolveLlm();
    if (llm == null) {
      return 'Recap unavailable: no model configured for summarization.';
    }

    _run(llm);
    return '';
  }

  Future<void> _run(LlmClient llm) async {
    final generator = RecapGenerator(
      llmClient: llm,
      onUsage: (usage) =>
          ctx.session.recordUsage(UsageStats()..record(usage), role: 'recap'),
    );
    final summary = await generator.generateFromContext(
      TitleContext.fromConversation(
        ctx.agent.conversation,
        cwdBasename: ctx.cwd.split(Platform.pathSeparator).last,
      ),
    );
    ctx.conversation.notify(
      summary == null || summary.isEmpty
          ? 'Could not generate recap.'
          : 'Recap: $summary',
    );
  }

  LlmClient? _resolveLlm() {
    final factory = ctx.llmFactory;
    if (factory == null) return null;
    try {
      return factory.createSmall(systemPrompt: RecapGenerator.systemPrompt);
    } on ConfigError {
      return null;
    }
  }
}
