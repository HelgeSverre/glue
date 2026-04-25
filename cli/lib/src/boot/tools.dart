import 'package:glue/src/agent/subagents.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/boot/http.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/skills/skill_tool.dart';
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

Map<String, Tool> wireTools({
  required GlueConfig config,
  required CommandExecutor executor,
  required SkillRuntime skillRuntime,
  required String startupSessionId,
  required HttpClientFactory httpClient,
}) {
  SearchRouter? searchRouter;
  SearchRouter getSearchRouter() => searchRouter ??= SearchRouter([
        BraveSearchProvider(
          apiKey: config.webConfig.search.braveApiKey,
          client: httpClient('search.brave'),
        ),
        TavilySearchProvider(
          apiKey: config.webConfig.search.tavilyApiKey,
          client: httpClient('search.tavily'),
        ),
        FirecrawlSearchProvider(
          apiKey: config.webConfig.search.firecrawlApiKey,
          baseUrl: config.webConfig.search.firecrawlBaseUrl ??
              'https://api.firecrawl.dev',
          client: httpClient('search.firecrawl'),
        ),
        DuckDuckGoSearchProvider(client: httpClient('search.duckduckgo')),
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
              client: httpClient('browser.steel'),
            ),
          BrowserBackend.browserbase => BrowserbaseProvider(
              apiKey: config.webConfig.browser.browserbaseApiKey,
              projectId: config.webConfig.browser.browserbaseProjectId,
              client: httpClient('browser.browserbase'),
            ),
          BrowserBackend.browserless => BrowserlessProvider(
              apiKey: config.webConfig.browser.browserlessApiKey,
              baseUrl: config.webConfig.browser.browserlessBaseUrl ?? '',
            ),
          BrowserBackend.anchor => AnchorProvider(
              apiKey: config.webConfig.browser.anchorApiKey,
              client: httpClient('browser.anchor'),
            ),
          BrowserBackend.hyperbrowser => HyperbrowserProvider(
              apiKey: config.webConfig.browser.hyperbrowserApiKey,
              client: httpClient('browser.hyperbrowser'),
            ),
        },
      );

  return {
    'read_file': ReadFileTool(),
    'write_file': WriteFileTool(),
    'edit_file': EditFileTool(),
    'bash': BashTool(executor),
    'grep': GrepTool(),
    'list_directory': ListDirectoryTool(),
    'web_fetch': WebFetchTool(
      config.webConfig.fetch,
      pdfConfig: config.webConfig.pdf,
      httpClient: httpClient('fetch.web'),
    ),
    'web_search': WebSearchTool.lazy(getSearchRouter),
    'web_browser': WebBrowserTool.lazy(getBrowserManager),
    'skill': SkillTool(skillRuntime),
  };
}

void registerSubagentTools(Map<String, Tool> tools, Subagents subagents) {
  tools['spawn_subagent'] = SpawnSubagentTool(subagents);
  tools['spawn_parallel_subagents'] = SpawnParallelSubagentsTool(subagents);
}
