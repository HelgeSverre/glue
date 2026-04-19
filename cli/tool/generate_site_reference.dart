// ignore_for_file: avoid_print
/// Generates the unified site's reference pages from canonical sources.
///
/// Inputs:
///   - ../docs/reference/models.yaml
///   - ../docs/reference/runtime-capabilities.yaml
///   - ../docs/reference/config-yaml.md
///   - ../docs/reference/session-storage.md
///   - lib/src/ui/theme_tokens.dart (parsed for TUI design tokens)
///
/// Outputs:
///   - ../website/generated/models.md
///   - ../website/generated/models.recommended.json
///   - ../website/generated/runtime-matrix.md
///   - ../website/generated/config-examples.md
///   - ../website/generated/session-events.md
///   - ../website/generated/brand-tokens.md
///
/// Every output begins with a `<!-- Generated from <source>. Do not edit. -->`
/// header so editors know not to hand-edit.
///
/// Usage:
///   dart run tool/generate_site_reference.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const _modelsYamlPath = '../docs/reference/models.yaml';
const _runtimeYamlPath = '../docs/reference/runtime-capabilities.yaml';
const _configMdPath = '../docs/reference/config-yaml.md';
const _sessionMdPath = '../docs/reference/session-storage.md';
const _themeTokensPath = 'lib/src/ui/theme_tokens.dart';

const _modelsOut = '../website/generated/models.md';
const _modelsJsonOut = '../website/generated/models.recommended.json';
const _runtimeOut = '../website/generated/runtime-matrix.md';
const _configOut = '../website/generated/config-examples.md';
const _sessionOut = '../website/generated/session-events.md';
const _brandOut = '../website/generated/brand-tokens.md';

