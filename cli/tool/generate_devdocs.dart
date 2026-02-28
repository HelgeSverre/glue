// ignore_for_file: avoid_print
/// Generates VitePress API documentation from Dart source files.
///
/// Walks `lib/src/` recursively, extracts doc comments and public API via
/// regex, and generates:
///   1. One `.md` file per source file in `../devdocs/api/{module}/`
///   2. `../devdocs/.vitepress/sidebar.json` for VitePress sidebar
///   3. `../devdocs/api/index.md` — API landing page
///
/// Usage:
///   dart run tool/generate_devdocs.dart
import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const _moduleOrder = [
  'core',
  'agent',
  'llm',
  'config',
  'terminal',
  'rendering',
  'shell',
  'tools',
  'observability',
  'storage',
  'ui',
  'input',
  'skills',
  'web',
  'commands',
];

const _moduleDisplayNames = <String, String>{
  'llm': 'LLM Providers',
  'ui': 'UI',
  'web': 'Web',
};

const _moduleDescriptions = <String, String>{
  'core': 'Top-level application orchestration',
  'agent': 'Core agent loop, runner, and subagent manager',
  'llm': 'Provider clients (Anthropic, OpenAI, Ollama)',
  'config': 'Configuration, constants, and model registry',
  'terminal': 'Terminal I/O, screen buffer, and layout',
  'rendering': 'Markdown rendering, ANSI utilities, and mascot',
  'shell': 'Shell command execution and Docker integration',
  'tools': 'Built-in and extended tool implementations',
  'observability': 'Logging, tracing, and telemetry sinks',
  'storage': 'Session state, config storage, and debug logs',
  'ui': 'UI widgets — modals, autocomplete, hints',
  'input': 'Line editor and file expansion',
  'skills': 'Skill parser, registry, and tool integration',
  'web': 'Web fetching, browser automation, and search',
  'commands': 'Slash commands and CLI handlers',
};

const _githubBase =
    'https://github.com/helgesverre/glue/blob/main/cli/lib/src/';

// ---------------------------------------------------------------------------
// Regex patterns
// ---------------------------------------------------------------------------

final _categoryPattern = RegExp(r'\{@category\s+(.+?)\}');

/// Matches a class/mixin declaration (with optional modifiers).
final _classPattern = RegExp(
  r'^(?:sealed\s+|abstract\s+|base\s+|final\s+)*(?:class|mixin)\s+(\w+)',
  multiLine: true,
);

/// Matches an enum declaration.
final _enumPattern = RegExp(r'^\s*enum\s+(\w+)', multiLine: true);

/// Matches a top-level function (not indented, not a class member).
final _topLevelFunctionPattern = RegExp(
  r'^(?![ \t])(\w[\w<>?,\s]*?)\s+(\w+)\s*\(([^)]*)\)\s*(?:async\*?|sync\*)?\s*[{\=]',
  multiLine: true,
);

/// Matches a top-level constant/final.
final _topLevelConstPattern = RegExp(
  r'^(?:const|final)\s+(\w[\w<>?]*)\s+(\w+)\s*=',
  multiLine: true,
);

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

class DartFile {
  final String relativePath; // e.g. agent/agent_core.dart
  final String module; // e.g. agent
  final String content;
  final String? libraryDoc;
  final String? category;
  final List<DartClass> classes;
  final List<DartEnum> enums;
  final List<DartFunction> topLevelFunctions;
  final List<DartConstant> topLevelConstants;

  DartFile({
    required this.relativePath,
    required this.module,
    required this.content,
    this.libraryDoc,
    this.category,
    required this.classes,
    required this.enums,
    required this.topLevelFunctions,
    required this.topLevelConstants,
  });

  /// The filename without extension, e.g. `agent_core`.
  String get stem => relativePath.split('/').last.replaceAll('.dart', '');

  /// Kebab-case filename, e.g. `agent-core`.
  String get kebab => stem.replaceAll('_', '-');

  /// Primary class name for the sidebar label.
  ///
  /// Prefers a class/enum whose name matches the file stem (PascalCase of the
  /// snake_case filename). Falls back to the title-cased filename to keep
  /// sidebar labels clean for files with many types.
  String get primaryName {
    final expected = _titleCase(stem);
    for (final c in classes) {
      if (c.name == expected) return c.name;
    }
    for (final e in enums) {
      if (e.name == expected) return e.name;
    }
    // No exact match — use the title-cased filename rather than an
    // arbitrary first class that may not represent the file.
    return expected;
  }
}

