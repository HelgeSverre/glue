import 'package:glue/src/runtime/controllers/chat_controller.dart';
import 'package:glue/src/runtime/controllers/model_controller.dart';
import 'package:glue/src/runtime/controllers/provider_controller.dart';
import 'package:glue/src/runtime/controllers/session_controller.dart';
import 'package:glue/src/runtime/controllers/skills_controller.dart';
import 'package:glue/src/runtime/controllers/system_controller.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/share/share_controller.dart';
import 'package:glue/src/skills/skill_runtime.dart';

/// Façade handed to [SlashCommandModule.register] / [attachArgCompleters].
/// Groups the controllers + services a module needs in one place so modules
/// don't have to declare each dependency individually.
abstract interface class SlashCommandContext {
  SystemController get system;
  ChatController get chat;
  ModelController get models;
  SessionController get sessions;
  ShareController get share;
  SkillsController get skills;
  ProviderController get providers;

  /// Live config handle for arg-completer factories that read the
  /// catalog (e.g. `/model`, `/provider`).
  Config get config;

  /// Live skill registry for the `/skills` arg completer.
  SkillRuntime get skillRuntime;
}
