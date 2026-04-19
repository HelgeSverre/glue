import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/prompts.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/file_sink.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/executor_factory.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/skills/skill_tool.dart';
import 'package:glue/src/storage/config_store.dart';
import 'package:glue/src/storage/session_state.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/tools/subagent_tools.dart';
import 'package:glue/src/tools/web_browser_tool.dart';
import 'package:glue/src/tools/web_fetch_tool.dart';
import 'package:glue/src/tools/web_search_tool.dart';
import 'package:glue/src/web/browser/browser_config.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/browser/providers/browserbase_provider.dart';
import 'package:glue/src/web/browser/providers/browserless_provider.dart';
import 'package:glue/src/web/browser/providers/docker_browser_provider.dart';
import 'package:glue/src/web/browser/providers/local_provider.dart';
import 'package:glue/src/web/browser/providers/steel_provider.dart';
import 'package:glue/src/web/search/providers/brave_provider.dart';
import 'package:glue/src/web/search/providers/firecrawl_provider.dart';
import 'package:glue/src/web/search/providers/tavily_provider.dart';
import 'package:glue/src/web/search/search_router.dart';

class ServiceLocator {
  static Future<AppServices> create({
    String? model,
    bool debug = false,
  }) async {
    final environment = Environment.detect();
    final config = GlueConfig.load(cliModel: model, environment: environment);
    config.validate();

    final terminal = Terminal();
    final layout = Layout(terminal);
    final editor = TextAreaEditor();

    final skillRuntime = SkillRuntime(
      cwd: environment.cwd,
      extraPathsProvider: () => config.skillPaths,
      environment: environment,
    );

    final systemPrompt = Prompts.build(
      cwd: environment.cwd,
      skills: skillRuntime.list(),
    );

    final debugController = DebugController(
      enabled: debug || config.observability.debug,
    );
    final obs = Observability(debugController: debugController);

    environment.ensureDirectories();

    final sessionId = '${DateTime.now().millisecondsSinceEpoch}-'
        '${DateTime.now().microsecond.toRadixString(36)}';

    obs.addSink(FileSink(logsDir: environment.logsDir));

    final llmFactory = LlmClientFactory(config);
    final llm = llmFactory.createFromConfig(systemPrompt: systemPrompt);

    final configStore = ConfigStore(environment.configPath);

    final sessionDir = environment.sessionDir(sessionId);
    final sessionMeta = SessionMeta(
      id: sessionId,
      cwd: environment.cwd,
      modelRef: config.activeModel.toString(),
      startTime: DateTime.now(),
    );
    final sessionStore =
        SessionStore(sessionDir: sessionDir, meta: sessionMeta);
    final sessionState = SessionState.load(sessionDir);
    final executor = await ExecutorFactory.create(
      shellConfig: config.shellConfig,
      dockerConfig: config.dockerConfig,
      cwd: environment.cwd,
      sessionMounts: sessionState.dockerMounts,
    );

    final searchRouter = SearchRouter([
      BraveSearchProvider(apiKey: config.webConfig.search.braveApiKey),
      TavilySearchProvider(apiKey: config.webConfig.search.tavilyApiKey),
      FirecrawlSearchProvider(
        apiKey: config.webConfig.search.firecrawlApiKey,
        baseUrl: config.webConfig.search.firecrawlBaseUrl ??
            'https://api.firecrawl.dev',
      ),
    ]);

    final browserProvider = switch (config.webConfig.browser.backend) {
      BrowserBackend.local => LocalProvider(config.webConfig.browser),
      BrowserBackend.docker => DockerBrowserProvider(
          image: config.webConfig.browser.dockerImage,
          port: config.webConfig.browser.dockerPort,
          sessionId: sessionId,
        ),
      BrowserBackend.steel => SteelProvider(
          apiKey: config.webConfig.browser.steelApiKey,
        ),
      BrowserBackend.browserbase => BrowserbaseProvider(
          apiKey: config.webConfig.browser.browserbaseApiKey,
          projectId: config.webConfig.browser.browserbaseProjectId,
        ),
      BrowserBackend.browserless => BrowserlessProvider(
          apiKey: config.webConfig.browser.browserlessApiKey,
          baseUrl: config.webConfig.browser.browserlessBaseUrl ?? '',
        ),
    };
    final browserManager = BrowserManager(provider: browserProvider);

    final tools = <String, Tool>{
      'read_file': ReadFileTool(),
      'write_file': WriteFileTool(),
      'edit_file': EditFileTool(),
      'bash': BashTool(executor),
      'grep': GrepTool(),
      'list_directory': ListDirectoryTool(),
      'web_fetch':
          WebFetchTool(config.webConfig.fetch, pdfConfig: config.webConfig.pdf),
      'web_search': WebSearchTool(searchRouter),
      'web_browser': WebBrowserTool(browserManager),
      'skill': SkillTool(skillRuntime),
    };

    final agent =
        AgentCore(llm: llm, tools: tools, modelId: config.activeModel.modelId);
    final manager = AgentManager(
      tools: tools,
      llmFactory: llmFactory,
      config: config,
      systemPrompt: systemPrompt,
      obs: obs,
    );
    tools['spawn_subagent'] = SpawnSubagentTool(manager);
    tools['spawn_parallel_subagents'] = SpawnParallelSubagentsTool(manager);

    return AppServices(
      environment: environment,
      config: config,
      terminal: terminal,
      layout: layout,
      editor: editor,
      agent: agent,
      manager: manager,
      llmFactory: llmFactory,
      systemPrompt: systemPrompt,
      trustedTools: configStore.trustedTools.toSet(),
      sessionStore: sessionStore,
      sessionState: sessionState,
      executor: executor,
      jobManager: ShellJobManager(executor),
      obs: obs,
      debugController: debugController,
      skillRuntime: skillRuntime,
    );
  }
}

class AppServices {
  final Environment environment;
  final GlueConfig config;
  final Terminal terminal;
  final Layout layout;
  final TextAreaEditor editor;
  final AgentCore agent;
  final AgentManager manager;
  final LlmClientFactory llmFactory;
  final String systemPrompt;
  final Set<String> trustedTools;
  final SessionStore sessionStore;
  final SessionState sessionState;
  final CommandExecutor executor;
  final ShellJobManager jobManager;
  final Observability obs;
  final DebugController debugController;
  final SkillRuntime skillRuntime;

  const AppServices({
    required this.environment,
    required this.config,
    required this.terminal,
    required this.layout,
    required this.editor,
    required this.agent,
    required this.manager,
    required this.llmFactory,
    required this.systemPrompt,
    required this.trustedTools,
    required this.sessionStore,
    required this.sessionState,
    required this.executor,
    required this.jobManager,
    required this.obs,
    required this.debugController,
    required this.skillRuntime,
  });
}