class DartClass {
  final String name;
  final String? docComment;
  final String? declaration; // full line(s)
  final List<DartMember> members;
  final bool isSealed;
  final bool isAbstract;

  DartClass({
    required this.name,
    this.docComment,
    this.declaration,
    required this.members,
    this.isSealed = false,
    this.isAbstract = false,
  });
}

class DartEnum {
  final String name;
  final String? docComment;
  final List<String> values;

  DartEnum({required this.name, this.docComment, required this.values});
}

class DartMember {
  final String kind; // 'constructor', 'method', 'property', 'getter'
  final String signature;
  final String? docComment;

  DartMember({required this.kind, required this.signature, this.docComment});
}

class DartFunction {
  final String name;
  final String signature;
  final String? docComment;

  DartFunction(
      {required this.name, required this.signature, this.docComment});
}

class DartConstant {
  final String name;
  final String type;
  final String? docComment;

  DartConstant({required this.name, required this.type, this.docComment});
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Extracts the doc comment block immediately preceding [offset] in [source].
String? _extractDocComment(String source, int offset) {
  // Walk backwards from the offset to find consecutive /// lines.
  final before = source.substring(0, offset);
  final lines = before.split('\n');

  // Remove the last line (the one containing the declaration start).
  if (lines.isNotEmpty) lines.removeLast();

  final docLines = <String>[];
  for (var i = lines.length - 1; i >= 0; i--) {
    final trimmed = lines[i].trim();
    if (trimmed.startsWith('///')) {
      docLines.insert(0, trimmed.replaceFirst(RegExp(r'^///\s?'), ''));
    } else if (trimmed.isEmpty) {
      // Allow blank lines between doc comment blocks.
      continue;
    } else {
      break;
    }
  }

  if (docLines.isEmpty) return null;

  // Strip {@category ...} tags from the doc comment text.
  final cleaned =
      docLines.map((l) => l.replaceAll(_categoryPattern, '').trim()).toList();
  // Remove leading/trailing empty lines.
  while (cleaned.isNotEmpty && cleaned.first.isEmpty) {
    cleaned.removeAt(0);
  }
  while (cleaned.isNotEmpty && cleaned.last.isEmpty) {
    cleaned.removeLast();
  }
  if (cleaned.isEmpty) return null;
  return cleaned.join('\n');
}

/// Finds the index of the matching closing `}` for an opening `{` at [start].
int _findMatchingBrace(String source, int start) {
  var depth = 0;
  var inString = false;
  var stringChar = '';
  var escaped = false;

  for (var i = start; i < source.length; i++) {
    final c = source[i];

    if (escaped) {
      escaped = false;
      continue;
    }
    if (c == '\\') {
      escaped = true;
      continue;
    }

    if (inString) {
      if (c == stringChar) inString = false;
      continue;
    }

    if (c == "'" || c == '"') {
      inString = true;
      stringChar = c;
      continue;
    }

    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return source.length - 1;
}

/// Extract members from a class body.
List<DartMember> _extractMembers(String classBody, String className) {
  final members = <DartMember>[];

  // Constructor patterns (including factory).
  final ctorPattern = RegExp(
    '^\\s*(?:const\\s+)?(?:factory\\s+)?$className(?:\\.\\w+)?\\s*\\(',
    multiLine: true,
  );
  final seenCtorStarts = <int>{};
  for (final m in ctorPattern.allMatches(classBody)) {
    // Deduplicate: a named constructor like `ClassName._(` can overlap with
    // a factory that references it on the same line.
    if (seenCtorStarts.contains(m.start)) continue;
    seenCtorStarts.add(m.start);

    // Find the end of the constructor signature.
    final parenStart = classBody.indexOf('(', m.start);
    if (parenStart == -1) continue;
    var depth = 1;
    var end = parenStart + 1;
    while (end < classBody.length && depth > 0) {
      if (classBody[end] == '(') depth++;
      if (classBody[end] == ')') depth--;
      end++;
    }
    final sig = classBody.substring(m.start, end).trim();

    // Skip private named constructors (e.g. `ClassName._(...)`).
    if (RegExp(r'\._\s*\(').hasMatch(sig)) continue;

    final doc = _extractDocComment(classBody, m.start);
    members.add(DartMember(kind: 'constructor', signature: sig, docComment: doc));
  }

  // Method patterns.
  final methodPattern = RegExp(
    r'^  (?:static\s+)?(?:Future<[\w<>?]+>|Stream<[\w<>?]+>|[\w<>?]+)\s+(\w+)\s*\(',
    multiLine: true,
  );
  for (final m in methodPattern.allMatches(classBody)) {
    final name = m.group(1)!;
    // Skip constructors (already captured), private methods, overrides of
    // toString/hashCode/==.
    if (name.startsWith('_')) continue;
    if (name == className) continue;

    // Build the full signature including return type and params.
    final lineStart = classBody.lastIndexOf('\n', m.start) + 1;
    final parenStart = classBody.indexOf('(', m.start);
    if (parenStart == -1) continue;
    var depth = 1;
    var end = parenStart + 1;
    while (end < classBody.length && depth > 0) {
      if (classBody[end] == '(') depth++;
      if (classBody[end] == ')') depth--;
      end++;
    }
    final rawSig = classBody.substring(lineStart, end).trim();
    // Clean up override annotations.
    final sig = rawSig.replaceAll(RegExp(r'@override\s*'), '');
    final doc = _extractDocComment(classBody, m.start);
    members.add(DartMember(kind: 'method', signature: sig, docComment: doc));
  }

  // Property/getter patterns.
  final propPattern = RegExp(
    r'^  (?:static\s+)?(?:final\s+|late\s+)?(\w[\w<>?,\s]*?)\s+(\w+)\s*[;=]',
    multiLine: true,
  );
  for (final m in propPattern.allMatches(classBody)) {
    final type = m.group(1)!.trim();
    final name = m.group(2)!;
    if (name.startsWith('_')) continue;
    // Skip if it looks like a method (already captured).
    if (type == 'void' || type == 'Future' || type == 'Stream') continue;
    final doc = _extractDocComment(classBody, m.start);
    members.add(DartMember(
      kind: 'property',
      signature: '$type $name',
      docComment: doc,
    ));
  }

  // Getter patterns.
  final getterPattern = RegExp(
    r'^  (?:static\s+)?(\w[\w<>?]*)\s+get\s+(\w+)',
    multiLine: true,
  );
  for (final m in getterPattern.allMatches(classBody)) {
    final type = m.group(1)!;
    final name = m.group(2)!;
    if (name.startsWith('_')) continue;
    final doc = _extractDocComment(classBody, m.start);
    members.add(DartMember(
      kind: 'getter',
      signature: '$type get $name',
      docComment: doc,
    ));
  }

  return members;
}

/// Parse a single Dart file into a [DartFile].
DartFile _parseFile(File file, String relativePath, String module) {
  final source = file.readAsStringSync();

  // Library-level doc comment (before any import/class).
  String? libraryDoc;
  final firstNonComment = RegExp(r'^(?!///|$|\s)', multiLine: true);
  final firstCodeMatch = firstNonComment.firstMatch(source);
  if (firstCodeMatch != null) {
    libraryDoc = _extractDocComment(source, firstCodeMatch.start);
  }

  // Category.
  String? category;
  final catMatch = _categoryPattern.firstMatch(source);
  if (catMatch != null) category = catMatch.group(1);

  // Classes and mixins.
  final classes = <DartClass>[];
  for (final m in _classPattern.allMatches(source)) {
    final name = m.group(1)!;
    if (name.startsWith('_')) continue;

    final declLine = source.substring(m.start, source.indexOf('\n', m.start));
    final isSealed = declLine.contains('sealed');
    final isAbstract = declLine.contains('abstract');

    final braceStart = source.indexOf('{', m.start);
    if (braceStart == -1) continue;
    final braceEnd = _findMatchingBrace(source, braceStart);
    final classBody = source.substring(braceStart, braceEnd + 1);

    final doc = _extractDocComment(source, m.start);
    final members = _extractMembers(classBody, name);

    classes.add(DartClass(
      name: name,
      docComment: doc,
      declaration: declLine.trim(),
      members: members,
      isSealed: isSealed,
      isAbstract: isAbstract,
    ));
  }

  // Enums.
  final enums = <DartEnum>[];
  for (final m in _enumPattern.allMatches(source)) {
    final name = m.group(1)!;
    if (name.startsWith('_')) continue;
    final doc = _extractDocComment(source, m.start);

    // Extract enum values.
    final braceStart = source.indexOf('{', m.start);
    final values = <String>[];
    if (braceStart != -1) {
      final braceEnd = _findMatchingBrace(source, braceStart);
      final body = source.substring(braceStart + 1, braceEnd);
      // Enum values are comma-separated identifiers before the first `;` or
      // method declaration.
      final valuesSection = body.split(RegExp(r'[;]'))[0].trim();
      // Split by commas and extract the identifier from each segment.
      for (final segment in valuesSection.split(',')) {
        final trimmed = segment.trim();
        if (trimmed.isEmpty) continue;
        // Skip doc comment lines.
        if (trimmed.startsWith('///') || trimmed.startsWith('//')) continue;
        // Strip any leading doc comments from multi-line segments.
        final lines = trimmed.split('\n');
        final lastLine = lines.last.trim();
        // The value name is the first identifier on the non-comment line.
        final idMatch = RegExp(r'^(\w+)').firstMatch(lastLine);
        if (idMatch != null) {
          final v = idMatch.group(1)!;
          if (!const {'const', 'final', 'static', 'void'}.contains(v)) {
            values.add(v);
          }
        }
      }
    }

    enums.add(DartEnum(name: name, docComment: doc, values: values));
  }

  // Top-level functions (skip those inside classes by checking indentation).
  final topLevelFunctions = <DartFunction>[];
  for (final m in _topLevelFunctionPattern.allMatches(source)) {
    final returnType = m.group(1)!.trim();
    final name = m.group(2)!;
    if (name.startsWith('_')) continue;
    // Skip class/enum keywords captured accidentally.
    if (['class', 'enum', 'mixin', 'import', 'export', 'if', 'for', 'while']
        .contains(returnType)) continue;
    if (['class', 'enum', 'mixin', 'import', 'export'].contains(name)) {
      continue;
    }
    final doc = _extractDocComment(source, m.start);
    final sig = '$returnType $name(${m.group(3)})';
    topLevelFunctions.add(
        DartFunction(name: name, signature: sig, docComment: doc));
  }

  // Top-level constants.
  final topLevelConstants = <DartConstant>[];
  for (final m in _topLevelConstPattern.allMatches(source)) {
    final type = m.group(1)!;
    final name = m.group(2)!;
    if (name.startsWith('_')) continue;
    final doc = _extractDocComment(source, m.start);
    topLevelConstants.add(DartConstant(name: name, type: type, docComment: doc));
  }

  return DartFile(
    relativePath: relativePath,
    module: module,
    content: source,
    libraryDoc: libraryDoc,
    category: category,
    classes: classes,
    enums: enums,
    topLevelFunctions: topLevelFunctions,
    topLevelConstants: topLevelConstants,
  );
}

// ---------------------------------------------------------------------------
// Markdown generation
// ---------------------------------------------------------------------------

String _generateMarkdown(DartFile df) {
  final buf = StringBuffer();

  // Use the title-cased filename as the page title (reads better than a
  // single class name when the file contains multiple types).
  final title = _titleCase(df.stem);
  buf.writeln('---');
  buf.writeln('title: $title');
  buf.writeln('---');
  buf.writeln();
  buf.writeln('# $title');
  buf.writeln();

  // Category.
  final cat = df.category ?? _moduleDisplayName(df.module);
  buf.writeln('> Category: $cat');
  buf.writeln();

  // Source link.
  final githubPath = df.relativePath;
  final filename = df.relativePath.split('/').last;
  buf.writeln(
      '*Source: [$filename]($_githubBase$githubPath)*');
  buf.writeln();

  // Library doc.
  if (df.libraryDoc != null && df.libraryDoc!.isNotEmpty) {
    buf.writeln(_escapeAngleBrackets(df.libraryDoc!));
    buf.writeln();
  }

  // Enums.
  if (df.enums.isNotEmpty) {
    buf.writeln('## Enums');
    buf.writeln();
    for (final e in df.enums) {
      buf.writeln('### `${e.name}`');
      buf.writeln();
      if (e.docComment != null) {
        buf.writeln(_escapeAngleBrackets(e.docComment!));
        buf.writeln();
      }
      if (e.values.isNotEmpty) {
        buf.writeln('| Value | Description |');
        buf.writeln('|-------|-------------|');
        for (final v in e.values) {
          buf.writeln('| `$v` | |');
        }
        buf.writeln();
      }
    }
  }

  // Classes.
  if (df.classes.isNotEmpty) {
    buf.writeln('## Classes');
    buf.writeln();
    for (final cls in df.classes) {
      final prefix = [
        if (cls.isSealed) 'sealed',
        if (cls.isAbstract) 'abstract',
      ].join(' ');
      final label = prefix.isEmpty ? '`${cls.name}`' : '$prefix `${cls.name}`';
      buf.writeln('### $label');
      buf.writeln();
      if (cls.docComment != null) {
        buf.writeln(_escapeAngleBrackets(cls.docComment!));
        buf.writeln();
      }

      // Split members by kind.
      final constructors =
          cls.members.where((m) => m.kind == 'constructor').toList();
      final methods = cls.members.where((m) => m.kind == 'method').toList();
      final properties = cls.members
          .where((m) => m.kind == 'property' || m.kind == 'getter')
          .toList();

      if (constructors.isNotEmpty) {
        buf.writeln('#### Constructor');
        buf.writeln();
        for (final c in constructors) {
          buf.writeln('```dart');
          buf.writeln(c.signature);
          buf.writeln('```');
          buf.writeln();
          if (c.docComment != null) {
            buf.writeln(_escapeAngleBrackets(c.docComment!));
            buf.writeln();
          }
        }
      }

      if (properties.isNotEmpty) {
        buf.writeln('#### Properties');
        buf.writeln();
        buf.writeln('| Property | Type | Description |');
        buf.writeln('|----------|------|-------------|');
        for (final p in properties) {
          final parts = p.signature.split(RegExp(r'\s+'));
          final type = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : '';
          final name = parts.last.replaceAll(RegExp(r'^get\s+'), '');
          final desc = p.docComment?.replaceAll('\n', ' ') ?? '';
          buf.writeln('| `${_escapeAngleBrackets(name)}` | `${_escapeAngleBrackets(type)}` | ${_escapeAngleBrackets(desc)} |');
        }
        buf.writeln();
      }

      if (methods.isNotEmpty) {
        buf.writeln('#### Methods');
        buf.writeln();
        for (final m in methods) {
          buf.writeln('##### `${_escapeAngleBrackets(m.signature)}`');
          buf.writeln();
          if (m.docComment != null) {
            buf.writeln(_escapeAngleBrackets(m.docComment!));
            buf.writeln();
          }
        }
      }
    }
  }

  // Top-level functions.
  if (df.topLevelFunctions.isNotEmpty) {
    buf.writeln('## Functions');
    buf.writeln();
    for (final f in df.topLevelFunctions) {
      buf.writeln('### `${_escapeAngleBrackets(f.signature)}`');
      buf.writeln();
      if (f.docComment != null) {
        buf.writeln(_escapeAngleBrackets(f.docComment!));
        buf.writeln();
      }
    }
  }

  // Top-level constants.
  if (df.topLevelConstants.isNotEmpty) {
    buf.writeln('## Constants');
    buf.writeln();
    buf.writeln('| Name | Type | Description |');
    buf.writeln('|------|------|-------------|');
    for (final c in df.topLevelConstants) {
      final desc = c.docComment?.replaceAll('\n', ' ') ?? '';
      buf.writeln('| `${c.name}` | `${_escapeAngleBrackets(c.type)}` | ${_escapeAngleBrackets(desc)} |');
    }
    buf.writeln();
  }

  return buf.toString();
}

// ---------------------------------------------------------------------------
// Sidebar generation
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _generateSidebar(
    Map<String, List<DartFile>> modules) {
  final sidebar = <Map<String, dynamic>>[];

  for (final mod in _moduleOrder) {
    final files = modules[mod];
    if (files == null || files.isEmpty) continue;

    // Sort files alphabetically.
    files.sort((a, b) => a.stem.compareTo(b.stem));

    final items = <Map<String, dynamic>>[];
    for (final f in files) {
      items.add({
        'text': f.primaryName,
        'link': '/api/${f.module}/${f.kebab}',
      });
    }

    sidebar.add({
      'text': _moduleDisplayName(mod),
      'collapsed': false,
      'items': items,
    });
  }

  // Any modules not in the predefined order.
  for (final mod in modules.keys) {
    if (_moduleOrder.contains(mod)) continue;
    final files = modules[mod]!;
    files.sort((a, b) => a.stem.compareTo(b.stem));
    final items = files
        .map((f) => {
              'text': f.primaryName,
              'link': '/api/${f.module}/${f.kebab}',
            })
        .toList();
    sidebar.add({
      'text': _moduleDisplayName(mod),
      'collapsed': false,
      'items': items,
    });
  }

  return sidebar;
}

// ---------------------------------------------------------------------------
// Index page
// ---------------------------------------------------------------------------

String _generateIndex(Map<String, List<DartFile>> modules) {
  final buf = StringBuffer();
  buf.writeln('---');
  buf.writeln('title: API Reference');
  buf.writeln('---');
  buf.writeln();
  buf.writeln('# API Reference');
  buf.writeln();
  buf.writeln('Glue CLI internals organized by module.');
  buf.writeln();
  buf.writeln('| Module | Description |');
  buf.writeln('|--------|-------------|');

  String linkForModule(String mod) {
    final files = modules[mod]!;
    files.sort((a, b) => a.stem.compareTo(b.stem));
    return '/api/$mod/${files.first.kebab}';
  }

  for (final mod in _moduleOrder) {
    if (!modules.containsKey(mod)) continue;
    final display = _moduleDisplayName(mod);
    final desc = _moduleDescriptions[mod] ?? '';
    buf.writeln('| [$display](${linkForModule(mod)}) | $desc |');
  }

  // Extras.
  for (final mod in modules.keys) {
    if (_moduleOrder.contains(mod)) continue;
    final display = _moduleDisplayName(mod);
    final desc = _moduleDescriptions[mod] ?? '';
    buf.writeln('| [$display](${linkForModule(mod)}) | $desc |');
  }

  buf.writeln();
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _moduleDisplayName(String mod) {
  if (_moduleDisplayNames.containsKey(mod)) return _moduleDisplayNames[mod]!;
  return mod[0].toUpperCase() + mod.substring(1);
}

String _titleCase(String snakeCase) {
  return snakeCase
      .split('_')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join('');
}

/// Escapes angle brackets for VitePress (Vue SFC) compatibility.
///
/// VitePress parses markdown as Vue single-file components, so `<Foo>` is
/// interpreted as a Vue component tag. We escape `<` and `>` so that generic
/// types like `Map<String, dynamic>` render correctly.
String _escapeAngleBrackets(String s) {
  return s.replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  final cliDir = Directory.current;
  final srcDir = Directory('${cliDir.path}/lib/src');
  final devdocsDir = Directory('${cliDir.path}/../devdocs');
  final apiDir = Directory('${devdocsDir.path}/api');
  final sidebarFile = File('${devdocsDir.path}/.vitepress/sidebar.json');

  if (!srcDir.existsSync()) {
    print('Error: ${srcDir.path} not found. Run from the cli/ directory.');
    exit(1);
  }

  // Collect all Dart files.
  final dartFiles = srcDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) {
    final name = f.uri.pathSegments.last;
    return !name.startsWith('_');
  }).toList();

  print('Found ${dartFiles.length} Dart files in lib/src/');

  // Parse all files.
  final parsed = <DartFile>[];
  for (final file in dartFiles) {
    final relative =
        file.path.replaceFirst('${srcDir.path}/', '');
    final parts = relative.split('/');
    final module = parts.length > 1 ? parts.first : 'core';
    parsed.add(_parseFile(file, relative, module));
  }

  // Group by module.
  final modules = <String, List<DartFile>>{};
  for (final df in parsed) {
    modules.putIfAbsent(df.module, () => []).add(df);
  }

  // Generate markdown files.
  var fileCount = 0;
  for (final df in parsed) {
    final outDir = Directory('${apiDir.path}/${df.module}');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final outFile = File('${outDir.path}/${df.kebab}.md');
    outFile.writeAsStringSync(_generateMarkdown(df));
    fileCount++;
  }

  // Generate sidebar.
  final sidebar = _generateSidebar(modules);
  sidebarFile.parent.createSync(recursive: true);
  final encoder = JsonEncoder.withIndent('  ');
  sidebarFile.writeAsStringSync(encoder.convert(sidebar));

  // Generate index.
  final indexFile = File('${apiDir.path}/index.md');
  apiDir.createSync(recursive: true);
  indexFile.writeAsStringSync(_generateIndex(modules));

  // Summary.
  print('Generated $fileCount API docs across ${modules.length} modules:');
  for (final mod in _moduleOrder) {
    if (!modules.containsKey(mod)) continue;
    print('  ${_moduleDisplayName(mod)}: ${modules[mod]!.length} files');
  }
  for (final mod in modules.keys) {
    if (_moduleOrder.contains(mod)) continue;
    print('  ${_moduleDisplayName(mod)}: ${modules[mod]!.length} files');
  }
  print('Sidebar: ${sidebarFile.path}');
  print('Index:   ${indexFile.path}');
  print('Done.');
}
