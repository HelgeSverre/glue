import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:glue/src/commands/config_command.dart';
import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/tty_style.dart';

enum DoctorSeverity { ok, info, warning, error }

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

/// Single finding-sink: every section routes its findings through this
/// so the `DoctorFinding(...)` constructor isn't hand-rolled at ~50 call
/// sites. Keeps the (section, severity, message, path) tuple shape — the
/// thing tests assert on — in one place.
void _add(
  List<DoctorFinding> findings,
  String section,
  DoctorSeverity severity,
  String message, {
  String? path,
}) {
  findings.add(
    DoctorFinding(
      section: section,
      severity: severity,
      message: message,
      path: path,
    ),
  );
}

DoctorReport runDoctor(Environment environment) {
  final findings = <DoctorFinding>[];

  void add(
    String section,
    DoctorSeverity severity,
    String message, {
    String? path,
  }) => _add(findings, section, severity, message, path: path);

  add('Environment', DoctorSeverity.ok, 'GLUE_HOME: ${environment.glueDir}');
  add('Environment', DoctorSeverity.ok, 'cwd: ${environment.cwd}');

  _checkPath(findings, 'Core files', 'config.yaml', environment.configYamlPath);
  _checkPath(
    findings,
    'Core files',
    'preferences.json',
    environment.configPath,
  );
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
  _checkCatalog(findings, 'Catalog cache', environment.catalogCachePath);
  _checkConfigValidation(findings, environment);
  _checkObservability(findings, environment);
  _checkAgentModelTools(findings, environment);
  _checkRuntime(findings, environment);
  _checkSessions(findings, environment.sessionsDir);
  _checkTmpFiles(findings, environment.glueDir);

  return DoctorReport(findings);
}

String _marker(DoctorSeverity severity) {
  return switch (severity) {
    DoctorSeverity.ok => markerOk,
    DoctorSeverity.info => markerInfo,
    DoctorSeverity.warning => markerWarn,
    DoctorSeverity.error => markerError,
  };
}

String renderDoctorReport(DoctorReport report, {bool verbose = false}) {
  final buf = StringBuffer();
  buf.writeln('$brandDot ${styledOrPlain('Glue Doctor', (s) => s.bold)}');
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
      buf.writeln(styledOrPlain(finding.section, (s) => s.bold));
    }
    final suffix = finding.path == null
        ? ''
        : '  ${styledOrPlain(finding.path!, (s) => s.gray)}';
    buf.writeln('  ${_marker(finding.severity)} ${finding.message}$suffix');
  }

  final hiddenInfo = report.infoCount - (verbose ? report.infoCount : 0);

  buf.writeln();
  buf.writeln(styledOrPlain('Summary', (s) => s.bold));
  if (report.hasErrors || report.warningCount > 0) {
    buf.writeln(
      '  ${styledOrPlain('${report.okCount} ok', (s) => s.green)}  '
      '${styledOrPlain('${report.warningCount} warn', (s) => s.yellow)}  '
      '${styledOrPlain('${report.errorCount} error', (s) => s.red)}',
    );
  } else {
    buf.writeln(
      '  ${styledOrPlain('✓ All checks passed', (s) => s.green)}  '
      '${styledOrPlain('(${report.okCount} ok)', (s) => s.gray)}',
    );
  }
  if (hiddenInfo > 0) {
    buf.writeln(
      '  ${styledOrPlain('$hiddenInfo info hidden — rerun with --verbose to show', (s) => s.gray)}',
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
  _add(
    findings,
    section,
    exists ? DoctorSeverity.ok : DoctorSeverity.warning,
    exists ? '$label exists' : '$label missing',
    path: path,
  );
}

void _checkConfigYaml(List<DoctorFinding> findings, String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml != null && yaml is! YamlMap) {
      _add(
        findings,
        'Config file',
        DoctorSeverity.error,
        'config.yaml root must be a mapping',
        path: path,
      );
      return;
    }
    _add(
      findings,
      'Config file',
      DoctorSeverity.ok,
      'config.yaml parsed',
      path: path,
    );
  } on Object catch (e) {
    _add(
      findings,
      'Config file',
      DoctorSeverity.error,
      'config.yaml parse failed: $e',
      path: path,
    );
  }
}

