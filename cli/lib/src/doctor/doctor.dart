import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:glue/src/boot/providers.dart';
import 'package:glue/src/catalog/catalog_parser.dart';
import 'package:glue/src/commands/config_command.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/diagnostics/terminal_diagnostics.dart';
import 'package:glue/src/observability/observability_config.dart';
import 'package:glue/src/observability/otlp_http_trace_sink.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/terminal/styled.dart';

enum DoctorSeverity {
  ok,
  info,
  warning,
  error,
}

class DoctorFinding {
  const DoctorFinding({
    required this.severity,
    required this.section,
    required this.message,
    this.path,
  });

  final DoctorSeverity severity;
  final String section;
  final String message;
  final String? path;
}

class DoctorReport {
  const DoctorReport(this.findings);

  final List<DoctorFinding> findings;

  int get okCount =>
      findings.where((f) => f.severity == DoctorSeverity.ok).length;

  int get infoCount =>
      findings.where((f) => f.severity == DoctorSeverity.info).length;

  int get warningCount =>
      findings.where((f) => f.severity == DoctorSeverity.warning).length;

  int get errorCount =>
      findings.where((f) => f.severity == DoctorSeverity.error).length;

  bool get hasErrors => errorCount > 0;
}

/// Builder for the [AdapterRegistry] used by the verbose connectivity probe.
/// Defaults to the production registry; tests inject a fake to avoid network.
typedef DoctorAdaptersBuilder = AdapterRegistry Function(
  CredentialStore credentials,
);

AdapterRegistry _defaultAdaptersBuilder(CredentialStore credentials) {
  return wireProviderAdapters(
    credentials: credentials,
    httpClient: (_) => http.Client(),
  );
}

Future<DoctorReport> runDoctor(
  Environment environment, {
  bool verbose = false,
  DoctorAdaptersBuilder? adaptersBuilder,
}) async {
  final findings = <DoctorFinding>[];

  void add(
    String section,
    DoctorSeverity severity,
    String message, {
    String? path,
  }) {
    findings.add(DoctorFinding(
      section: section,
      severity: severity,
      message: message,
      path: path,
    ));
  }

  add('Environment', DoctorSeverity.ok, 'GLUE_HOME: ${environment.glueDir}');
  add('Environment', DoctorSeverity.ok, 'cwd: ${environment.cwd}');

  final term = TerminalDiagnostics.collect();
  final ttySev = (term.stdinHasTerminal && term.stdoutHasTerminal)
      ? DoctorSeverity.ok
      : DoctorSeverity.warning;
  add('Terminal', ttySev, term.verdict);
  for (final line in term.toReportLines().skip(1) /* verdict already added */) {
    add('Terminal', DoctorSeverity.info, line);
  }

  _checkPath(findings, 'Core files', 'config.yaml', environment.configYamlPath);
  _checkPath(
      findings, 'Core files', 'preferences.json', environment.configPath);
  _checkPath(
    findings,
    'Core files',
    'credentials.json',
    environment.credentialsPath,
  );
  _checkPath(findings, 'Core files', 'models.yaml', environment.modelsYamlPath);
  _checkPath(
    findings,
    'Core files',
    'sessions/',
    environment.sessionsDir,
    isDir: true,
  );
  _checkPath(findings, 'Core files', 'logs/', environment.logsDir, isDir: true);
  _checkPath(
    findings,
    'Core files',
    'cache/',
    environment.cacheDir,
    isDir: true,
  );

  _checkConfigYaml(findings, environment.configYamlPath);
  _checkJsonObject(findings, 'Preferences', environment.configPath);
  _checkCredentialsJson(findings, environment.credentialsPath);
  _checkCatalog(findings, 'Catalog', environment.modelsYamlPath);
  _checkCatalog(
    findings,
    'Catalog cache',
    p.join(environment.cacheDir, 'models.yaml'),
  );
  _checkConfigValidation(findings, environment);
  if (verbose) {
    await _probeConfiguredProviders(
      findings,
      environment,
      adaptersBuilder ?? _defaultAdaptersBuilder,
    );
  }
  _checkObservability(findings, environment);
  _checkSessions(findings, environment.sessionsDir);
  _checkTmpFiles(findings, environment.glueDir);

  return DoctorReport(findings);
}

String _marker(DoctorSeverity severity) {
  return switch (severity) {
    DoctorSeverity.ok => '✓'.styled.green.toString(),
    DoctorSeverity.info => '·'.styled.gray.toString(),
    DoctorSeverity.warning => '!'.styled.yellow.toString(),
    DoctorSeverity.error => '✗'.styled.red.toString(),
  };
}

