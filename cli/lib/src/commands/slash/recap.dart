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
    final summary = await generator.generateFromContext(_buildContext());
    ctx.conversation.notify(
      summary == null || summary.isEmpty
          ? 'Could not generate recap.'
          : 'Recap: $summary',
    );
  }

  LlmClient? _resolveLlm() {
    final config = ctx.config;
    final factory = ctx.llmFactory;
    if (config == null || factory == null) return null;
    final ref = config.smallModel ?? config.activeModel;
    try {
      return factory.createFor(ref, systemPrompt: RecapGenerator.systemPrompt);
    } on ConfigError {
      return null;
    }
  }

  TitleContext _buildContext() {
    String? firstUser;
    String? latestUser;
    String? firstAssistant;
    String? latestAssistant;
    final tools = <String>{};

    for (final msg in ctx.agent.conversation) {
      final text = msg.text?.trim();
      switch (msg.role) {
        case Role.user:
          if (text != null && text.isNotEmpty) {
            firstUser ??= text;
            latestUser = text;
          }
        case Role.assistant:
          if (text != null && text.isNotEmpty) {
            firstAssistant ??= text;
            latestAssistant = text;
          }
          for (final call in msg.toolCalls) {
            tools.add(call.name);
          }
        case Role.toolResult:
          break;
      }
    }

    return TitleContext(
      firstUserMessage: firstUser,
      latestUserMessage: latestUser,
      firstAssistantMessage: firstAssistant,
      latestAssistantMessage: latestAssistant,
      toolNames: tools.toList(),
      cwdBasename: ctx.cwd.split(Platform.pathSeparator).last,
    );
  }
}
