import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/runtime/commands/register_builtin_slash_commands.dart';

/// Registration point for built-in slash commands.
class BuiltinCommands {
  static SlashCommandRegistry create({
    required void Function() openHelpPanel,
    required String Function() clearConversation,
    required void Function() requestExit,
    required void Function() openModelPanel,
    required String Function(String query) switchModelByQuery,
    required String Function(List<String> args) sessionAction,
    required String Function(List<String> args) shareAction,
    required String Function() listTools,
    required void Function() openHistoryPanel,
    required String Function(String query) historyActionByQuery,
    required void Function() openResumePanel,
    required String Function(String query) resumeSessionByQuery,
    required String Function() toggleDebug,
    required void Function() openSkillsPanel,
    required String Function(String skillName) activateSkillByName,
    required String Function() toggleApproval,
    required String Function(List<String> args) runProviderCommand,
    required String Function() pathsReport,
    required String Function(List<String> args) openGlueTarget,
    required String Function(List<String> args) configAction,
    required String Function(String title) renameSession,
  }) {
    return buildBuiltinSlashCommands(_LegacySlashCommandContext(
      system: _LegacySystemCommands(
        openHelpPanel: openHelpPanel,
        requestExit: requestExit,
        toggleDebug: toggleDebug,
        pathsReport: pathsReport,
        openGlueTarget: openGlueTarget,
        configAction: configAction,
      ),
      chat: _LegacyChatCommands(
        clearConversation: clearConversation,
        listTools: listTools,
        toggleApproval: toggleApproval,
      ),
      models: _LegacyModelCommands(
        openModelPanel: openModelPanel,
        switchModelByQuery: switchModelByQuery,
      ),
      sessions: _LegacySessionCommands(
        sessionAction: sessionAction,
        openHistoryPanel: openHistoryPanel,
        historyActionByQuery: historyActionByQuery,
        openResumePanel: openResumePanel,
        resumeSessionByQuery: resumeSessionByQuery,
        renameSession: renameSession,
      ),
      share: _LegacyShareCommands(shareAction: shareAction),
      skills: _LegacySkillsCommands(
        openSkillsPanel: openSkillsPanel,
        activateSkillByName: activateSkillByName,
      ),
      providers: _LegacyProviderCommands(
        runProviderCommand: runProviderCommand,
      ),
    ));
  }
}

class _LegacySlashCommandContext implements SlashCommandContext {
  const _LegacySlashCommandContext({
    required this.system,
    required this.chat,
    required this.models,
    required this.sessions,
    required this.share,
    required this.skills,
    required this.providers,
  });

  @override
  final SystemCommandController system;

  @override
  final ChatCommandController chat;

  @override
  final ModelCommandController models;

  @override
  final SessionCommandController sessions;

  @override
  final ShareCommandController share;

  @override
  final SkillsCommandController skills;

  @override
  final ProviderCommandController providers;
}

class _LegacySystemCommands implements SystemCommandController {
  const _LegacySystemCommands({
    required void Function() openHelpPanel,
    required void Function() requestExit,
    required String Function() toggleDebug,
    required String Function() pathsReport,
    required String Function(List<String> args) openGlueTarget,
    required String Function(List<String> args) configAction,
  })  : _openHelpPanel = openHelpPanel,
        _requestExit = requestExit,
        _toggleDebug = toggleDebug,
        _pathsReport = pathsReport,
        _openGlueTarget = openGlueTarget,
        _configAction = configAction;

  final void Function() _openHelpPanel;
  final void Function() _requestExit;
  final String Function() _toggleDebug;
  final String Function() _pathsReport;
  final String Function(List<String> args) _openGlueTarget;
  final String Function(List<String> args) _configAction;

  @override
  void openHelpPanel() => _openHelpPanel();

  @override
  void requestExit() => _requestExit();

  @override
  String toggleDebug() => _toggleDebug();

  @override
  String pathsReport() => _pathsReport();

  @override
  String openGlueTarget(List<String> args) => _openGlueTarget(args);

  @override
  String configAction(List<String> args) => _configAction(args);

  @override
  List<SlashArgCandidate> openArgCandidates(
    List<String> prior,
    String partial,
  ) =>
      const [];
}

