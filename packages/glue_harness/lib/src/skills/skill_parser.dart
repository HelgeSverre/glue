import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Where a skill was discovered.
enum SkillSource {
  project,
  projectAgents,
  projectClaude,
  global,
  userAgents,
  userClaude,
  custom,
  bundled,
}

extension SkillSourceLabel on SkillSource {
  String get label => switch (this) {
    SkillSource.project => 'project',
    SkillSource.projectAgents => 'project-agents',
    SkillSource.projectClaude => 'project-claude',
    SkillSource.global => 'global',
    SkillSource.userAgents => 'user-agents',
    SkillSource.userClaude => 'user-claude',
    SkillSource.custom => 'custom',
    SkillSource.bundled => 'bundled',
  };
}

enum SkillDiagnosticSeverity { warning, error }

class SkillDiagnostic {
  final SkillDiagnosticSeverity severity;
  final String code;
  final String message;
  final String? path;
  final String? skillName;

  const SkillDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.path,
    this.skillName,
  });
}

enum SkillResourceKind { script, reference, asset, other }

class SkillResource {
  final String relativePath;
  final String absolutePath;
  final SkillResourceKind kind;
  final int? sizeBytes;

  const SkillResource({
    required this.relativePath,
    required this.absolutePath,
    required this.kind,
    this.sizeBytes,
  });
}

/// An error thrown when a SKILL.md file cannot be parsed.
class SkillParseError implements Exception {
  final String message;
  SkillParseError(this.message);

  @override
  String toString() => 'SkillParseError: $message';
}

/// Parsed metadata from a skill's YAML frontmatter.
class SkillMeta {
  final String name;
  final String description;
  final String? license;
  final String? compatibility;
  final List<String> allowedTools;
  final Map<String, String> metadata;
  final List<SkillResource> resources;
  final String skillDir;
  final String skillMdPath;
  final SkillSource source;

  SkillMeta({
    required this.name,
    required this.description,
    this.license,
    this.compatibility,
    this.allowedTools = const [],
    this.metadata = const {},
    this.resources = const [],
    required this.skillDir,
    required this.skillMdPath,
    required this.source,
  });

  SkillMeta copyWith({List<SkillResource>? resources}) {
    return SkillMeta(
      name: name,
      description: description,
      license: license,
      compatibility: compatibility,
      allowedTools: allowedTools,
      metadata: metadata,
      resources: resources ?? this.resources,
      skillDir: skillDir,
      skillMdPath: skillMdPath,
      source: source,
    );
  }
}

const _allowedFields = {
  'name',
  'description',
  'license',
  'allowed-tools',
  'metadata',
  'compatibility',
};

final _namePattern = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');

/// Parses YAML frontmatter from a SKILL.md file into a [SkillMeta].
SkillMeta parseSkillFrontmatter(
  String content,
  String skillDir,
  String skillMdPath,
  SkillSource source,
) {
  final split = _splitSkillContent(content);
  final Object? parsed;
  try {
    parsed = loadYaml(split.frontmatter);
  } catch (e) {
    throw SkillParseError('Invalid YAML frontmatter: $e');
  }
  if (parsed is! YamlMap) {
    throw SkillParseError('Frontmatter is not a valid YAML map');
  }

  final keys = parsed.keys.cast<String>().toSet();
  final unknown = keys.difference(_allowedFields);
  if (unknown.isNotEmpty) {
    throw SkillParseError('Unknown frontmatter fields: ${unknown.join(', ')}');
  }

  final name = _requiredStringField(parsed, 'name');
  if (name.length > 64) {
    throw SkillParseError('Name exceeds 64 characters');
  }

  if (!_namePattern.hasMatch(name)) {
    throw SkillParseError(
      'Invalid name "$name": must be lowercase alphanumeric with hyphens',
    );
  }
  if (name.contains('--')) {
    throw SkillParseError(
      'Invalid name "$name": consecutive hyphens not allowed',
    );
  }

  final dirName = p.basename(p.normalize(skillDir));
  if (name != dirName) {
    throw SkillParseError('Name "$name" does not match directory "$dirName"');
  }

  final description = _requiredStringField(parsed, 'description');
  if (description.length > 1024) {
    throw SkillParseError('Description exceeds 1024 characters');
  }

  final compatibility = parsed['compatibility']?.toString();
  if (compatibility != null && compatibility.length > 500) {
    throw SkillParseError('Compatibility exceeds 500 characters');
  }

  final license = parsed['license']?.toString();
  final allowedTools = _parseAllowedTools(parsed['allowed-tools']);

  final rawMetadata = parsed['metadata'];
  final metadata = rawMetadata is YamlMap
      ? Map.fromEntries(
          rawMetadata.entries.map(
            (entry) => MapEntry(entry.key.toString(), entry.value.toString()),
          ),
        )
      : <String, String>{};

  return SkillMeta(
    name: name,
    description: description,
    license: license,
    compatibility: compatibility,
    allowedTools: allowedTools,
    metadata: metadata,
    skillDir: skillDir,
    skillMdPath: skillMdPath,
    source: source,
  );
}

/// Loads the body content of a SKILL.md file (everything after the frontmatter).
String loadSkillBody(String skillMdPath) {
  final content = File(skillMdPath).readAsStringSync();
  return _splitSkillContent(content).body.trimLeft();
}

String _requiredStringField(YamlMap parsed, String field) {
  final value = parsed[field];
  if (value is! String || value.isEmpty) {
    throw SkillParseError('Missing or empty "$field" field');
  }
  return value;
}

List<String> _parseAllowedTools(Object? value) {
  if (value == null) return const [];
  if (value is String) {
    return value
        .split(RegExp(r'[\s,]+'))
        .map((tool) => tool.trim())
        .where((tool) => tool.isNotEmpty)
        .toList(growable: false);
  }
  if (value is YamlList) {
    return value
        .map((tool) => tool.toString().trim())
        .where((tool) => tool.isNotEmpty)
        .toList(growable: false);
  }
  throw SkillParseError('allowed-tools must be a string or list');
}

_SkillContent _splitSkillContent(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  if (lines.isEmpty || lines.first.trimRight() != '---') {
    throw SkillParseError('Missing frontmatter delimiter');
  }

  final closingIndex = _findClosingFrontmatterIndex(lines);
  if (closingIndex == -1) {
    throw SkillParseError('Unclosed frontmatter');
  }

  return _SkillContent(
    frontmatter: lines.sublist(1, closingIndex).join('\n'),
    body: lines.sublist(closingIndex + 1).join('\n'),
  );
}

int _findClosingFrontmatterIndex(List<String> lines) {
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trimRight() == '---') {
      return i;
    }
  }
  return -1;
}

class _SkillContent {
  final String frontmatter;
  final String body;

  const _SkillContent({required this.frontmatter, required this.body});
}