/// Reads [path], decodes it as JSON, and asserts the root is an object.
///
/// Returns the decoded [Map] on success. On a parse error or a
/// non-object root it adds the appropriate `error` finding under
/// [section] (using `<basename> root must be an object` /
/// `<basename> parse failed: …`) and returns `null`. Callers that have
/// already established the file exists pass it straight through; the
/// shared messages keep the three JSON-object validators in lockstep.
Map<dynamic, dynamic>? _parseJsonObject(
  List<DoctorFinding> findings,
  String section,
  String path,
) {
  try {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map) {
      _add(
        findings,
        section,
        DoctorSeverity.error,
        '${p.basename(path)} root must be an object',
        path: path,
      );
      return null;
    }
    return decoded;
  } on Object catch (e) {
    _add(
      findings,
      section,
      DoctorSeverity.error,
      '${p.basename(path)} parse failed: $e',
      path: path,
    );
    return null;
  }
}

void _checkJsonObject(
  List<DoctorFinding> findings,
  String section,
  String path,
) {
  if (!File(path).existsSync()) return;
  if (_parseJsonObject(findings, section, path) == null) return;
  _add(
    findings,
    section,
    DoctorSeverity.ok,
    '${p.basename(path)} parsed',
    path: path,
  );
}

void _checkCredentialsJson(List<DoctorFinding> findings, String path) {
  if (!File(path).existsSync()) return;
  final decoded = _parseJsonObject(findings, 'Credentials', path);
  if (decoded == null) return;
  final providers = decoded['providers'];
  if (providers != null && providers is! Map) {
    _add(
      findings,
      'Credentials',
      DoctorSeverity.error,
      'credentials.json providers must be an object',
      path: path,
    );
    return;
  }
  _add(
    findings,
    'Credentials',
    DoctorSeverity.ok,
    'credentials.json parsed',
    path: path,
  );
}

void _checkCatalog(List<DoctorFinding> findings, String section, String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    parseCatalogYaml(file.readAsStringSync());
    _add(
      findings,
      section,
      DoctorSeverity.ok,
      '${p.basename(path)} parsed',
      path: path,
    );
  } on CatalogParseException catch (e) {
    _add(
      findings,
      section,
      DoctorSeverity.error,
      '${p.basename(path)} parse failed: ${e.message}',
      path: path,
    );
  } on Object catch (e) {
    _add(
      findings,
      section,
      DoctorSeverity.error,
      '${p.basename(path)} parse failed: $e',
      path: path,
    );
  }
}

void _checkConfigValidation(
  List<DoctorFinding> findings,
  Environment environment,
) {
  final result = validateUserConfig(environment);
  _add(
    findings,
    'Config validation',
    result.ok ? DoctorSeverity.ok : DoctorSeverity.error,
    result.message,
    path: environment.configYamlPath,
  );
}

