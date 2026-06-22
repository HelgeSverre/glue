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

DoctorReport runDoctor(Environment environment) {
  final findings = <DoctorFinding>[];

  void add(
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
  findings.add(
    DoctorFinding(
      severity: exists ? DoctorSeverity.ok : DoctorSeverity.warning,
      section: section,
      message: exists ? '$label exists' : '$label missing',
      path: path,
    ),
  );
}

void _checkConfigYaml(List<DoctorFinding> findings, String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml != null && yaml is! YamlMap) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.error,
          section: 'Config file',
          message: 'config.yaml root must be a mapping',
          path: path,
        ),
      );
      return;
    }
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.ok,
        section: 'Config file',
        message: 'config.yaml parsed',
        path: path,
      ),
    );
  } on Object catch (e) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.error,
        section: 'Config file',
        message: 'config.yaml parse failed: $e',
        path: path,
      ),
    );
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
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.error,
          section: section,
          message: '${p.basename(path)} root must be an object',
          path: path,
        ),
      );
      return;
    }
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.ok,
        section: section,
        message: '${p.basename(path)} parsed',
        path: path,
      ),
    );
  } on Object catch (e) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.error,
        section: section,
        message: '${p.basename(path)} parse failed: $e',
        path: path,
      ),
    );
  }
}

void _checkCredentialsJson(List<DoctorFinding> findings, String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.error,
          section: 'Credentials',
          message: 'credentials.json root must be an object',
          path: path,
        ),
      );
      return;
    }
    final providers = decoded['providers'];
    if (providers != null && providers is! Map) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.error,
          section: 'Credentials',
          message: 'credentials.json providers must be an object',
          path: path,
        ),
      );
      return;
    }
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.ok,
        section: 'Credentials',
        message: 'credentials.json parsed',
        path: path,
      ),
    );
  } on Object catch (e) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.error,
        section: 'Credentials',
        message: 'credentials.json parse failed: $e',
        path: path,
      ),
    );
  }
}

void _checkCatalog(List<DoctorFinding> findings, String section, String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    parseCatalogYaml(file.readAsStringSync());
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.ok,
        section: section,
        message: '${p.basename(path)} parsed',
        path: path,
      ),
    );
  } on CatalogParseException catch (e) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.error,
        section: section,
        message: '${p.basename(path)} parse failed: ${e.message}',
        path: path,
      ),
    );
  } on Object catch (e) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.error,
        section: section,
        message: '${p.basename(path)} parse failed: $e',
        path: path,
      ),
    );
  }
}

void _checkConfigValidation(
  List<DoctorFinding> findings,
  Environment environment,
) {
  final result = validateUserConfig(environment);
  findings.add(
    DoctorFinding(
      severity: result.ok ? DoctorSeverity.ok : DoctorSeverity.error,
      section: 'Config validation',
      message: result.message,
      path: environment.configYamlPath,
    ),
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
  findings.add(
    DoctorFinding(
      severity: DoctorSeverity.info,
      section: 'Agent model',
      message:
          '$ref does not declare the "tools" capability — '
          'sessions will run in chat-only mode. '
          'Use /model to switch to a tool-capable model.',
    ),
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

  findings.add(
    DoctorFinding(
      severity: DoctorSeverity.info,
      section: section,
      message: 'debug: ${observability.debug ? 'on' : 'off'}',
    ),
  );

  findings.add(
    DoctorFinding(
      severity: DoctorSeverity.info,
      section: section,
      message: 'Log directory: $logsDir',
      path: logsDir,
    ),
  );

  final otel = observability.otel;
  findings.add(
    DoctorFinding(
      severity: otel.isConfigured ? DoctorSeverity.ok : DoctorSeverity.info,
      section: section,
      message: otel.isConfigured
          ? 'OTEL export: on (${normalizeOtlpTracesEndpoint(otel.endpoint!)})'
          : 'OTEL export: off',
    ),
  );
  if (otel.isConfigured) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.info,
        section: section,
        message: 'OTEL service: ${otel.serviceName}',
      ),
    );
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.info,
        section: section,
        message: 'OTEL headers: ${redactOtelHeadersForDisplay(otel.headers)}',
      ),
    );
  }

  final latestSpanLog = _latestLogFile(logsDir, 'spans-', '.jsonl');
  findings.add(
    DoctorFinding(
      severity: DoctorSeverity.info,
      section: section,
      message: latestSpanLog == null
          ? 'no recent span logs'
          : 'Recent span log: ${p.basename(latestSpanLog)}',
      path: latestSpanLog,
    ),
  );

  if (latestSpanLog != null) {
    findings.add(
      const DoctorFinding(
        severity: DoctorSeverity.info,
        section: section,
        message:
            'Export a session as a Firefox Profiler trace: '
            '`glue trace export <sessionId>` (or `--latest`).',
      ),
    );
  }

  if (observability.debug) {
    final latestHttpLog = _latestLogFile(logsDir, 'http-', '.jsonl');
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.info,
        section: section,
        message: latestHttpLog == null
            ? 'no recent http logs'
            : 'Recent http log: ${p.basename(latestHttpLog)}',
        path: latestHttpLog,
      ),
    );
  }

  findings.add(
    DoctorFinding(
      severity: DoctorSeverity.info,
      section: section,
      message: 'Body cap: ${observability.maxBodyBytes} bytes',
    ),
  );

  findings.add(
    DoctorFinding(
      severity: observability.redact
          ? DoctorSeverity.info
          : DoctorSeverity.warning,
      section: section,
      message: observability.redact
          ? 'Redaction: enabled'
          : 'Redaction: disabled — debug logs may contain secrets',
    ),
  );
}