void main(List<String> args) {
  final outDir = Directory('../website/generated');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  _writeModels();
  _writeModelsRecommendedJson();
  _writeRuntimeMatrix();
  _writeConfigExamples();
  _writeSessionEvents();
  _writeBrandTokens();

  print('Generated 6 files in ../website/generated/');
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

void _writeModels() {
  final yaml = loadYaml(File(_modelsYamlPath).readAsStringSync()) as YamlMap;
  final providers = yaml['providers'] as YamlMap;
  final capsDoc = yaml['capabilities'] as YamlMap;

  final rows = <Map<String, dynamic>>[];
  for (final entry in providers.entries) {
    final providerId = entry.key as String;
    final provider = entry.value as YamlMap;
    final models = provider['models'] as YamlMap? ?? YamlMap();
    for (final mEntry in models.entries) {
      final id = mEntry.key as String;
      final m = mEntry.value as YamlMap;
      rows.add({
        'id': id,
        'provider': providerId,
        'name': m['name'] ?? id,
        'recommended': m['recommended'] ?? false,
        'capabilities':
            (m['capabilities'] as YamlList?)?.cast<String>().toList() ??
                const <String>[],
        'notes': m['notes'] ?? '',
        'speed': m['speed'] ?? '',
        'cost': m['cost'] ?? '',
        'context_window': m['context_window'],
      });
    }
  }

  final sb = StringBuffer();
  sb.writeln(
      '<!-- Generated from docs/reference/models.yaml. Do not edit by hand. -->');
  sb.writeln(
      '<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->');
  sb.writeln();
  sb.writeln('# Model catalog');
  sb.writeln();
  sb.writeln(
      'Source: [`docs/reference/models.yaml`](https://github.com/helgesverre/glue/blob/main/docs/reference/models.yaml)');
  sb.writeln();
  sb.writeln('## Capabilities');
  sb.writeln();
  sb.writeln('| Capability | Meaning |');
  sb.writeln('| --- | --- |');
  for (final entry in capsDoc.entries) {
    sb.writeln('| `${entry.key}` | ${entry.value} |');
  }
  sb.writeln();

  sb.writeln('## Models');
  sb.writeln();
  sb.writeln(
      '| ID | Recommended | Capabilities | Context | Speed | Cost | Notes |');
  sb.writeln('| --- | :---: | --- | ---: | --- | --- | --- |');
  for (final r in rows) {
    final ctx = r['context_window'] == null ? '—' : '${r['context_window']}';
    final rec = (r['recommended'] == true) ? '★' : '';
    final caps = (r['capabilities'] as List<String>).join(', ');
    final notes = (r['notes'] as String).replaceAll('\n', ' ');
    sb.writeln(
        '| `${r['provider']}/${r['id']}` | $rec | $caps | $ctx | ${r['speed']} | ${r['cost']} | $notes |');
  }
  sb.writeln();

  File(_modelsOut).writeAsStringSync(sb.toString());
}

/// Emits the `recommended: true` subset of the catalog as JSON for the
/// marketing page (`website/models.md`) to import. Replaces the hand-curated
/// model table that used to be duplicated there.
void _writeModelsRecommendedJson() {
  final yaml = loadYaml(File(_modelsYamlPath).readAsStringSync()) as YamlMap;
  final providers = yaml['providers'] as YamlMap;

  final rows = <Map<String, dynamic>>[];
  for (final entry in providers.entries) {
    final providerId = entry.key as String;
    final provider = entry.value as YamlMap;
    final models = provider['models'] as YamlMap? ?? YamlMap();
    for (final mEntry in models.entries) {
      final id = mEntry.key as String;
      final m = mEntry.value as YamlMap;
      if (m['recommended'] != true) continue;
      rows.add({
        'id': id,
        'provider': providerId,
        'name': m['name'] ?? id,
        'recommended': true,
        'capabilities':
            (m['capabilities'] as YamlList?)?.cast<String>().toList() ??
                const <String>[],
        'notes': m['notes']?.toString() ?? '',
      });
    }
  }

  const encoder = JsonEncoder.withIndent('  ');
  File(_modelsJsonOut).writeAsStringSync('${encoder.convert(rows)}\n');
}

// ---------------------------------------------------------------------------
// Runtime matrix
// ---------------------------------------------------------------------------

void _writeRuntimeMatrix() {
  final yaml = loadYaml(File(_runtimeYamlPath).readAsStringSync()) as YamlMap;
  final capsDoc = yaml['capabilities'] as YamlMap;
  final runtimes = yaml['runtimes'] as YamlMap;

  final capKeys = capsDoc.keys.cast<String>().toList();

  final sb = StringBuffer();
  sb.writeln(
      '<!-- Generated from docs/reference/runtime-capabilities.yaml. Do not edit by hand. -->');
  sb.writeln(
      '<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->');
  sb.writeln();
  sb.writeln('# Runtime capability matrix');
  sb.writeln();
  sb.writeln(
      'Source: [`docs/reference/runtime-capabilities.yaml`](https://github.com/helgesverre/glue/blob/main/docs/reference/runtime-capabilities.yaml)');
  sb.writeln();

  sb.writeln('## Capabilities');
  sb.writeln();
  sb.writeln('| Capability | Meaning |');
  sb.writeln('| --- | --- |');
  for (final entry in capsDoc.entries) {
    sb.writeln('| `${entry.key}` | ${entry.value} |');
  }
  sb.writeln();

  sb.writeln('## Matrix');
  sb.writeln();
  sb.write('| Runtime | Status | Notes |');
  for (final cap in capKeys) {
    sb.write(' `$cap` |');
  }
  sb.writeln();
  sb.write('| --- | --- | --- |');
  for (var i = 0; i < capKeys.length; i++) {
    sb.write(' :---: |');
  }
  sb.writeln();

  for (final entry in runtimes.entries) {
    final name = entry.key as String;
    final rt = entry.value as YamlMap;
    final caps = rt['capabilities'] as YamlMap;
    sb.write('| `$name` | ${rt['status']} | ${rt['notes'] ?? ''} |');
    for (final cap in capKeys) {
      final cell = caps[cap]?.toString() ?? 'no';
      sb.write(' ${_cellGlyph(cell)} |');
    }
    sb.writeln();
  }
  sb.writeln();

  sb.writeln('Legend: `✓` yes · `◐` partial · `◌` planned · `—` no');
  sb.writeln();

  File(_runtimeOut).writeAsStringSync(sb.toString());
}

String _cellGlyph(String value) {
  switch (value) {
    case 'yes':
      return '✓';
    case 'partial':
      return '◐';
    case 'planned':
      return '◌';
    case 'no':
    default:
      return '—';
  }
}

// ---------------------------------------------------------------------------
// Config examples
// ---------------------------------------------------------------------------

void _writeConfigExamples() {
  final src = File(_configMdPath).readAsStringSync();

  // Extract every fenced code block in the source. Each block is emitted
  // into the generated file as-is, in the order it appears.
  final blocks = <_Block>[];
  final lines = src.split('\n');
  int? openLine;
  var lang = '';
  final buffer = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (openLine == null) {
      final match = RegExp(r'^```(\w*)').firstMatch(line);
      if (match != null) {
        openLine = i;
        lang = match.group(1) ?? '';
        buffer.clear();
        continue;
      }
    } else {
      if (line.startsWith('```')) {
        blocks.add(_Block(lang: lang, content: buffer.join('\n')));
        openLine = null;
      } else {
        buffer.add(line);
      }
    }
  }

  final sb = StringBuffer();
  sb.writeln(
      '<!-- Generated from docs/reference/config-yaml.md. Do not edit by hand. -->');
  sb.writeln(
      '<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->');
  sb.writeln();
  sb.writeln('# Config examples');
  sb.writeln();
  sb.writeln(
      'Extracted from the `~/.glue/config.yaml` reference. Keep editing');
  sb.writeln('the source file, not this one.');
  sb.writeln();

  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    sb.writeln('## Example ${i + 1}');
    sb.writeln();
    sb.writeln('```${b.lang}');
    sb.writeln(b.content);
    sb.writeln('```');
    sb.writeln();
  }

  File(_configOut).writeAsStringSync(sb.toString());
}