String renderDoctorReport(DoctorReport report, {bool verbose = false}) {
  final buf = StringBuffer();
  buf.writeln(
    '${'●'.styled.rgb(250, 204, 21)} ${'Glue Doctor'.styled.bold}',
  );
  buf.writeln();

  final visible = verbose
      ? report.findings
      : report.findings
          .where((f) => f.severity != DoctorSeverity.info)
          .toList();

  String? currentSection;
  for (final finding in visible) {
    if (finding.section != currentSection) {
      if (currentSection != null) buf.writeln();
      currentSection = finding.section;
      buf.writeln(finding.section.styled.bold.toString());
    }
    final suffix = finding.path == null ? '' : '  ${finding.path!.styled.gray}';
    buf.writeln('  ${_marker(finding.severity)} ${finding.message}$suffix');
  }

  final hiddenInfo = report.infoCount - (verbose ? report.infoCount : 0);

  buf.writeln();
  buf.writeln('Summary'.styled.bold.toString());
  if (report.hasErrors || report.warningCount > 0) {
    buf.writeln(
      '  ${'${report.okCount} ok'.styled.green}  '
      '${'${report.warningCount} warn'.styled.yellow}  '
      '${'${report.errorCount} error'.styled.red}',
    );
  } else {
    buf.writeln(
      '  ${'✓ All checks passed'.styled.green}  '
      '${'(${report.okCount} ok)'.styled.gray}',
    );
  }
  if (hiddenInfo > 0) {
    buf.writeln(
      '  ${'$hiddenInfo info hidden — rerun with --verbose to show'.styled.gray}',
    );
  }
  return buf.toString();
}

void _checkPath(
  List<DoctorFinding> findings,
  String section,
  String label,
  String path, {
  bool isDir = false,
}) {
  final exists = isDir ? Directory(path).existsSync() : File(path).existsSync();
  findings.add(DoctorFinding(
    severity: exists ? DoctorSeverity.ok : DoctorSeverity.warning,
    section: section,
    message: exists ? '$label exists' : '$label missing',
    path: path,
  ));
}

void _checkConfigYaml(List<DoctorFinding> findings, String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml != null && yaml is! YamlMap) {
      findings.add(DoctorFinding(
        severity: DoctorSeverity.error,
        section: 'Config file',
        message: 'config.yaml root must be a mapping',
        path: path,
      ));
      return;
    }
    findings.add(DoctorFinding(
      severity: DoctorSeverity.ok,
      section: 'Config file',
      message: 'config.yaml parsed',
      path: path,
    ));
  } on Object catch (e) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.error,
      section: 'Config file',
      message: 'config.yaml parse failed: $e',
      path: path,
    ));
  }
}

void _checkJsonObject(
  List<DoctorFinding> findings,
  String section,
  String path,
) {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      findings.add(DoctorFinding(
        severity: DoctorSeverity.error,
        section: section,
        message: '${p.basename(path)} root must be an object',
        path: path,
      ));
      return;
    }
    findings.add(DoctorFinding(
      severity: DoctorSeverity.ok,
      section: section,
      message: '${p.basename(path)} parsed',
      path: path,
    ));
  } on Object catch (e) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.error,
      section: section,
      message: '${p.basename(path)} parse failed: $e',
      path: path,
    ));
  }
}

void _checkCredentialsJson(List<DoctorFinding> findings, String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      findings.add(DoctorFinding(
        severity: DoctorSeverity.error,
        section: 'Credentials',
        message: 'credentials.json root must be an object',
        path: path,
      ));
      return;
    }
    final providers = decoded['providers'];
    if (providers != null && providers is! Map) {
      findings.add(DoctorFinding(
        severity: DoctorSeverity.error,
        section: 'Credentials',
        message: 'credentials.json providers must be an object',
        path: path,
      ));
      return;
    }
    findings.add(DoctorFinding(
      severity: DoctorSeverity.ok,
      section: 'Credentials',
      message: 'credentials.json parsed',
      path: path,
    ));
  } on Object catch (e) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.error,
      section: 'Credentials',
      message: 'credentials.json parse failed: $e',
      path: path,
    ));
  }
}

void _checkCatalog(
  List<DoctorFinding> findings,
  String section,
  String path,
) {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    parseCatalogYaml(file.readAsStringSync());
    findings.add(DoctorFinding(
      severity: DoctorSeverity.ok,
      section: section,
      message: '${p.basename(path)} parsed',
      path: path,
    ));
  } on CatalogParseException catch (e) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.error,
      section: section,
      message: '${p.basename(path)} parse failed: ${e.message}',
      path: path,
    ));
  } on Object catch (e) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.error,
      section: section,
      message: '${p.basename(path)} parse failed: $e',
      path: path,
    ));
  }
}