/// Catalog-only check: does the active model declare the `tools`
/// capability? When it doesn't, the agent loop will start in chat-only
/// mode (soft fallback in `ServiceLocator`). Surface as an info finding
/// — not an error — so `glue doctor` exits 0 and the user is just told
/// what to expect.
///
/// Uncatalogued tags fall through to the runtime catch in
/// `AgentCore` (`ToolsNotSupportedException` → same end state); doctor
/// stays silent for them since the catalog is the only source of truth
/// at diagnostic time.
void _checkAgentModelTools(
  List<DoctorFinding> findings,
  Environment environment,
) {
  GlueConfig config;
  try {
    config = GlueConfig.load(environment: environment);
  } on Object {
    // Config-load failures already surface in the Config validation
    // section above; don't double-report.
    return;
  }
  final ref = config.activeModel;
  final def = config.catalogData.providers[ref.providerId]?.models[ref.modelId];
  if (def == null || def.capabilities.isEmpty) return;
  if (def.capabilities.contains('tools')) return;
  _add(
    findings,
    'Agent model',
    DoctorSeverity.info,
    '$ref does not declare the "tools" capability — '
        'sessions will run in chat-only mode. '
        'Use /model to switch to a tool-capable model.',
  );
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
  void add(DoctorSeverity severity, String message, {String? path}) =>
      _add(findings, section, severity, message, path: path);

  add(DoctorSeverity.info, 'debug: ${observability.debug ? 'on' : 'off'}');
  add(DoctorSeverity.info, 'Log directory: $logsDir', path: logsDir);

  final otel = observability.otel;
  add(
    otel.isConfigured ? DoctorSeverity.ok : DoctorSeverity.info,
    otel.isConfigured
        ? 'OTEL export: on (${normalizeOtlpTracesEndpoint(otel.endpoint!)})'
        : 'OTEL export: off',
  );
  if (otel.isConfigured) {
    add(DoctorSeverity.info, 'OTEL service: ${otel.serviceName}');
    add(
      DoctorSeverity.info,
      'OTEL headers: ${redactOtelHeadersForDisplay(otel.headers)}',
    );
  }

  final latestSpanLog = _latestLogFile(logsDir, 'spans-', '.jsonl');
  add(
    DoctorSeverity.info,
    latestSpanLog == null
        ? 'no recent span logs'
        : 'Recent span log: ${p.basename(latestSpanLog)}',
    path: latestSpanLog,
  );

  if (latestSpanLog != null) {
    add(
      DoctorSeverity.info,
      'Export a session as a Firefox Profiler trace: '
      '`glue trace export <sessionId>` (or `--latest`).',
    );
  }

  if (observability.debug) {
    final latestHttpLog = _latestLogFile(logsDir, 'http-', '.jsonl');
    add(
      DoctorSeverity.info,
      latestHttpLog == null
          ? 'no recent http logs'
          : 'Recent http log: ${p.basename(latestHttpLog)}',
      path: latestHttpLog,
    );
  }

  add(DoctorSeverity.info, 'Body cap: ${observability.maxBodyBytes} bytes');

  add(
    observability.redact ? DoctorSeverity.info : DoctorSeverity.warning,
    observability.redact
        ? 'Redaction: enabled'
        : 'Redaction: disabled — debug logs may contain secrets',
  );
}

/// Maps a runtime adapter's [RuntimeDiagnosticLevel] onto the doctor's
/// own severity scale. The adapter owns the probing logic; doctor only
/// renders.
DoctorSeverity _runtimeDiagnosticSeverity(RuntimeDiagnosticLevel level) {
  return switch (level) {
    RuntimeDiagnosticLevel.ok => DoctorSeverity.ok,
    RuntimeDiagnosticLevel.info => DoctorSeverity.info,
    RuntimeDiagnosticLevel.warn => DoctorSeverity.warning,
    RuntimeDiagnosticLevel.error => DoctorSeverity.error,
  };
}

void _checkRuntime(List<DoctorFinding> findings, Environment environment) {
  const section = 'Runtime';
  void add(DoctorSeverity severity, String message) =>
      _add(findings, section, severity, message);

  GlueConfig config;
  try {
    config = GlueConfig.load(environment: environment);
  } on Object catch (e) {
    add(
      DoctorSeverity.warning,
      'Could not load config to determine runtime: $e',
    );
    return;
  }

  final selected = config.effectiveRuntime;
  add(DoctorSeverity.ok, 'Active runtime: $selected');

  final registered = RuntimeFactory.registeredAdapters().toList();
  if (registered.isNotEmpty) {
    add(
      DoctorSeverity.info,
      'Registered cloud adapters: ${registered.join(', ')}',
    );
  }

  // host/docker stay in the surface — they read GlueConfig/Environment
  // directly and have no cloud probe to delegate. Every other runtime
  // delegates readiness probing to its adapter via the factory.
  switch (selected) {
    case 'host':
      add(
        DoctorSeverity.info,
        'Commands run on the host shell (no isolation).',
      );
      return;
    case 'docker':
      add(
        DoctorSeverity.info,
        'Docker image: ${config.dockerConfig.image} '
        '(shell: ${config.dockerConfig.shell})',
      );
      return;
  }

  _checkHostGitForCloud(add);

  if (!registered.contains(selected)) {
    add(
      DoctorSeverity.error,
      'Runtime "$selected" is not host/docker and no '
      'registered cloud adapter matches.',
    );
    return;
  }

  final ctx = RuntimeDiagnosticContext(
    options: config.runtimeOptions,
    env: (key) => environment.vars[key],
  );
  for (final d in RuntimeFactory.diagnose(selected, ctx)) {
    add(_runtimeDiagnosticSeverity(d.level), d.message);
  }
}

