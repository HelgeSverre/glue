import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/prompts.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/file_sink.dart';
import 'package:glue/src/observability/http_trace_sink.dart';
import 'package:glue/src/observability/logging_http_client.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/otlp_http_trace_sink.dart';
import 'package:glue/src/providers/anthropic_adapter.dart';
import 'package:glue/src/providers/ollama_adapter.dart';
import 'package:glue/src/providers/copilot_adapter.dart';
import 'package:glue/src/providers/llm_client_factory.dart';
import 'package:glue/src/providers/openai_compatible_adapter.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/executor_factory.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/skills/skill_tool.dart';
import 'package:glue/src/storage/config_store.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/tools/subagent_tools.dart';
import 'package:glue/src/tools/web_browser_tool.dart';
import 'package:glue/src/tools/web_fetch_tool.dart';
import 'package:glue/src/tools/web_search_tool.dart';
import 'package:glue/src/web/browser/browser_config.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/browser/providers/anchor_provider.dart';
import 'package:glue/src/web/browser/providers/browserbase_provider.dart';
import 'package:glue/src/web/browser/providers/browserless_provider.dart';
import 'package:glue/src/web/browser/providers/docker_browser_provider.dart';
import 'package:glue/src/web/browser/providers/hyperbrowser_provider.dart';
import 'package:glue/src/web/browser/providers/local_provider.dart';
import 'package:glue/src/web/browser/providers/steel_provider.dart';
import 'package:glue/src/web/search/providers/brave_provider.dart';
import 'package:glue/src/web/search/providers/duckduckgo_provider.dart';
import 'package:glue/src/web/search/providers/firecrawl_provider.dart';
import 'package:glue/src/web/search/providers/tavily_provider.dart';
import 'package:glue/src/web/search/search_router.dart';
import 'package:http/http.dart' as http;

