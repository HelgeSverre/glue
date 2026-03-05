import 'dart:io';

import 'package:glue/src/core/environment.dart';
import 'package:path/path.dart' as p;

class PlanDocument {
  final String title;
  final String path;
  final String source;
  final DateTime modifiedAt;
  final int sizeBytes;

  const PlanDocument({
    required this.title,
    required this.path,
    required this.source,
    required this.modifiedAt,
    required this.sizeBytes,
  });
}

/// Discovers markdown plan files from global and workspace locations.
class PlanStore {
  final Environment _environment;
  final String _cwd;

  const PlanStore({
    required Environment environment,
    required String cwd,
  })  : _environment = environment,
        _cwd = cwd;

  List<PlanDocument> listPlans({int maxResults = 300}) {
    final docs = <PlanDocument>[];
    final seen = <String>{};

    void addFile(File file, String source) {
      if (!file.existsSync()) return;
      final absolute = p.normalize(p.absolute(file.path));
      if (!seen.add(absolute)) return;

      final stat = file.statSync();
      final title =
          _extractTitle(file) ?? p.basenameWithoutExtension(file.path);
      docs.add(PlanDocument(
        title: title,
        path: absolute,
        source: source,
        modifiedAt: stat.modified,
        sizeBytes: stat.size,
      ));
    }

    void scanDirectory(String dirPath, String source) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final base = p.basename(entity.path);
        if (!base.toLowerCase().endsWith('.md')) continue;
        addFile(entity, source);
      }
    }

    scanDirectory(_environment.plansDir, 'global');
    scanDirectory(p.join(_cwd, 'docs', 'plans'), 'workspace');
    scanDirectory(p.join(_cwd, 'plans'), 'workspace');
    _scanWorkspaceRoot(addFile);

    docs.sort((a, b) {
      final timeCompare = b.modifiedAt.compareTo(a.modifiedAt);
      if (timeCompare != 0) return timeCompare;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    if (docs.length > maxResults) {
      return docs.sublist(0, maxResults);
    }
    return docs;
  }

  String readPlan(String path) {
    final file = File(path);
    return file.readAsStringSync();
  }

  void _scanWorkspaceRoot(void Function(File file, String source) addFile) {
    final dir = Directory(_cwd);
    if (!dir.existsSync()) return;
    final candidates = dir.listSync(followLinks: false);
    for (final entity in candidates) {
      if (entity is! File) continue;
      final base = p.basename(entity.path);
      final lower = base.toLowerCase();
      if (!lower.endsWith('.md')) continue;
      if (_isPlanLikeRootFile(base)) {
        addFile(entity, 'workspace');
      }
    }
  }

  bool _isPlanLikeRootFile(String name) {
    final lower = name.toLowerCase();
    if (lower == 'plan.md') return true;
    if (lower == 'roadmap.md') return true;
    if (lower == 'implementation_plan.md') return true;
    if (lower.contains('plan')) return true;
    if (lower.contains('roadmap')) return true;
    return false;
  }

  String? _extractTitle(File file) {
    try {
      final lines = file.readAsLinesSync();
      for (final line in lines.take(40)) {
        final trimmed = line.trim();
        if (trimmed.startsWith('# ')) {
          return trimmed.substring(2).trim();
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