class _Block {
  _Block({required this.lang, required this.content});
  final String lang;
  final String content;
}

// ---------------------------------------------------------------------------
// Session events
// ---------------------------------------------------------------------------

void _writeSessionEvents() {
  final src = File(_sessionMdPath).readAsStringSync();

  // Pull the "Common event types" bullet list from the session-storage doc.
  // The list is a `- event_name with a, b` per line, under a header named
  // "Common event types". We stop at the next blank line.
  final events = <_Event>[];
  final lines = src.split('\n');
  var inList = false;
  for (final line in lines) {
    if (line.contains('Common event types')) {
      inList = true;
      continue;
    }
    if (!inList) continue;
    if (line.trim().isEmpty) {
      if (events.isNotEmpty) break;
      continue;
    }
    final match = RegExp(r'^- `(\w+)` with (.+)$').firstMatch(line);
    if (match != null) {
      events.add(_Event(name: match.group(1)!, fields: match.group(2)!));
    }
  }

  final sb = StringBuffer();
  sb.writeln(
      '<!-- Generated from docs/reference/session-storage.md. Do not edit by hand. -->');
  sb.writeln(
      '<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->');
  sb.writeln();
  sb.writeln('# Session event types');
  sb.writeln();
  sb.writeln('Current event types appended to `conversation.jsonl`. The event');
  sb.writeln('schema is expanding — tracked by the session JSONL schema plan.');
  sb.writeln();

  if (events.isEmpty) {
    sb.writeln(
        '_No event rows parsed. Check that session-storage.md still uses_');
    sb.writeln(
        '_the `- \\`name\\` with ...` format under "Common event types"._');
  } else {
    sb.writeln('| Event | Payload fields |');
    sb.writeln('| --- | --- |');
    for (final e in events) {
      sb.writeln('| `${e.name}` | ${e.fields} |');
    }
  }
  sb.writeln();

  File(_sessionOut).writeAsStringSync(sb.toString());
}

class _Event {
  _Event({required this.name, required this.fields});
  final String name;
  final String fields;
}

// ---------------------------------------------------------------------------
// Brand / terminal design tokens (parsed from theme_tokens.dart)
// ---------------------------------------------------------------------------