void _checkConfigValidation(
  List<DoctorFinding> findings,
  Environment environment,
) {
  final result = validateUserConfig(environment);
  findings.add(DoctorFinding(
    severity: result.ok ? DoctorSeverity.ok : DoctorSeverity.error,
    section: 'Config validation',
    message: result.message,
    path: environment.configYamlPath,
  ));
}

/// Probes every configured provider in parallel and emits one
/// [DoctorFinding] per provider. Only invoked when `--verbose` is set —
/// keeps the fast-path under a second.
///
/// "Configured" means [ProviderAdapter.isConnected] returns true: env var
/// resolves, credential is stored, or the provider is [AuthKind.none] (local
/// LLMs). Catalog drift (`unknownAdapter`) and missing credentials are
/// already surfaced by the earlier `_checkConfigValidation` row.
Future<void> _probeConfiguredProviders(
  List<DoctorFinding> findings,
  Environment environment,
  DoctorAdaptersBuilder adaptersBuilder,
) async {
  const section = 'Provider connectivity';
  GlueConfig config;
  try {
    config = GlueConfig.load(environment: environment);
  } on Object catch (e) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.info,
      section: section,
      message: 'skipped: config did not load ($e)',
    ));
    return;
  }

  final registry = adaptersBuilder(config.credentials);
  final probes = <Future<DoctorFinding>>[];
  for (final def in config.catalogData.providers.values) {
    final adapter = registry.lookup(def.adapter);
    if (adapter == null) continue;
    if (!adapter.isConnected(def, config.credentials)) continue;
    final resolved = config.resolveProviderById(def.id);
    probes.add(adapter.probe(resolved).then((health) {
      return DoctorFinding(
        severity: _severityFor(health),
        section: section,
        message: '${def.name}: ${_statusLabel(health)}',
      );
    }));
  }

  if (probes.isEmpty) {
    findings.add(const DoctorFinding(
      severity: DoctorSeverity.info,
      section: section,
      message: 'no configured providers to probe',
    ));
    return;
  }

  final rows = await Future.wait(probes);
  rows.sort((a, b) => a.message.compareTo(b.message));
  findings.addAll(rows);
}

DoctorSeverity _severityFor(ProviderHealth health) {
  return switch (health) {
    ProviderHealth.ok => DoctorSeverity.ok,
    ProviderHealth.unauthorized => DoctorSeverity.error,
    ProviderHealth.unreachable => DoctorSeverity.info,
    ProviderHealth.unknownAdapter => DoctorSeverity.warning,
    ProviderHealth.missingCredential => DoctorSeverity.info,
  };
}

String _statusLabel(ProviderHealth health) {
  return switch (health) {
    ProviderHealth.ok => 'ok',
    ProviderHealth.unauthorized => 'credentials rejected',
    ProviderHealth.unreachable => 'unreachable',
    ProviderHealth.unknownAdapter => 'no adapter',
    ProviderHealth.missingCredential => 'not connected',
  };
}

void _checkObservability(
  List<DoctorFinding> findings,
  Environment environment,
) {
  // Pull effective observability settings from the loaded config when possible.
  // If the config cannot be loaded (e.g. legacy-shape YAML), fall back to the
  // default observability settings so the section still renders useful paths.
  ObservabilityConfig observability;
  try {
    final config = GlueConfig.load(environment: environment);
    observability = config.observability;
  } on Object {
    observability = const ObservabilityConfig();
  }

  const section = 'Observability';
  final logsDir = environment.logsDir;

  findings.add(DoctorFinding(
    severity: DoctorSeverity.info,
    section: section,
    message: 'debug: ${observability.debug ? 'on' : 'off'}',
  ));

  findings.add(DoctorFinding(
    severity: DoctorSeverity.info,
    section: section,
    message: 'Log directory: $logsDir',
    path: logsDir,
  ));

  final otel = observability.otel;
  findings.add(DoctorFinding(
    severity: otel.isConfigured ? DoctorSeverity.ok : DoctorSeverity.info,
    section: section,
    message: otel.isConfigured
        ? 'OTEL export: on (${normalizeOtlpTracesEndpoint(otel.endpoint!)})'
        : 'OTEL export: off',
  ));
  if (otel.isConfigured) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.info,
      section: section,
      message: 'OTEL service: ${otel.serviceName}',
    ));
    findings.add(DoctorFinding(
      severity: DoctorSeverity.info,
      section: section,
      message: 'OTEL headers: ${redactOtelHeadersForDisplay(otel.headers)}',
    ));
  }

  final latestSpanLog = _latestLogFile(logsDir, 'spans-', '.jsonl');
  findings.add(DoctorFinding(
    severity: DoctorSeverity.info,
    section: section,
    message: latestSpanLog == null
        ? 'no recent span logs'
        : 'Recent span log: ${p.basename(latestSpanLog)}',
    path: latestSpanLog,
  ));

  if (observability.debug) {
    final latestHttpLog = _latestLogFile(logsDir, 'http-', '.jsonl');
    findings.add(DoctorFinding(
      severity: DoctorSeverity.info,
      section: section,
      message: latestHttpLog == null
          ? 'no recent http logs'
          : 'Recent http log: ${p.basename(latestHttpLog)}',
      path: latestHttpLog,
    ));
  }

  findings.add(DoctorFinding(
    severity: DoctorSeverity.info,
    section: section,
    message: 'Body cap: ${observability.maxBodyBytes} bytes',
  ));

  findings.add(DoctorFinding(
    severity:
        observability.redact ? DoctorSeverity.info : DoctorSeverity.warning,
    section: section,
    message: observability.redact
        ? 'Redaction: enabled'
        : 'Redaction: disabled — debug logs may contain secrets',
  ));
}

