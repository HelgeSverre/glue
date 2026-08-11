library;

import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/src/config/config_file.dart';
import 'package:glue_harness/src/config/config_template.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

class ConversationConfigWriteError implements Exception {
  ConversationConfigWriteError(this.message);

  final String message;

  @override
  String toString() => 'ConversationConfigWriteError: $message';
}

/// Surgically updates conversation defaults in `config.yaml`.
class ConversationConfigWriter {
  ConversationConfigWriter(this.configPath);

  final String configPath;

  void setModelAndReasoning(ModelRef model, ReasoningConfig reasoning) {
    _mutate((editor, root) {
      editor.update(['active_model'], model.toString());
      _updateReasoning(editor, root, reasoning);
    });
  }

  void setReasoning(ReasoningConfig reasoning) {
    _mutate((editor, root) => _updateReasoning(editor, root, reasoning));
  }

  void _updateReasoning(
    YamlEditor editor,
    Map<dynamic, dynamic> root,
    ReasoningConfig reasoning,
  ) {
    if (root['reasoning'] is Map) {
      editor
        ..update(['reasoning', 'effort'], reasoning.effort.name)
        ..update(['reasoning', 'show_thoughts'], reasoning.showThoughts);
      return;
    }
    editor.update(
      ['reasoning'],
      wrapAsYamlNode({
        'effort': reasoning.effort.name,
        'show_thoughts': reasoning.showThoughts,
      }, collectionStyle: CollectionStyle.BLOCK),
    );
  }

  void _mutate(
    void Function(YamlEditor editor, Map<dynamic, dynamic> root) operation,
  ) {
    try {
      final file = _resolveDestination();
      final original = file.existsSync()
          ? file.readAsStringSync()
          : buildConfigTemplate();
      final parsed = _parse(original);
      final root = switch (parsed) {
        final Map<dynamic, dynamic> map => map,
        null => <dynamic, dynamic>{},
        _ => throw ConversationConfigWriteError(
          'Refusing to update config.yaml because its root is not a mapping.',
        ),
      };
      final editableSource = parsed == null
          ? _appendEmptyMapping(original)
          : original;

      final editor = YamlEditor(editableSource);
      operation(editor, root);
      final updated = editor.toString();
      _validate(updated);

      file.parent.createSync(recursive: true);
      final temporary = File(
        '${file.path}.${pid.toString()}.'
        '${DateTime.now().microsecondsSinceEpoch.toString()}.tmp',
      );
      try {
        temporary.writeAsStringSync(updated, flush: true);
        temporary.renameSync(file.path);
      } finally {
        if (temporary.existsSync()) temporary.deleteSync();
      }
    } on ConversationConfigWriteError {
      rethrow;
    } on Exception catch (error) {
      throw ConversationConfigWriteError(
        'Could not update config.yaml: $error',
      );
    }
  }

  Object? _parse(String source) {
    try {
      return loadYaml(source);
    } on Exception catch (error) {
      throw ConversationConfigWriteError(
        'Refusing to update an invalid config.yaml ($error).',
      );
    }
  }

  String _appendEmptyMapping(String source) {
    final separator = source.isEmpty || source.endsWith('\n') ? '' : '\n';
    return '$source$separator{}\n';
  }

  File _resolveDestination() {
    var path = p.normalize(p.absolute(configPath));
    final visited = <String>{};

    while (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.link) {
      if (!visited.add(path)) {
        throw ConversationConfigWriteError(
          'Could not update config.yaml: symbolic link cycle detected.',
        );
      }
      final target = Link(path).targetSync();
      path = p.normalize(
        p.isAbsolute(target) ? target : p.join(p.dirname(path), target),
      );
    }

    return File(path);
  }

  void _validate(String source) {
    try {
      final parsed = loadYaml(source);
      if (parsed is! Map) {
        throw const FormatException('document root is not a mapping');
      }
      ConfigFileMapper.fromMap(_stringKeyedMap(parsed));
    } on Exception catch (error) {
      throw ConversationConfigWriteError(
        'Refusing to write: result would not parse ($error).',
      );
    }
  }

  Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> source) => {
    for (final entry in source.entries)
      entry.key.toString(): _plainValue(entry.value),
  };

  Object? _plainValue(Object? value) => switch (value) {
    final Map<dynamic, dynamic> map => _stringKeyedMap(map),
    final List<dynamic> list => list.map(_plainValue).toList(),
    _ => value,
  };
}