void _writeBrandTokens() {
  final src = File(_themeTokensPath).readAsStringSync();

  // Human-facing description for each known token. Keep in sync with
  // theme_tokens.dart; unknown tokens fall back to the literal field name.
  const descriptions = <String, String>{
    'textPrimary': 'Main transcript text.',
    'textSecondary': 'Supporting text (timestamps, inline meta).',
    'textMuted': 'De-emphasised, dim, or placeholder copy.',
    'accent': 'Brand accent — prompts, highlights, active chip.',
    'accentSubtle': 'Quieter accent — borders, focused backgrounds.',
    'surfaceBorder': 'Panel and divider lines.',
    'surfaceMuted': 'Subtle panel fill.',
    'focus': 'Focus indicator.',
    'selection': 'Selected text / row.',
    'info': 'Informational messages.',
    'success': 'Successful tool calls, passing tests.',
    'warning': 'Non-fatal warnings.',
    'danger': 'Errors and destructive prompts.',
  };

  // Tones exposed via GlueTone — keep ordered like the enum definition.
  const tones = <String, String>{
    'accent': 'Brand accent.',
    'info': 'Informational.',
    'success': 'Success, complete, OK.',
    'warning': 'Non-fatal warning.',
    'danger': 'Error, destructive.',
    'muted': 'De-emphasised.',
  };

  final minimal = _parseThemeMode(src, 'minimal');
  final hc = _parseThemeMode(src, 'highContrast');

  final sb = StringBuffer();
  sb.writeln(
      '<!-- Generated from cli/lib/src/ui/theme_tokens.dart. Do not edit by hand. -->');
  sb.writeln(
      '<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->');
  sb.writeln();
  sb.writeln('## Terminal design tokens');
  sb.writeln();
  sb.writeln('The TUI ships two theme modes: **minimal** (the default; quiet,');
  sb.writeln('low-contrast) and **highContrast** (for environments where');
  sb.writeln('default ANSI contrast is insufficient). Both modes share the');
  sb.writeln('same token surface; only the ANSI chain differs.');
  sb.writeln();
  sb.writeln('> Tokens are ANSI styling chains — read them as calls on a');
  sb.writeln('> `styled` builder. For example, `bold.yellow` means the text');
  sb.writeln('> is rendered bold and foreground-yellow.');
  sb.writeln();

  sb.writeln('### Brand dot');
  sb.writeln();
  sb.writeln('The brand dot is `●` (U+25CF). It prefixes section headings,');
  sb.writeln('selected list items, and prompt rows.');
  sb.writeln();

  sb.writeln('### Token styling');
  sb.writeln();
  sb.writeln('| Token | Minimal | High contrast | Description |');
  sb.writeln('| --- | --- | --- | --- |');
  for (final key in descriptions.keys) {
    final minStyle = minimal[key] ?? 'unstyled';
    final hcStyle = hc[key] ?? 'unstyled';
    final desc = descriptions[key]!;
    sb.writeln('| `$key` | `$minStyle` | `$hcStyle` | $desc |');
  }
  sb.writeln();

  sb.writeln('### Tones');
  sb.writeln();
  sb.writeln('`GlueTone` maps each semantic role to one of the tokens above,');
  sb.writeln('so components pick a tone without hardcoding a style.');
  sb.writeln();
  sb.writeln('| Tone | Backing token | Description |');
  sb.writeln('| --- | --- | --- |');
  for (final entry in tones.entries) {
    final token = entry.key == 'muted' ? 'textMuted' : entry.key;
    sb.writeln('| `${entry.key}` | `$token` | ${entry.value} |');
  }
  sb.writeln();

  File(_brandOut).writeAsStringSync(sb.toString());
}

/// Extract `{tokenName: ansiChain}` pairs for a single GlueThemeMode block.
///
/// The parser isolates the block between `case GlueThemeMode.<mode>:` and the
/// next `case` or end of `switch`, then pulls each
/// `tokenName: (text) => text.styled.<chain>.toString()` line.
Map<String, String> _parseThemeMode(String src, String mode) {
  final blockRe = RegExp(
    'case\\s+GlueThemeMode\\.$mode\\s*:(.*?)(?=case\\s+GlueThemeMode|\\}\\s*\$)',
    dotAll: true,
  );
  final blockMatch = blockRe.firstMatch(src);
  if (blockMatch == null) return const {};
  final block = blockMatch.group(1)!;

  final tokenRe = RegExp(
    r'(\w+):\s*\(text\)\s*=>\s*text\.styled\.([A-Za-z0-9_.()]+?)\.toString\(\)',
  );
  final result = <String, String>{};
  for (final m in tokenRe.allMatches(block)) {
    result[m.group(1)!] = m.group(2)!;
  }
  return result;
}
