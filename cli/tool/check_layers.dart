// ignore_for_file: avoid_print, unused_field
/// Layer-import linter for `cli/lib/src/`.
///
/// Enforces the layered architecture defined in
/// `docs/plans/2026-04-29-harness-layers.md`:
///
///   surface  →  harness  →  strategies  →  transport
///
/// **Today's enforcement**: harness and strategies share a rank (they are
/// peers in the current codebase because data types like `Message` and
/// `ToolCall` haven't yet moved to a `glue_core` package — until then,
/// strategies legitimately import from harness data subsystems). The only
/// rule the linter enforces today is the surface↔non-surface boundary.
///
/// **Future tightening**: once `glue_core` is extracted (step 4 of the
/// migration plan), restore harness rank above strategies and let the
/// linter flag the strategies→harness imports that remain.
///
/// Usage:
///   dart run tool/check_layers.dart            # warn-only, exit 0
///   dart run tool/check_layers.dart --strict   # exit 1 on violations
///   dart run tool/check_layers.dart --json     # machine-readable output
///   dart run tool/check_layers.dart --aspirational
///       # report future strategies→harness violations as well (advisory)
///
/// CI runs the warn-only mode initially. The plan is to flip to `--strict`
/// once the existing worklist is cleared.
library;

import 'dart:convert';
import 'dart:io';

/// Each subsystem under `lib/src/` is assigned a layer. Subsystems not listed
/// here are treated as unknown and skipped (they do not produce violations
/// but are reported in the summary).
const _subsystemLayers = <String, _Layer>{
  // Surface
  'app': _Layer.surface,
  'commands': _Layer.surface,
  'doctor': _Layer.surface,
  'input': _Layer.surface,
  'rendering': _Layer.surface,
  'terminal': _Layer.surface,
  'ui': _Layer.surface,

  // Harness
  'agent': _Layer.harness,
  'catalog': _Layer.harness,
  'config': _Layer.harness,
  'core': _Layer.harness,
  'extensions': _Layer.harness,
  'observability': _Layer.harness,
  'orchestrator': _Layer.harness,
  'session': _Layer.harness,
  'share': _Layer.harness,
  'skills': _Layer.harness,
  'storage': _Layer.harness,
  'tools': _Layer.harness,

  // Strategies
  'credentials': _Layer.strategies,
  'llm': _Layer.strategies,
  'providers': _Layer.strategies,
  'shell': _Layer.strategies,
  'web': _Layer.strategies,

  // Proposed core — pure data types, the staging area for the future
  // `glue_core` package. Below strategies, so any subsystem can import.
  '_proposed_core': _Layer.core,
};

enum _Layer {
  surface(3, 'surface'),
  // harness and strategies share rank 1 today — see file-level dartdoc.
  // The aspirationalRank field records the future split so we can flag
  // future-violations under --aspirational without enforcing them now.
  harness(1, 'harness', aspirationalRank: 2),
  strategies(1, 'strategies'),
  // Pure data types — no behavior, no I/O. Strictly below strategies so
  // any subsystem can import them. This is the future `glue_core` package.
  core(0, 'core'),
  // Reserved — no subsystem maps to it today, but keeping the rank stable
  // means future transport-layer subsystems just need a _subsystemLayers entry.
  transport(0, 'transport');

  const _Layer(this.rank, this.name, {int? aspirationalRank})
      : aspirationalRank = aspirationalRank ?? rank;

  /// Rank used in default mode.
  final int rank;

  /// Rank used under `--aspirational`. Currently differs only for harness
  /// (which will rise above strategies once `glue_core` is extracted).
  final int aspirationalRank;

  final String name;
}

