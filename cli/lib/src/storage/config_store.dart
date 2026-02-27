import 'dart:convert';
import 'dart:io';

class ConfigStore {
  final String path;

  ConfigStore(this.path);

  Map<String, dynamic> load() {
    final file = File(path);
    if (!file.existsSync()) return {};
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  void save(Map<String, dynamic> config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync(encoder.convert(config));
  }

  String? get defaultProvider => load()['default_provider'] as String?;
  String? get defaultModel => load()['default_model'] as String?;
  List<String> get trustedTools =>
      (load()['trusted_tools'] as List?)?.cast<String>() ?? [];
  bool get debug => (load()['debug'] as bool?) ?? true;
}