class ServiceLocator {
  static Future<AppServices> create({
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

    final debugController = DebugController(
      enabled: debug || config.observability.debug,
    );
    final obs = Observability(debugController: debugController);

    resolvedEnv.ensureDirectories();

    // Placeholder id used only for wiring subsystems (docker browser
    // container naming) at startup. The real session store is created
    // lazily by SessionManager either when resuming an existing session
    // or when the user sends their first message — see BUG-002.
    final startupSessionId = '${DateTime.now().millisecondsSinceEpoch}-'
        '${DateTime.now().microsecond.toRadixString(36)}';

    obs.addSink(FileSink(logsDir: resolvedEnv.logsDir));
    if (config.observability.otel.isConfigured) {
      obs.addSink(OtlpHttpTraceSink(config: config.observability.otel));
      obs.startAutoFlush(const Duration(seconds: 5));
    }
    if (debugController.enabled) {
      obs.addSink(HttpTraceSink(logsDir: resolvedEnv.logsDir));
    }

    // When debug is on, wrap every outbound HTTP call in a LoggingHttpClient
    // so request/response bodies and timings land in the http trace log. When
    // off, producers use a plain http.Client with zero overhead.
    http.Client mkHttp(String spanKind) => debugController.enabled
        ? LoggingHttpClient(
            inner: http.Client(),
            observability: obs,
            spanKind: spanKind,
            maxBodyBytes: config.observability.maxBodyBytes,
          )
        : http.Client();

    // Rebuild the adapter registry with HTTP client factories routed through
    // observability. GlueConfig.load constructed plain adapters before obs
    // existed; we swap them here now that we can wrap.
    config.adapters = AdapterRegistry([
      AnthropicAdapter(requestClientFactory: () => mkHttp('llm.anthropic')),
      OpenAiCompatibleAdapter(requestClientFactory: () => mkHttp('llm.openai')),
      OllamaAdapter(requestClientFactory: () => mkHttp('llm.ollama')),
      CopilotAdapter(
        credentialStore: config.credentials,
        client: mkHttp('llm.copilot.auth'),
        requestClientFactory: () => mkHttp('llm.copilot'),
      ),
    ]);

    final llmFactory = LlmClientFactory(config);
    final llm = llmFactory.createFromConfig(systemPrompt: systemPrompt);

    final configStore = ConfigStore(resolvedEnv.configPath);

    final executor = await ExecutorFactory.create(
      shellConfig: config.shellConfig,
      dockerConfig: config.dockerConfig,
      cwd: resolvedEnv.cwd,
    );

    SearchRouter? searchRouter;
    SearchRouter getSearchRouter() => searchRouter ??= SearchRouter([
          BraveSearchProvider(
            apiKey: config.webConfig.search.braveApiKey,
            client: mkHttp('search.brave'),
          ),
          TavilySearchProvider(
            apiKey: config.webConfig.search.tavilyApiKey,
            client: mkHttp('search.tavily'),
          ),
          FirecrawlSearchProvider(
            apiKey: config.webConfig.search.firecrawlApiKey,
            baseUrl: config.webConfig.search.firecrawlBaseUrl ??
                'https://api.firecrawl.dev',
            client: mkHttp('search.firecrawl'),
          ),
          DuckDuckGoSearchProvider(client: mkHttp('search.duckduckgo')),
        ]);

    BrowserManager? browserManager;
    BrowserManager getBrowserManager() => browserManager ??= BrowserManager(
          provider: switch (config.webConfig.browser.backend) {
            BrowserBackend.local => LocalProvider(config.webConfig.browser),
            BrowserBackend.docker => DockerBrowserProvider(
                image: config.webConfig.browser.dockerImage,
                port: config.webConfig.browser.dockerPort,
                sessionId: startupSessionId,
              ),
            BrowserBackend.steel => SteelProvider(
                apiKey: config.webConfig.browser.steelApiKey,
                client: mkHttp('browser.steel'),
              ),
            BrowserBackend.browserbase => BrowserbaseProvider(
                apiKey: config.webConfig.browser.browserbaseApiKey,
                projectId: config.webConfig.browser.browserbaseProjectId,
                client: mkHttp('browser.browserbase'),
              ),
            BrowserBackend.browserless => BrowserlessProvider(
                apiKey: config.webConfig.browser.browserlessApiKey,
                baseUrl: config.webConfig.browser.browserlessBaseUrl ?? '',
              ),
            BrowserBackend.anchor => AnchorProvider(
                apiKey: config.webConfig.browser.anchorApiKey,
                client: mkHttp('browser.anchor'),
              ),
            BrowserBackend.hyperbrowser => HyperbrowserProvider(
                apiKey: config.webConfig.browser.hyperbrowserApiKey,
                client: mkHttp('browser.hyperbrowser'),
              ),
          },
        );

    final tools = <String, Tool>{
      'read_file': ReadFileTool(),
      'write_file': WriteFileTool(),
      'edit_file': EditFileTool(),
      'bash': BashTool(executor),
      'grep': GrepTool(),
      'list_directory': ListDirectoryTool(),
      'web_fetch': WebFetchTool(
        config.webConfig.fetch,
        pdfConfig: config.webConfig.pdf,
        httpClient: mkHttp('fetch.web'),
      ),
      'web_search': WebSearchTool.lazy(getSearchRouter),
      'web_browser': WebBrowserTool.lazy(getBrowserManager),
      'skill': SkillTool(skillRuntime),
    };

    final agent = AgentCore(
      llm: llm,
      tools: tools,
      modelId: config.activeModel.modelId,
      obs: obs,
    );
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
      environment: resolvedEnv,
      config: config,
      terminal: terminal,
      layout: layout,
      editor: editor,
      agent: agent,
      manager: manager,
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

  /// Null on startup. SessionManager creates the concrete store lazily —
  /// either on resume, or when the user sends their first message.
  final SessionStore? sessionStore;
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
    this.sessionStore,
    required this.executor,
    required this.jobManager,
    required this.obs,
    required this.debugController,
    required this.skillRuntime,
  });
}