void _checkRuntime(List<DoctorFinding> findings, Environment environment) {
  const section = 'Runtime';

  GlueConfig? config;
  try {
    config = GlueConfig.load(environment: environment);
  } on Object catch (e) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.warning,
        section: section,
        message: 'Could not load config to determine runtime: $e',
      ),
    );
    return;
  }

  final selected = config.effectiveRuntime;
  findings.add(
    DoctorFinding(
      severity: DoctorSeverity.ok,
      section: section,
      message: 'Active runtime: $selected',
    ),
  );

  final registered = RuntimeFactory.registeredAdapters().toList();
  if (registered.isNotEmpty) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.info,
        section: section,
        message: 'Registered cloud adapters: ${registered.join(', ')}',
      ),
    );
  }

  // Phase 4: host-side git is required by bundle bootstrap
  // (used for every cloud runtime). Warn early if it's missing so
  // the user doesn't discover this at first cloud session start.
  if (selected != 'host' && selected != 'docker') {
    try {
      final gitProbe = Process.runSync('git', ['--version']);
      if (gitProbe.exitCode == 0) {
        findings.add(
          DoctorFinding(
            severity: DoctorSeverity.ok,
            section: section,
            message:
                'Host git: ${(gitProbe.stdout as String).trim()} '
                '(bundle bootstrap available)',
          ),
        );
      } else {
        findings.add(
          const DoctorFinding(
            severity: DoctorSeverity.warning,
            section: section,
            message:
                'Host git not runnable — bundle bootstrap is unavailable, '
                'cloud sessions will fall back to clone-from-remote '
                '(requires reachable origin + pushed HEAD)',
          ),
        );
      }
    } on ProcessException {
      findings.add(
        const DoctorFinding(
          severity: DoctorSeverity.warning,
          section: section,
          message:
              'git not on host PATH — bundle bootstrap is unavailable, '
              'cloud sessions will fall back to clone-from-remote',
        ),
      );
    }
  }

  switch (selected) {
    case 'host':
      findings.add(
        const DoctorFinding(
          severity: DoctorSeverity.info,
          section: section,
          message: 'Commands run on the host shell (no isolation).',
        ),
      );
    case 'docker':
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.info,
          section: section,
          message:
              'Docker image: ${config.dockerConfig.image} (shell: ${config.dockerConfig.shell})',
        ),
      );
    case 'daytona':
      final hasKey =
          (environment.vars['DAYTONA_API_KEY']?.isNotEmpty ?? false) ||
          (config.runtimeOptions['api_key'] as String?)?.isNotEmpty == true;
      findings.add(
        DoctorFinding(
          severity: hasKey ? DoctorSeverity.ok : DoctorSeverity.error,
          section: section,
          message: hasKey
              ? 'DAYTONA_API_KEY: present'
              : 'DAYTONA_API_KEY missing — set the env var or daytona.api_key in config',
        ),
      );
      final snapshot =
          (config.runtimeOptions['snapshot'] as String?) ??
          environment.vars['DAYTONA_SNAPSHOT'];
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.info,
          section: section,
          message: snapshot == null
              ? 'Daytona: default sandbox shape (2 vCPU / 4 GiB / 8 GiB)'
              : 'Daytona snapshot: $snapshot',
        ),
      );
    case 'modal':
      // Modal exposes sandboxes only via its Python SDK; glue ships
      // a Python sidecar that drives it. The readiness check is
      // "the configured python interpreter can import modal".
      final cliPath =
          (config.runtimeOptions['modal_cli'] as String?) ??
          environment.vars['MODAL_CLI'] ??
          'modal';
      String? python;
      String? failureReason;
      try {
        final which = Process.runSync('which', [cliPath]);
        if (which.exitCode != 0) {
          failureReason =
              '`$cliPath` not found on PATH — '
              '`uv tool install modal` (or `pipx install modal`)';
        } else {
          final modalPath = (which.stdout as String).trim();
          // Follow the shebang to find the venv python.
          final firstLine = File(
            modalPath,
          ).readAsStringSync().split('\n').first;
          if (firstLine.startsWith('#!')) {
            python = firstLine.substring(2).trim().split(' ').first;
          }
          python ??=
              (config.runtimeOptions['python_path'] as String?) ??
              environment.vars['MODAL_PYTHON'] ??
              'python3';
          final import = Process.runSync(python, [
            '-c',
            'import modal; print(modal.__version__)',
          ]);
          if (import.exitCode != 0) {
            failureReason =
                'python at $python cannot import modal — install the package '
                'into that interpreter, or set MODAL_PYTHON / modal.python_path';
          }
        }
      } on ProcessException {
        failureReason = 'failed to probe modal — check $cliPath is executable';
      }
      findings.add(
        DoctorFinding(
          severity: failureReason == null
              ? DoctorSeverity.ok
              : DoctorSeverity.error,
          section: section,
          message: failureReason == null
              ? 'modal CLI + python ($python) ready'
              : 'modal: $failureReason',
        ),
      );
      // Auth check: `modal profile current` exits 0 when logged in.
      try {
        final auth = Process.runSync(cliPath, ['profile', 'current']);
        findings.add(
          DoctorFinding(
            severity: auth.exitCode == 0
                ? DoctorSeverity.ok
                : DoctorSeverity.error,
            section: section,
            message: auth.exitCode == 0
                ? 'modal profile: ${(auth.stdout as String).trim()}'
                : 'modal not authenticated — run `modal token set`',
          ),
        );
      } on ProcessException {
        /* already covered */
      }
      final appName =
          (config.runtimeOptions['app_name'] as String?) ??
          environment.vars['MODAL_APP'] ??
          'glue';
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.info,
          section: section,
          message: 'modal app: $appName',
        ),
      );
    case 'sprites':
      // Glue wraps the official `sprite` CLI (the API's wire protocol
      // is in RC flux and there's no stable /filesystem REST endpoint
      // today), so the readiness check is "binary on PATH, user is
      // logged in".
      final cliPath =
          (config.runtimeOptions['sprite_cli'] as String?) ??
          environment.vars['SPRITES_CLI'] ??
          'sprite';
      String? failureReason;
      try {
        final res = Process.runSync(cliPath, ['list']);
        if (res.exitCode != 0) {
          failureReason = 'not authenticated — run `sprite login`';
        }
      } on ProcessException {
        failureReason = 'not found on PATH';
      }
      findings.add(
        DoctorFinding(
          severity: failureReason == null
              ? DoctorSeverity.ok
              : DoctorSeverity.error,
          section: section,
          message: failureReason == null
              ? '`$cliPath` CLI installed and authenticated'
              : '`$cliPath` CLI: $failureReason',
        ),
      );
      final spriteName =
          (config.runtimeOptions['sprite_name'] as String?) ??
          environment.vars['SPRITES_NAME'];
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.info,
          section: section,
          message: spriteName == null
              ? 'Sprite name: auto (a fresh sprite per session)'
              : 'Sprite name: $spriteName (resumes on each session)',
        ),
      );
    default:
      if (!registered.contains(selected)) {
        findings.add(
          DoctorFinding(
            severity: DoctorSeverity.error,
            section: section,
            message:
                'Runtime "$selected" is not host/docker and no '
                'registered cloud adapter matches.',
          ),
        );
      }
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
  findings.add(
    DoctorFinding(
      severity: DoctorSeverity.ok,
      section: 'Sessions',
      message: 'scanned ${sessionDirs.length} session directories',
      path: sessionsDir,
    ),
  );

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
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.error,
        section: 'Sessions',
        message: 'meta.json missing',
        path: path,
      ),
    );
    return;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.error,
          section: 'Sessions',
          message: 'meta.json root must be an object',
          path: path,
        ),
      );
      return;
    }
    for (final key in ['id', 'cwd', 'start_time']) {
      if (!decoded.containsKey(key)) {
        findings.add(
          DoctorFinding(
            severity: DoctorSeverity.error,
            section: 'Sessions',
            message: 'meta.json missing required key "$key"',
            path: path,
          ),
        );
        return;
      }
    }
  } on Object catch (e) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.error,
        section: 'Sessions',
        message: 'meta.json parse failed: $e',
        path: path,
      ),
    );
  }
}

void _checkConversationJsonl(List<DoctorFinding> findings, String path) {
  final file = File(path);
  if (!file.existsSync()) {
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.info,
        section: 'Sessions',
        message: 'conversation.jsonl missing',
        path: path,
      ),
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
        findings.add(
          DoctorFinding(
            severity: DoctorSeverity.error,
            section: 'Sessions',
            message: 'conversation.jsonl line ${i + 1} is not an object',
            path: path,
          ),
        );
        return;
      }
      if (!decoded.containsKey('type')) {
        findings.add(
          DoctorFinding(
            severity: DoctorSeverity.error,
            section: 'Sessions',
            message: 'conversation.jsonl line ${i + 1} missing type',
            path: path,
          ),
        );
        return;
      }
    } on Object catch (e) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.error,
          section: 'Sessions',
          message: 'conversation.jsonl line ${i + 1} parse failed: $e',
          path: path,
        ),
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
    findings.add(
      DoctorFinding(
        severity: DoctorSeverity.warning,
        section: 'Filesystem',
        message: 'orphaned tmp file',
        path: entry.path,
      ),
    );
  }
}
