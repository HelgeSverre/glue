import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart' as tool_contract;
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/providers/llm_client_factory.dart';
import 'package:glue/src/runtime/app_mode.dart';
import 'package:glue/src/ui/actions/chat_actions.dart';
import 'package:glue/src/ui/actions/model_actions.dart';
import 'package:glue/src/ui/actions/provider_actions.dart';
import 'package:glue/src/ui/actions/session_actions.dart';
import 'package:glue/src/ui/actions/skills_actions.dart';
import 'package:glue/src/ui/actions/system_actions.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/runtime/services/session.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/components/modal.dart';
import 'package:glue/src/ui/actions/share_actions.dart';
import 'package:glue/src/ui/services/confirmations.dart';
import 'package:glue/src/ui/services/docks.dart';
import 'package:glue/src/ui/services/panels.dart';

/// TUI-facing actions that slash commands, panels, and keybindings can call.
///
/// This is intentionally concrete wiring, not a service locator: [App] builds
/// it once from explicit dependencies, and command registration receives only
/// this action surface.
class AppActions {
  AppActions({
    required Environment environment,
    required void Function() requestExit,
    required Panels panels,
    required List<SlashCommand> Function() commands,
    required void Function() render,
    required String? Function() currentSessionId,
    required Terminal terminal,
    required Layout layout,
    required void Function() clearConversationState,
    required Iterable<tool_contract.Tool> Function() tools,
    required ApprovalMode Function() getApprovalMode,
    required void Function(ApprovalMode mode) setApprovalMode,
    required Transcript transcript,
    required this.config,
    required LlmClientFactory? Function() getLlmFactory,
    required String? Function() getSystemPrompt,
    required Agent agent,
    required Session session,
    required Confirmations confirmations,
    required void Function(String modelId) setModelId,
    required String Function(String path) shortenPath,
    required String cwd,
    required String Function() modelLabel,
    required String Function() approvalLabel,
    required List<String> Function() autoApprovedTools,
    required bool Function() canShare,
    required SessionStore? Function() currentStore,
    required this.skillRuntime,
    required Docks docks,
    required Future<void> Function(String skillName) activateSkill,
    DebugController? debugController,
  }) {
    system = SystemActions(
      environment: environment,
      requestExit: requestExit,
      panels: panels,
      commands: commands,
      render: render,
      currentSessionId: currentSessionId,
      debugController: debugController,
    );
    chat = ChatActions(
      terminal: terminal,
      layout: layout,
      clearConversationState: clearConversationState,
      render: render,
      tools: tools,
      getApprovalMode: getApprovalMode,
      setApprovalMode: setApprovalMode,
      transcript: transcript,
      agent: agent,
    );
    models = ModelActions(
      config: config,
      getLlmFactory: getLlmFactory,
      getSystemPrompt: getSystemPrompt,
      agent: agent,
      session: session,
      panels: panels,
      confirmations: confirmations,
      transcript: transcript,
      render: render,
      setModelId: setModelId,
    );
    sessions = SessionActions(
      session: session,
      agent: agent,
      panels: panels,
      transcript: transcript,
      render: render,
      shortenPath: shortenPath,
      cwd: cwd,
      modelLabel: modelLabel,
      approvalLabel: approvalLabel,
      autoApprovedTools: autoApprovedTools,
    );
    share = ShareActions(
      canShare: canShare,
      currentStore: currentStore,
      cwd: cwd,
      transcript: transcript,
      render: render,
    );
    skills = SkillsActions(
      skillRuntime: skillRuntime,
      docks: docks,
      render: render,
      transcript: transcript,
      activateSkill: activateSkill,
    );
    providers = ProviderActions(
      config: config,
      panels: panels,
      transcript: transcript,
      render: render,
    );
  }

  final Config config;
  final SkillRuntime skillRuntime;

  late final SystemActions system;
  late final ChatActions chat;
  late final ModelActions models;
  late final SessionActions sessions;
  late final ShareActions share;
  late final SkillsActions skills;
  late final ProviderActions providers;
}

class AppConfirmations implements Confirmations {
  const AppConfirmations({
    required this.setMode,
    required this.setActiveModal,
    required this.getActiveModal,
    required this.render,
  });

  final void Function(AppMode mode) setMode;
  final void Function(ConfirmModal? modal) setActiveModal;
  final ConfirmModal? Function() getActiveModal;
  final void Function() render;

  @override
  Future<bool> confirm({
    required String title,
    required List<String> bodyLines,
    List<ModalChoice> choices = const [
      ModalChoice('Yes', 'y'),
      ModalChoice('No', 'n'),
    ],
  }) async {
    setMode(AppMode.confirming);
    final modal = ConfirmModal(
      title: title,
      bodyLines: bodyLines,
      choices: choices,
    );
    setActiveModal(modal);
    render();

    try {
      final choiceIndex = await modal.result;
      return choiceIndex == 0;
    } finally {
      if (identical(getActiveModal(), modal)) {
        setActiveModal(null);
      }
      setMode(AppMode.idle);
      render();
    }
  }
}
