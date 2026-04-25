import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/subagents.dart';
import 'package:glue/src/agent/prompts.dart';
import 'package:glue/src/app.dart';
import 'package:glue/src/boot/observability.dart';
import 'package:glue/src/boot/providers.dart';
import 'package:glue/src/boot/tools.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/providers/llm_client_factory.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/executor_factory.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/storage/config_store.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';

Future<App> wireApp({
  String? model,
  String? prompt,
  bool printMode = false,
  bool jsonMode = false,
  String? resumeSessionId,
  bool startupContinue = false,
  bool debug = false,
  Environment? environment,
}) async {
  final context = await wireAppContext(
    model: model,
    debug: debug,
    environment: environment,
  );

  return context.createApp(
    prompt: prompt,
    printMode: printMode,
    jsonMode: jsonMode,
    resumeSessionId: resumeSessionId,
    startupContinue: startupContinue,
  );
}

Future<AppContext> wireAppContext({
  String? model,
  bool debug = false,
  Environment? environment,
}) async {
  final resolvedEnv = environment ?? Environment.detect();
  final config = GlueConfig.load(cliModel: model, environment: resolvedEnv);
  config.validate();

  final terminal = Terminal();
  final layout = Layout(terminal);
  final editor = TextAreaEditor();

  final skillRuntime = SkillRuntime(
    cwd: resolvedEnv.cwd,
    extraPathsProvider: () => config.skillPaths,
    environment: resolvedEnv,
  );

  final systemPrompt = Prompts.build(
    cwd: resolvedEnv.cwd,
    skills: skillRuntime.list(),
  );

  resolvedEnv.ensureDirectories();

  final observability = wireObservability(
    config: config,
    environment: resolvedEnv,
    debug: debug,
  );
  final obs = observability.observability;
  final debugController = observability.debugController;

  // Placeholder id used only for wiring subsystems (docker browser
  // container naming) at startup. The real session store is created
  // lazily by SessionManager either when resuming an existing session
  // or when the user sends their first message — see BUG-002.
  final startupSessionId = '${DateTime.now().millisecondsSinceEpoch}-'
      '${DateTime.now().microsecond.toRadixString(36)}';

  // Rebuild the adapter registry with HTTP client factories routed through
  // observability. GlueConfig.load constructed plain adapters before obs
  // existed; we swap them here now that we can wrap.
  config.adapters = wireProviderAdapters(
    credentials: config.credentials,
    httpClient: observability.httpClient,
  );

  final llmFactory = LlmClientFactory(config);
  final llm = llmFactory.createFromConfig(systemPrompt: systemPrompt);

  final configStore = ConfigStore(resolvedEnv.configPath);

  final executor = await ExecutorFactory.create(
    shellConfig: config.shellConfig,
    dockerConfig: config.dockerConfig,
    cwd: resolvedEnv.cwd,
  );

  final tools = wireTools(
    config: config,
    executor: executor,
    skillRuntime: skillRuntime,
    startupSessionId: startupSessionId,
    httpClient: observability.httpClient,
  );

  final agent = Agent(
    llm: llm,
    tools: tools,
    modelId: config.activeModel.modelId,
    obs: obs,
  );
  final subagents = Subagents(
    tools: tools,
    llmFactory: llmFactory,
    config: config,
    systemPrompt: systemPrompt,
    obs: obs,
  );
  registerSubagentTools(tools, subagents);

  return AppContext(
    environment: resolvedEnv,
    config: config,
    terminal: terminal,
    layout: layout,
    editor: editor,
    agent: agent,
    subagents: subagents,
    llmFactory: llmFactory,
    systemPrompt: systemPrompt,
    trustedTools: configStore.trustedTools.toSet(),
    executor: executor,
    jobManager: ShellJobManager(executor, obs: obs),
    obs: obs,
    debugController: debugController,
    skillRuntime: skillRuntime,
  );
}

class AppContext {
  final Environment environment;
  final GlueConfig config;
  final Terminal terminal;
  final Layout layout;
  final TextAreaEditor editor;
  final Agent agent;
  final Subagents subagents;
  final LlmClientFactory llmFactory;
  final String systemPrompt;
  final Set<String> trustedTools;

  /// Null on startup. SessionManager creates the concrete store lazily —
  /// either on resume, or when the user sends their first message.
  final SessionStore? sessionStore;
  final CommandExecutor executor;
  final ShellJobManager jobManager;
  final Observability obs;
  final DebugController debugController;
  final SkillRuntime skillRuntime;

  const AppContext({
    required this.environment,
    required this.config,
    required this.terminal,
    required this.layout,
    required this.editor,
    required this.agent,
    required this.subagents,
    required this.llmFactory,
    required this.systemPrompt,
    required this.trustedTools,
    this.sessionStore,
    required this.executor,
    required this.jobManager,
    required this.obs,
    required this.debugController,
    required this.skillRuntime,
  });

  App createApp({
    String? prompt,
    bool printMode = false,
    bool jsonMode = false,
    String? resumeSessionId,
    bool startupContinue = false,
  }) {
    return App(
      terminal: terminal,
      layout: layout,
      editor: editor,
      agent: agent,
      modelId: config.activeModel.modelId,
      subagents: subagents,
      llmFactory: llmFactory,
      config: config,
      systemPrompt: systemPrompt,
      extraTrustedTools: trustedTools,
      sessionStore: sessionStore,
      executor: executor,
      jobManager: jobManager,
      startupContinue: startupContinue,
      startupPrompt: prompt,
      printMode: printMode,
      jsonMode: jsonMode,
      resumeSessionId: resumeSessionId,
      obs: obs,
      debugController: debugController,
      skillRuntime: skillRuntime,
      environment: environment,
    );
  }
}