/// Phase 4: host-side git is required by bundle bootstrap (used for
/// every cloud runtime). Warn early if it's missing so the user doesn't
/// discover this at first cloud session start. CLI-appropriate (probes
/// the host, not the sandbox), so it stays in the surface.
void _checkHostGitForCloud(void Function(DoctorSeverity, String) add) {
  try {
    final gitProbe = Process.runSync('git', ['--version']);
    if (gitProbe.exitCode == 0) {
      add(
        DoctorSeverity.ok,
        'Host git: ${(gitProbe.stdout as String).trim()} '
        '(bundle bootstrap available)',
      );
    } else {
      add(
        DoctorSeverity.warning,
        'Host git not runnable — bundle bootstrap is unavailable, '
        'cloud sessions will fall back to clone-from-remote '
        '(requires reachable origin + pushed HEAD)',
      );
    }
  } on ProcessException {
    add(
      DoctorSeverity.warning,
      'git not on host PATH — bundle bootstrap is unavailable, '
      'cloud sessions will fall back to clone-from-remote',
    );
  }
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
  _add(
    findings,
    'Sessions',
    DoctorSeverity.ok,
    'scanned ${sessionDirs.length} session directories',
    path: sessionsDir,
  );

  for (final sessionDir in sessionDirs) {
    final metaPath = p.join(sessionDir.path, 'meta.json');
    final conversationPath = p.join(sessionDir.path, 'conversation.jsonl');
    _checkSessionMeta(findings, metaPath);
    _checkConversationJsonl(findings, conversationPath);
  }
}

void _checkSessionMeta(List<DoctorFinding> findings, String path) {
  if (!File(path).existsSync()) {
    _add(
      findings,
      'Sessions',
      DoctorSeverity.error,
      'meta.json missing',
      path: path,
    );
    return;
  }
  final decoded = _parseJsonObject(findings, 'Sessions', path);
  if (decoded == null) return;
  for (final key in ['id', 'cwd', 'start_time']) {
    if (!decoded.containsKey(key)) {
      _add(
        findings,
        'Sessions',
        DoctorSeverity.error,
        'meta.json missing required key "$key"',
        path: path,
      );
      return;
    }
  }
}

void _checkConversationJsonl(List<DoctorFinding> findings, String path) {
  final file = File(path);
  if (!file.existsSync()) {
    _add(
      findings,
      'Sessions',
      DoctorSeverity.info,
      'conversation.jsonl missing',
      path: path,
    );
    return;
  }
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        _add(
          findings,
          'Sessions',
          DoctorSeverity.error,
          'conversation.jsonl line ${i + 1} is not an object',
          path: path,
        );
        return;
      }
      if (!decoded.containsKey('type')) {
        _add(
          findings,
          'Sessions',
          DoctorSeverity.error,
          'conversation.jsonl line ${i + 1} missing type',
          path: path,
        );
        return;
      }
    } on Object catch (e) {
      _add(
        findings,
        'Sessions',
        DoctorSeverity.error,
        'conversation.jsonl line ${i + 1} parse failed: $e',
        path: path,
      );
      return;
    }
  }
}

void _checkTmpFiles(List<DoctorFinding> findings, String glueDir) {
  final dir = Directory(glueDir);
  if (!dir.existsSync()) return;
  for (final entry in dir.listSync(recursive: true)) {
    if (!entry.path.endsWith('.tmp')) continue;
    _add(
      findings,
      'Filesystem',
      DoctorSeverity.warning,
      'orphaned tmp file',
      path: entry.path,
    );
  }
}