/// Returns the absolute path of the most recently modified file in [dir]
/// whose name starts with [prefix] and ends with [suffix], or `null` when
/// the directory is missing or no matching file exists.
String? _latestLogFile(String dir, String prefix, String suffix) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return null;
  File? newest;
  DateTime? newestMtime;
  for (final entry in directory.listSync()) {
    if (entry is! File) continue;
    final name = p.basename(entry.path);
    if (!name.startsWith(prefix) || !name.endsWith(suffix)) continue;
    final mtime = entry.statSync().modified;
    if (newestMtime == null || mtime.isAfter(newestMtime)) {
      newest = entry;
      newestMtime = mtime;
    }
  }
  return newest?.path;
}

void _checkSessions(List<DoctorFinding> findings, String sessionsDir) {
  final dir = Directory(sessionsDir);
  if (!dir.existsSync()) return;

  final sessionDirs = dir.listSync().whereType<Directory>().toList();
  findings.add(DoctorFinding(
    severity: DoctorSeverity.ok,
    section: 'Sessions',
    message: 'scanned ${sessionDirs.length} session directories',
    path: sessionsDir,
  ));

  for (final sessionDir in sessionDirs) {
    final metaPath = p.join(sessionDir.path, 'meta.json');
    final conversationPath = p.join(sessionDir.path, 'conversation.jsonl');
    _checkSessionMeta(findings, metaPath);
    _checkConversationJsonl(findings, conversationPath);
  }
}

void _checkSessionMeta(List<DoctorFinding> findings, String path) {
  final file = File(path);
  if (!file.existsSync()) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.error,
      section: 'Sessions',
      message: 'meta.json missing',
      path: path,
    ));
    return;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      findings.add(DoctorFinding(
        severity: DoctorSeverity.error,
        section: 'Sessions',
        message: 'meta.json root must be an object',
        path: path,
      ));
      return;
    }
    for (final key in ['id', 'cwd', 'start_time']) {
      if (!decoded.containsKey(key)) {
        findings.add(DoctorFinding(
          severity: DoctorSeverity.error,
          section: 'Sessions',
          message: 'meta.json missing required key "$key"',
          path: path,
        ));
        return;
      }
    }
  } on Object catch (e) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.error,
      section: 'Sessions',
      message: 'meta.json parse failed: $e',
      path: path,
    ));
  }
}

void _checkConversationJsonl(List<DoctorFinding> findings, String path) {
  final file = File(path);
  if (!file.existsSync()) {
    findings.add(DoctorFinding(
      severity: DoctorSeverity.info,
      section: 'Sessions',
      message: 'conversation.jsonl missing',
      path: path,
    ));
    return;
  }
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        findings.add(DoctorFinding(
          severity: DoctorSeverity.error,
          section: 'Sessions',
          message: 'conversation.jsonl line ${i + 1} is not an object',
          path: path,
        ));
        return;
      }
      if (!decoded.containsKey('type')) {
        findings.add(DoctorFinding(
          severity: DoctorSeverity.error,
          section: 'Sessions',
          message: 'conversation.jsonl line ${i + 1} missing type',
          path: path,
        ));
        return;
      }
    } on Object catch (e) {
      findings.add(DoctorFinding(
        severity: DoctorSeverity.error,
        section: 'Sessions',
        message: 'conversation.jsonl line ${i + 1} parse failed: $e',
        path: path,
      ));
      return;
    }
  }
}

void _checkTmpFiles(List<DoctorFinding> findings, String glueDir) {
  final dir = Directory(glueDir);
  if (!dir.existsSync()) return;
  for (final entry in dir.listSync(recursive: true)) {
    if (!entry.path.endsWith('.tmp')) continue;
    findings.add(DoctorFinding(
      severity: DoctorSeverity.warning,
      section: 'Filesystem',
      message: 'orphaned tmp file',
      path: entry.path,
    ));
  }
}
