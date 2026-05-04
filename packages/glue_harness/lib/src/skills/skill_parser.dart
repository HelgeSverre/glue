import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Where a skill was discovered.
enum SkillSource { project, global, custom }

extension SkillSourceLabel on SkillSource {
  String get label => switch (this) {
        SkillSource.project => 'project',
        SkillSource.global => 'global',
        SkillSource.custom => 'custom',
      };
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
  final Map<String, String> metadata;
  final String skillDir;
  final String skillMdPath;
  final SkillSource source;

  SkillMeta({
    required this.name,
    required this.description,
    this.license,
    this.compatibility,
    this.metadata = const {},
    required this.skillDir,
    required this.skillMdPath,
    required this.source,
  });
}

const _allowedFields = {
  'name',
  'description',
  'license',
  'allowed-tools',
  'metadata',
  'compatibility',
};

final _namePatternMulti = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');
final _namePatternSingle = RegExp(r'^[a-z0-9]$');

/// Parses YAML frontmatter from a SKILL.md file into a [SkillMeta].
SkillMeta parseSkillFrontmatter(
  String content,
  String skillDir,
  String skillMdPath,
  SkillSource source,
) {
  if (!content.startsWith('---')) {
    throw SkillParseError('Missing frontmatter delimiter');
  }

  final parts = content.split('---');
  if (parts.length < 3) {
    throw SkillParseError('Unclosed frontmatter');
  }

  final yamlStr = parts[1];
  final parsed = loadYaml(yamlStr);
  if (parsed is! YamlMap) {
    throw SkillParseError('Frontmatter is not a valid YAML map');
  }

  final keys = parsed.keys.cast<String>().toSet();
  final unknown = keys.difference(_allowedFields);
  if (unknown.isNotEmpty) {
    throw SkillParseError('Unknown frontmatter fields: ${unknown.join(', ')}');
  }

  final name = parsed['name'];
  if (name == null || name is! String || name.isEmpty) {
    throw SkillParseError('Missing or empty "name" field');
  }
  if (name.length > 64) {
    throw SkillParseError('Name exceeds 64 characters');
  }

  final namePattern = name.length == 1 ? _namePatternSingle : _namePatternMulti;
  if (!namePattern.hasMatch(name)) {
    throw SkillParseError(
        'Invalid name "$name": must be lowercase alphanumeric with hyphens');
  }
  if (name.contains('--')) {
    throw SkillParseError(
        'Invalid name "$name": consecutive hyphens not allowed');
  }

  final dirName = p.basename(skillDir);
  if (name != dirName) {
    throw SkillParseError('Name "$name" does not match directory "$dirName"');
  }

  final description = parsed['description'];
  if (description == null || description is! String || description.isEmpty) {
    throw SkillParseError('Missing or empty "description" field');
  }
  if (description.length > 1024) {
    throw SkillParseError('Description exceeds 1024 characters');
  }

  final compatibility = parsed['compatibility']?.toString();
  if (compatibility != null && compatibility.length > 500) {
    throw SkillParseError('Compatibility exceeds 500 characters');
  }

  final license = parsed['license']?.toString();

  final rawMeta = parsed['metadata'];
  final metadata = <String, String>{};
  if (rawMeta is YamlMap) {
    for (final entry in rawMeta.entries) {
      metadata[entry.key.toString()] = entry.value.toString();
    }
  }

  return SkillMeta(
    name: name,
    description: description,
    license: license,
    compatibility: compatibility,
    metadata: metadata,
    skillDir: skillDir,
    skillMdPath: skillMdPath,
    source: source,
  );
}

/// Loads the body content of a SKILL.md file (everything after the frontmatter).
String loadSkillBody(String skillMdPath) {
  final content = File(skillMdPath).readAsStringSync();
  if (!content.startsWith('---')) {
    throw SkillParseError('Missing frontmatter delimiter');
  }

  final parts = content.split('---');
  if (parts.length < 3) {
    throw SkillParseError('Unclosed frontmatter');
  }

  return parts.sublist(2).join('---').trimLeft();
}
