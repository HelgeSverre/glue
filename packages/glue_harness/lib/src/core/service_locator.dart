import 'package:glue_harness/src/agent/agent_core.dart';
import 'package:glue_harness/src/agent/agent_manager.dart';
import 'package:glue_harness/src/agent/prompts.dart';
import 'package:glue_harness/src/agent/tools.dart';
import 'package:glue_harness/src/config/glue_config.dart';
import 'package:glue_harness/src/core/environment.dart';
import 'package:glue_harness/src/agent/llm_factory.dart';
import 'package:glue_harness/src/observability/debug_controller.dart';
import 'package:glue_harness/src/observability/file_sink.dart';
import 'package:glue_harness/src/observability/http_trace_sink.dart';
import 'package:glue_harness/src/observability/logging_http_client.dart';
import 'package:glue_harness/src/observability/observability.dart';
import 'package:glue_harness/src/observability/otlp_http_trace_sink.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:glue_harness/src/agent/shell_job_manager.dart';
import 'package:glue_harness/src/skills/skill_runtime.dart';
import 'package:glue_harness/src/skills/skill_tool.dart';
import 'package:glue_harness/src/storage/config_store.dart';
import 'package:glue_harness/src/storage/session_store.dart';
import 'package:glue_harness/src/tools/subagent_tools.dart';
import 'package:glue_harness/src/tools/web_browser_tool.dart';
import 'package:glue_harness/src/tools/web_fetch_tool.dart';
import 'package:glue_harness/src/tools/web_search_tool.dart';
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
      AnthropicAdapter(
        requestClientFactory: () => mkHttp('llm.anthropic'),
        promptCacheEnabled: config.anthropicPromptCache,
      ),
      OpenAiCompatibleAdapter(requestClientFactory: () => mkHttp('llm.openai')),
      OllamaAdapter(requestClientFactory: () => mkHttp('llm.ollama')),
      CopilotAdapter(
        credentialStore: config.credentials,
        client: mkHttp('llm.copilot.auth'),
        requestClientFactory: () => mkHttp('llm.copilot'),
      ),
      GeminiProvider(requestClientFactory: () => mkHttp('llm.gemini')),
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

    // MCP pool — eager non-blocking connect. As each server completes
    // its handshake the pool emits a connected event; we mutate the
    // agent's tools map so subsequent turns see the new entries.
    // Native names are reserved (the snapshot is taken now, before the
    // pool subscribes, so MCP tools never overwrite a built-in).
    final reservedNames = tools.keys.toSet();
    final mcpPool = McpClientPool(
      config: config.mcp,
      credentials: config.credentials,
      reservedToolNames: reservedNames,
    );
    mcpPool.events.listen((event) {
      switch (event) {
        case McpPoolServerConnectedEvent(:final serverId):
          final server = mcpPool.server(serverId);
          if (server == null) return;
          for (final tool in server.tools) {
            tools[tool.name] = tool;
          }
        case McpPoolServerDisconnectedEvent(:final serverId):
          tools.removeWhere(
            (_, t) => t is McpTool && t.serverId == serverId,
          );
        case McpPoolToolListChangedEvent(:final serverId):
          final server = mcpPool.server(serverId);
          tools.removeWhere(
            (_, t) => t is McpTool && t.serverId == serverId,
          );
          if (server != null) {
            for (final tool in server.tools) {
              tools[tool.name] = tool;
            }
          }
        case McpPoolServerErrorEvent():
        case McpPoolServerAuthRequiredEvent():
          // Surface concerns — App listens to the same stream to render
          // system messages. The harness side just keeps the tools map
          // honest.
          break;
      }
    });
    if (config.mcp.hasAnyServer) {
      mcpPool.connectAll();
    }

    return AppServices(
      environment: resolvedEnv,
      config: config,
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
      mcpPool: mcpPool,
    );
  }
}

/// Harness-layer services constructed by [ServiceLocator].
///
/// Surface concerns (terminal, layout, line editor) are not bundled here —
/// the surface (e.g. `App.create`) constructs those itself. Keeping
/// [AppServices] surface-free is what lets `core/` stay below `surface/`
/// in the layered architecture (see `tool/check_layers.dart`).
class AppServices {
  final Environment environment;
  final GlueConfig config;
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

  /// Pool of connected MCP servers. Always present (empty when no
  /// servers are configured). App subscribes to [McpClientPool.events]
  /// for status messages; commands call into it for `/mcp list` etc.
  final McpClientPool mcpPool;

  const AppServices({
    required this.environment,
    required this.config,
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
    required this.mcpPool,
  });
}