void main(List<String> args) {
  final strict = args.contains('--strict');
  final asJson = args.contains('--json');
  final aspirational = args.contains('--aspirational');
  final root = Directory('lib/src');
  if (!root.existsSync()) {
    stderr.writeln('check_layers: lib/src not found (run from cli/)');
    exit(2);
  }

  final violations = <_Violation>[];
  final unknownSubsystems = <String>{};

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;

    final relPath = entity.path.replaceFirst(RegExp(r'^\./?'), '');
    final fromSubsystem = _subsystemOf(relPath);
    if (fromSubsystem == null) continue;

    final fromLayer = _subsystemLayers[fromSubsystem];
    if (fromLayer == null) {
      unknownSubsystems.add(fromSubsystem);
      continue;
    }

    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final match = _importPattern.firstMatch(lines[i]);
      if (match == null) continue;

      final imported = match.group(1)!;
      final toSubsystem = _subsystemOfImport(imported);
      if (toSubsystem == null) continue;
      if (toSubsystem == fromSubsystem) continue;

      final toLayer = _subsystemLayers[toSubsystem];
      if (toLayer == null) {
        unknownSubsystems.add(toSubsystem);
        continue;
      }

      final fromRank =
          aspirational ? fromLayer.aspirationalRank : fromLayer.rank;
      final toRank = aspirational ? toLayer.aspirationalRank : toLayer.rank;
      if (toRank > fromRank) {
        violations.add(
          _Violation(
            file: relPath,
            line: i + 1,
            fromSubsystem: fromSubsystem,
            fromLayer: fromLayer,
            toSubsystem: toSubsystem,
            toLayer: toLayer,
            importPath: imported,
          ),
        );
      }
    }
  }

  if (asJson) {
    final payload = {
      'violations': violations.map((v) => v.toJson()).toList(),
      'unknownSubsystems': unknownSubsystems.toList()..sort(),
      'count': violations.length,
      'strict': strict,
    };
    print(const JsonEncoder.withIndent('  ').convert(payload));
  } else {
    _printHumanReport(violations, unknownSubsystems, strict: strict);
  }

  if (strict && violations.isNotEmpty) {
    exit(1);
  }
}

final _importPattern = RegExp(
  r'''^\s*import\s+['"](package:glue/[^'"]+)['"]''',
);

String? _subsystemOf(String filePath) {
  // Expect lib/src/<subsystem>/...
  final parts = filePath.split(Platform.pathSeparator);
  final libIdx = parts.indexOf('lib');
  if (libIdx < 0 || parts.length <= libIdx + 3) return null;
  if (parts[libIdx + 1] != 'src') return null;
  final candidate = parts[libIdx + 2];
  // Files directly under lib/src/ (e.g. app.dart) are not subsystem files.
  if (candidate.endsWith('.dart')) return null;
  return candidate;
}

String? _subsystemOfImport(String importUri) {
  // `package:glue/src/<subsystem>/...`
  const prefix = 'package:glue/src/';
  if (!importUri.startsWith(prefix)) return null;
  final rest = importUri.substring(prefix.length);
  final slash = rest.indexOf('/');
  if (slash < 0) return null;
  return rest.substring(0, slash);
}

void _printHumanReport(
  List<_Violation> violations,
  Set<String> unknownSubsystems, {
  required bool strict,
}) {
  if (violations.isEmpty) {
    print('check_layers: no layer violations found');
  } else {
    print('check_layers: ${violations.length} layer violation(s)\n');
    final byPair = <String, List<_Violation>>{};
    for (final v in violations) {
      final key = '${v.fromSubsystem} (${v.fromLayer.name}) → '
          '${v.toSubsystem} (${v.toLayer.name})';
      (byPair[key] ??= <_Violation>[]).add(v);
    }
    for (final entry in byPair.entries) {
      print('  ${entry.key}  [${entry.value.length}]');
      for (final v in entry.value) {
        print('    ${v.file}:${v.line}  ${v.importPath}');
      }
      print('');
    }
  }

  if (unknownSubsystems.isNotEmpty) {
    print('check_layers: unknown subsystems (add to _subsystemLayers): '
        '${unknownSubsystems.toList()..sort()}');
  }

  if (!strict && violations.isNotEmpty) {
    print('check_layers: WARN-ONLY mode — pass --strict to fail the build');
  }
}

class _Violation {
  _Violation({
    required this.file,
    required this.line,
    required this.fromSubsystem,
    required this.fromLayer,
    required this.toSubsystem,
    required this.toLayer,
    required this.importPath,
  });

  final String file;
  final int line;
  final String fromSubsystem;
  final _Layer fromLayer;
  final String toSubsystem;
  final _Layer toLayer;
  final String importPath;

  Map<String, dynamic> toJson() => {
        'file': file,
        'line': line,
        'from': {'subsystem': fromSubsystem, 'layer': fromLayer.name},
        'to': {'subsystem': toSubsystem, 'layer': toLayer.name},
        'import': importPath,
      };
}