class _LegacyChatCommands implements ChatCommandController {
  const _LegacyChatCommands({
    required String Function() clearConversation,
    required String Function() listTools,
    required String Function() toggleApproval,
  })  : _clearConversation = clearConversation,
        _listTools = listTools,
        _toggleApproval = toggleApproval;

  final String Function() _clearConversation;
  final String Function() _listTools;
  final String Function() _toggleApproval;

  @override
  String clearConversation() => _clearConversation();

  @override
  String listTools() => _listTools();

  @override
  String toggleApproval() => _toggleApproval();
}

class _LegacyModelCommands implements ModelCommandController {
  const _LegacyModelCommands({
    required void Function() openModelPanel,
    required String Function(String query) switchModelByQuery,
  })  : _openModelPanel = openModelPanel,
        _switchModelByQuery = switchModelByQuery;

  final void Function() _openModelPanel;
  final String Function(String query) _switchModelByQuery;

  @override
  void openModelPanel() => _openModelPanel();

  @override
  String switchModelByQuery(String query) => _switchModelByQuery(query);

  @override
  List<SlashArgCandidate> modelArgCandidates(
    List<String> prior,
    String partial,
  ) =>
      const [];
}

class _LegacySessionCommands implements SessionCommandController {
  const _LegacySessionCommands({
    required String Function(List<String> args) sessionAction,
    required void Function() openHistoryPanel,
    required String Function(String query) historyActionByQuery,
    required void Function() openResumePanel,
    required String Function(String query) resumeSessionByQuery,
    required String Function(String title) renameSession,
  })  : _sessionAction = sessionAction,
        _openHistoryPanel = openHistoryPanel,
        _historyActionByQuery = historyActionByQuery,
        _openResumePanel = openResumePanel,
        _resumeSessionByQuery = resumeSessionByQuery,
        _renameSession = renameSession;

  final String Function(List<String> args) _sessionAction;
  final void Function() _openHistoryPanel;
  final String Function(String query) _historyActionByQuery;
  final void Function() _openResumePanel;
  final String Function(String query) _resumeSessionByQuery;
  final String Function(String title) _renameSession;

  @override
  String sessionAction(List<String> args) => _sessionAction(args);

  @override
  void openHistoryPanel() => _openHistoryPanel();

  @override
  String historyActionByQuery(String query) => _historyActionByQuery(query);

  @override
  void openResumePanel() => _openResumePanel();

  @override
  String resumeSessionByQuery(String query) => _resumeSessionByQuery(query);

  @override
  String renameSession(String title) => _renameSession(title);

  @override
  List<SlashArgCandidate> sessionArgCandidates(
    List<String> prior,
    String partial,
  ) =>
      const [];
}

class _LegacyShareCommands implements ShareCommandController {
  const _LegacyShareCommands({
    required String Function(List<String> args) shareAction,
  }) : _shareAction = shareAction;

  final String Function(List<String> args) _shareAction;

  @override
  String shareAction(List<String> args) => _shareAction(args);

  @override
  List<SlashArgCandidate> shareArgCandidates(
    List<String> prior,
    String partial,
  ) =>
      const [];
}

class _LegacySkillsCommands implements SkillsCommandController {
  const _LegacySkillsCommands({
    required void Function() openSkillsPanel,
    required String Function(String skillName) activateSkillByName,
  })  : _openSkillsPanel = openSkillsPanel,
        _activateSkillByName = activateSkillByName;

  final void Function() _openSkillsPanel;
  final String Function(String skillName) _activateSkillByName;

  @override
  void openSkillsPanel() => _openSkillsPanel();

  @override
  String activateSkillByName(String skillName) =>
      _activateSkillByName(skillName);

  @override
  List<SlashArgCandidate> skillsArgCandidates(
    List<String> prior,
    String partial,
  ) =>
      const [];
}

class _LegacyProviderCommands implements ProviderCommandController {
  const _LegacyProviderCommands({
    required String Function(List<String> args) runProviderCommand,
  }) : _runProviderCommand = runProviderCommand;

  final String Function(List<String> args) _runProviderCommand;

  @override
  String runProviderCommand(List<String> args) => _runProviderCommand(args);

  @override
  List<SlashArgCandidate> providerArgCandidates(
    List<String> prior,
    String partial,
  ) =>
      const [];
}
