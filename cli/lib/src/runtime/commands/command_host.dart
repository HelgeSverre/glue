import 'package:glue/src/commands/slash_commands.dart';

abstract interface class SystemCommandController {
  void openHelpPanel();
  void requestExit();
  String toggleDebug();
  String pathsReport();
  String openGlueTarget(List<String> args);
  String configAction(List<String> args);
  List<SlashArgCandidate> openArgCandidates(List<String> prior, String partial);
}

abstract interface class ChatCommandController {
  String clearConversation();
  String listTools();
  String toggleApproval();
}

abstract interface class ModelCommandController {
  void openModelPanel();
  String switchModelByQuery(String query);
  List<SlashArgCandidate> modelArgCandidates(
    List<String> prior,
    String partial,
  );
}

abstract interface class SessionCommandController {
  String sessionAction(List<String> args);
  void openHistoryPanel();
  String historyActionByQuery(String query);
  void openResumePanel();
  String resumeSessionByQuery(String query);
  String renameSession(String title);
  List<SlashArgCandidate> sessionArgCandidates(
    List<String> prior,
    String partial,
  );
}

abstract interface class ShareCommandController {
  String shareAction(List<String> args);
  List<SlashArgCandidate> shareArgCandidates(
    List<String> prior,
    String partial,
  );
}

abstract interface class SkillsCommandController {
  void openSkillsPanel();
  String activateSkillByName(String skillName);
  List<SlashArgCandidate> skillsArgCandidates(
    List<String> prior,
    String partial,
  );
}

abstract interface class ProviderCommandController {
  String runProviderCommand(List<String> args);
  List<SlashArgCandidate> providerArgCandidates(
    List<String> prior,
    String partial,
  );
}

abstract interface class SlashCommandContext {
  SystemCommandController get system;
  ChatCommandController get chat;
  ModelCommandController get models;
  SessionCommandController get sessions;
  ShareCommandController get share;
  SkillsCommandController get skills;
  ProviderCommandController get providers;
}
