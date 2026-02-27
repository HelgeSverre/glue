import 'dart:convert';
import 'dart:io';

class ConfigStore {
  final String path;
  Map<String, dynamic> _cache = const {};
  DateTime? _lastMtime;
  int? _lastSize;
  bool _loaded = false;

  ConfigStore(this.path);

  Map<String, dynamic> load() {
    _ensureLoaded();
    return Map<String, dynamic>.from(_cache);
  }

  void _ensureLoaded() {
    final file = File(path);

    if (!file.existsSync()) {
      _cache = {};
      _lastMtime = null;
      _lastSize = null;
      _loaded = true;
      return;
    }

    final stat = file.statSync();
    final changed =
        !_loaded || _lastMtime != stat.modified || _lastSize != stat.size;

    if (!changed) return;

    try {
      final decoded = jsonDecode(file.readAsStringSync());
      _cache = (decoded is Map<String, dynamic>) ? decoded : {};
    } catch (_) {
      // Keep last-known-good cache on parse error
      if (!_loaded) _cache = {};
    }
    _lastMtime = stat.modified;
    _lastSize = stat.size;
    _loaded = true;
  }

  void save(Map<String, dynamic> config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(encoder.convert(config));
    tmp.renameSync(path);

    _cache = Map<String, dynamic>.from(config);
    final stat = file.statSync();
    _lastMtime = stat.modified;
    _lastSize = stat.size;
    _loaded = true;
  }

  void update(void Function(Map<String, dynamic> c) mutate) {
    _ensureLoaded();
    final next = Map<String, dynamic>.from(_cache);
    mutate(next);
    save(next);
  }

  String? get defaultProvider {
    _ensureLoaded();
    return _cache['default_provider'] as String?;
  }

  String? get defaultModel {
    _ensureLoaded();
    return _cache['default_model'] as String?;
  }

  List<String> get trustedTools {
    _ensureLoaded();
    return (_cache['trusted_tools'] as List?)?.cast<String>() ?? const [];
  }

  bool get debug {
    _ensureLoaded();
    return (_cache['debug'] as bool?) ?? true;
  }
}
