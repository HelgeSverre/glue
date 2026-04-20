import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:glue/src/catalog/catalog_parser.dart';
import 'package:glue/src/commands/config_command.dart';
import 'package:glue/src/core/environment.dart';

enum DoctorSeverity {
  ok,
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
    findings.add(DoctorFinding(
      section: section,
      severity: severity,
      message: message,
      path: path,
    ));
  }

  add('Environment', DoctorSeverity.ok, 'GLUE_HOME: ${environment.glueDir}');
  add('Environment', DoctorSeverity.ok, 'cwd: ${environment.cwd}');

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
  _checkSessions(findings, environment.sessionsDir);
  _checkTmpFiles(findings, environment.glueDir);

  return DoctorReport(findings);
}

String renderDoctorReport(DoctorReport report) {
  final buf = StringBuffer();
  buf.writeln('Glue Doctor');
  buf.writeln('===========');
  buf.writeln();

  String? currentSection;
  for (final finding in report.findings) {
    if (finding.section != currentSection) {
      if (currentSection != null) buf.writeln();
      currentSection = finding.section;
      buf.writeln(finding.section);
    }
    final label = switch (finding.severity) {
      DoctorSeverity.ok => 'OK',
      DoctorSeverity.warning => 'WARN',
      DoctorSeverity.error => 'ERROR',
    };
    final suffix = finding.path == null ? '' : ' (${finding.path})';
    buf.writeln('  ${label.padRight(5)} ${finding.message}$suffix');
  }

  buf.writeln();
  buf.writeln('Summary');
  buf.writeln(
    '  ${report.okCount} OK, ${report.warningCount} WARN, '
    '${report.errorCount} ERROR',
  );
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
      severity: DoctorSeverity.warning,
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
