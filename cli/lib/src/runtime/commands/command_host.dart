import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/skills/skill_runtime.dart';

abstract interface class SystemCommandController {
  void openHelpPanel();
  void requestExit();
  String toggleDebug();
  String pathsReport();
  String openGlueTarget(List<String> args);
  String configAction(List<String> args);
}

abstract interface class ChatCommandController {
  String clearConversation();
  String listTools();
  String toggleApproval();
  void copyLastResponse();
}

abstract interface class ModelCommandController {
  void openModelPanel();
  String switchModelByQuery(String query);
}

abstract interface class SessionCommandController {
  String sessionAction(List<String> args);
  void openHistoryPanel();
  String historyActionByQuery(String query);
  void openResumePanel();
  String resumeSessionByQuery(String query);
  String renameSession(String title);
}

abstract interface class ShareCommandController {
  String shareAction(List<String> args);
}

abstract interface class SkillsCommandController {
  void openSkillsPanel();
  String activateSkillByName(String skillName);
}

abstract interface class ProviderCommandController {
  String runProviderCommand(List<String> args);
}

abstract interface class SlashCommandContext {
  SystemCommandController get system;
  ChatCommandController get chat;
  ModelCommandController get models;
  SessionCommandController get sessions;
  ShareCommandController get share;
  SkillsCommandController get skills;
  ProviderCommandController get providers;

  /// Live config handle for arg-completer factories that read the
  /// catalog (e.g. `/model`, `/provider`). Controllers already hold
  /// their own references — this is exposed for closures registered
  /// in `attachArgCompleters()`.
  Config get config;

  /// Live skill registry for the `/skills` arg completer.
  SkillRuntime get skillRuntime;
}
