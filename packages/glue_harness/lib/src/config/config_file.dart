@MappableLib(caseStyle: CaseStyle.snakeCase)
library;

import 'package:dart_mappable/dart_mappable.dart';

part 'config_file.mapper.dart';

// ─── Raw YAML shape: every field nullable, snake_case — mirrors the YAML ───

@MappableClass(ignoreNull: true)
class ConfigFile with ConfigFileMappable {
  final String? activeModel;
  final String? smallModel;
  final Map<String, String>? profiles;
  final CatalogSectionConfig? catalog;
  final BashSectionConfig? bash;
  final ShellSectionConfig? shell;
  final DockerSectionConfig? docker;
  final WebSectionConfig? web;
  final ObservabilitySectionConfig? observability;
  final Map<String, dynamic>? mcp;
  final String? runtime;
  final SkillsSectionConfig? skills;
  final bool? titleGenerationEnabled;
  final bool? anthropicPromptCache;
  final String? approvalMode;

  const ConfigFile({
    this.activeModel,
    this.smallModel,
    this.profiles,
    this.catalog,
    this.bash,
    this.shell,
    this.docker,
    this.web,
    this.observability,
    this.mcp,
    this.runtime,
    this.skills,
    this.titleGenerationEnabled,
    this.anthropicPromptCache,
    this.approvalMode,
  });
}

@MappableClass()
class CatalogSectionConfig with CatalogSectionConfigMappable {
  final String? refresh;
  final String? remoteUrl;

  const CatalogSectionConfig({this.refresh, this.remoteUrl});
}

@MappableClass()
class BashSectionConfig with BashSectionConfigMappable {
  final int? maxLines;

  const BashSectionConfig({this.maxLines});
}

@MappableClass()
class ShellSectionConfig with ShellSectionConfigMappable {
  final String? executable;
  final String? mode;

  const ShellSectionConfig({this.executable, this.mode});
}

@MappableClass()
class DockerSectionConfig with DockerSectionConfigMappable {
  final bool? enabled;
  final String? image;
  final String? shell;
  final bool? fallbackToHost;
  final List<String>? mounts;

  const DockerSectionConfig({
    this.enabled,
    this.image,
    this.shell,
    this.fallbackToHost,
    this.mounts,
  });
}

@MappableClass()
class WebSectionConfig with WebSectionConfigMappable {
  final FetchSectionConfig? fetch;
  final SearchSectionConfig? search;
  final PdfSectionConfig? pdf;
  final BrowserSectionConfig? browser;

  const WebSectionConfig({this.fetch, this.search, this.pdf, this.browser});
}

@MappableClass()
class FetchSectionConfig with FetchSectionConfigMappable {
  final String? jinaApiKey;
  final bool? allowJinaFallback;
  final int? timeoutSeconds;
  final int? maxBytes;
  final int? maxTokens;

  const FetchSectionConfig({
    this.jinaApiKey,
    this.allowJinaFallback,
    this.timeoutSeconds,
    this.maxBytes,
    this.maxTokens,
  });
}

@MappableClass()
class SearchSectionConfig with SearchSectionConfigMappable {
  final String? provider;
  final String? braveApiKey;
  final String? tavilyApiKey;
  final String? firecrawlApiKey;
  final String? firecrawlBaseUrl;
  final int? timeoutSeconds;
  final int? maxResults;

  const SearchSectionConfig({
    this.provider,
    this.braveApiKey,
    this.tavilyApiKey,
    this.firecrawlApiKey,
    this.firecrawlBaseUrl,
    this.timeoutSeconds,
    this.maxResults,
  });
}

@MappableClass()
class PdfSectionConfig with PdfSectionConfigMappable {
  final String? mistralApiKey;
  final String? openaiApiKey;
  final String? ocrProvider;
  final int? maxBytes;
  final int? timeoutSeconds;
  final bool? enableOcrFallback;

  const PdfSectionConfig({
    this.mistralApiKey,
    this.openaiApiKey,
    this.ocrProvider,
    this.maxBytes,
    this.timeoutSeconds,
    this.enableOcrFallback,
  });
}

@MappableClass()
class BrowserSectionConfig with BrowserSectionConfigMappable {
  final String? backend;
  final bool? headed;
  final DockerBrowserSectionConfig? docker;
  final CredentialSectionConfig? steel;
  final BrowserbaseSectionConfig? browserbase;
  final BrowserlessSectionConfig? browserless;
  final CredentialSectionConfig? anchor;
  final CredentialSectionConfig? hyperbrowser;

  const BrowserSectionConfig({
    this.backend,
    this.headed,
    this.docker,
    this.steel,
    this.browserbase,
    this.browserless,
    this.anchor,
    this.hyperbrowser,
  });
}

@MappableClass()
class DockerBrowserSectionConfig with DockerBrowserSectionConfigMappable {
  final String? image;
  final int? port;

  const DockerBrowserSectionConfig({this.image, this.port});
}

@MappableClass()
class CredentialSectionConfig with CredentialSectionConfigMappable {
  final String? apiKey;

  const CredentialSectionConfig({this.apiKey});
}

@MappableClass()
class BrowserbaseSectionConfig with BrowserbaseSectionConfigMappable {
  final String? apiKey;
  final String? projectId;

  const BrowserbaseSectionConfig({this.apiKey, this.projectId});
}

@MappableClass()
class BrowserlessSectionConfig with BrowserlessSectionConfigMappable {
  final String? baseUrl;
  final String? apiKey;

  const BrowserlessSectionConfig({this.baseUrl, this.apiKey});
}

@MappableClass()
class ObservabilitySectionConfig with ObservabilitySectionConfigMappable {
  final bool? debug;
  final int? maxBodyBytes;
  final bool? redact;
  final OtelSectionConfig? otel;

  const ObservabilitySectionConfig({
    this.debug,
    this.maxBodyBytes,
    this.redact,
    this.otel,
  });
}

@MappableClass()
class OtelSectionConfig with OtelSectionConfigMappable {
  final bool? enabled;
  final String? endpoint;
  final Map<String, String>? headers;
  final String? serviceName;
  final Map<String, String>? resourceAttributes;
  final int? timeoutMilliseconds;

  const OtelSectionConfig({
    this.enabled,
    this.endpoint,
    this.headers,
    this.serviceName,
    this.resourceAttributes,
    this.timeoutMilliseconds,
  });
}

@MappableClass()
class SkillsSectionConfig with SkillsSectionConfigMappable {
  final List<String>? paths;

  const SkillsSectionConfig({this.paths});
}
