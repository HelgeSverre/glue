/// Top-level `glue catalog …` subcommands.
///
/// `refresh` fetches the canonical model catalog into the user's cache so
/// `~/.glue/cache/models.yaml` overlays the bundled snapshot on next start.
/// `show` prints the active merged catalog. `path` reports where each layer
/// is resolved from. `open` opens the canonical URL in a browser. `edit`
/// opens the cached `models.yaml` in `$EDITOR`.
///
/// The `/model` slash command remains the interactive surface inside a
/// running session; this CLI surface is for scripted setup and diagnostics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/tty_style.dart';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';

const _jsonEncoder = JsonEncoder.withIndent('  ');

/// Default sources tried by `glue catalog refresh` when the user has not set
/// `catalog.remote_url`. Points at the canonical copy in the GitHub repo;
/// the marketing site does not publish a `models.yaml` artifact.
const defaultCatalogUrls = <String>[
  'https://raw.githubusercontent.com/helgesverre/glue/main/docs/reference/models.yaml',
];

/// Outcome of [refreshCatalog]. Exposed so the CLI surface and tests can
/// inspect what happened without scraping stdout.
sealed class RefreshOutcome {
  const RefreshOutcome();
}

class RefreshWrote extends RefreshOutcome {
  const RefreshWrote({required this.uri, required this.bytes});
  final Uri uri;
  final int bytes;
}

class RefreshNotModified extends RefreshOutcome {
  const RefreshNotModified({required this.uri});
  final Uri uri;
}

class RefreshAllFailed extends RefreshOutcome {
  const RefreshAllFailed({required this.failures});

  /// Pairs of (uri, reason) in the order they were attempted.
  final List<({Uri uri, String reason})> failures;
}

/// Tries [candidates] in order. Stops on the first [FetchUpdated] or
/// [FetchNotModified]; collects [FetchFailed] reasons otherwise. The
/// optional [onAttempt] callback fires with each URL before the fetch, so
/// the CLI surface can render progress without `refreshCatalog` taking on
/// presentation concerns.
Future<RefreshOutcome> refreshCatalog({
  required List<Uri> candidates,
  required String cachePath,
  required RemoteCatalogFetcher fetcher,
  void Function(Uri uri)? onAttempt,
}) async {
  final failures = <({Uri uri, String reason})>[];
  for (final uri in candidates) {
    onAttempt?.call(uri);
    final result = await fetcher.fetch(uri);
    switch (result) {
      case FetchUpdated(:final yaml):
        final file = File(cachePath);
        file.parent.createSync(recursive: true);
        final tmp = File('$cachePath.tmp');
        tmp.writeAsStringSync(yaml);
        tmp.renameSync(file.path);
        return RefreshWrote(uri: uri, bytes: file.lengthSync());
      case FetchNotModified():
        return RefreshNotModified(uri: uri);
      case FetchFailed(:final reason):
        failures.add((uri: uri, reason: reason));
    }
  }
  return RefreshAllFailed(failures: failures);
}

class CatalogCommand extends Command<int> {
  CatalogCommand() {
    addSubcommand(CatalogRefreshCommand());
    addSubcommand(CatalogShowCommand());
    addSubcommand(CatalogPathCommand());
    addSubcommand(CatalogOpenCommand());
    addSubcommand(CatalogEditCommand());
  }

  @override
  String get name => 'catalog';

  @override
  String get description => 'Inspect and refresh the bundled model catalog.';
}

class CatalogRefreshCommand extends Command<int> {
  CatalogRefreshCommand({this._fetcher}) {
    argParser
      ..addOption(
        'url',
        help:
            'Override the source URL for this run. Tried before the '
            'configured `catalog.remote_url` and the built-in defaults.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit the refresh outcome as JSON instead of styled text. '
            'Suppresses progress lines so output is a single document.',
      );
  }

  final RemoteCatalogFetcher? _fetcher;

  @override
  String get name => 'refresh';

  @override
  String get description =>
      'Download the latest model catalog into ~/.glue/cache/models.yaml.';

  @override
  String get invocation => 'glue catalog refresh [--url <url>] [--json]';

  @override
  Future<int> run() async {
    final env = Environment.detect();
    final config = _safeLoadConfig();
    if (config == null) return 1;

    final asJson = argResults!.flag('json');
    final flagUrl = argResults!.option('url');
    final candidates = <Uri>[
      if (flagUrl != null) Uri.parse(flagUrl),
      if (config.catalog.remoteUrl != null) config.catalog.remoteUrl!,
      for (final raw in defaultCatalogUrls) Uri.parse(raw),
    ];

    final cachePath = env.catalogCachePath;

    if (!asJson) {
      stdout.writeln(
        '$brandDot ${styledOrPlain('Refreshing catalog', (s) => s.bold)}',
      );
    }

    final outcome = await refreshCatalog(
      candidates: candidates,
      cachePath: cachePath,
      fetcher: _fetcher ?? RemoteCatalogFetcher(),
      onAttempt: asJson
          ? null
          : (uri) => stdout.writeln(
              '  $markerInfo ${styledOrPlain(uri.toString(), (s) => s.gray)}',
            ),
    );

    if (asJson) {
      stdout.writeln(_jsonEncoder.convert(_refreshJson(outcome, cachePath)));
      return outcome is RefreshAllFailed ? 1 : 0;
    }

    switch (outcome) {
      case RefreshWrote(:final bytes):
        stdout.writeln(
          '  $markerOk ${styledOrPlain('wrote', (s) => s.green)} $cachePath  '
          '${styledOrPlain('($bytes bytes)', (s) => s.gray)}',
        );
        return 0;
      case RefreshNotModified():
        stdout.writeln(
          '  $markerOk ${styledOrPlain('up to date', (s) => s.green)} '
          '${styledOrPlain('(304 Not Modified)', (s) => s.gray)}',
        );
        return 0;
      case RefreshAllFailed(:final failures):
        for (final f in failures) {
          stderr.writeln(
            '  $markerError ${styledOrPlain(f.uri.host, (s) => s.red)}  '
            '${styledOrPlain(f.reason, (s) => s.gray)}',
          );
        }
        stderr.writeln();
        stderr.writeln(
          '  ${styledOrPlain('Failed to refresh catalog.', (s) => s.red)}',
        );
        return 1;
    }
  }
}

Map<String, dynamic> _refreshJson(RefreshOutcome outcome, String cachePath) {
  return switch (outcome) {
    RefreshWrote(:final uri, :final bytes) => {
      'outcome': 'wrote',
      'url': uri.toString(),
      'cachePath': cachePath,
      'bytes': bytes,
    },
    RefreshNotModified(:final uri) => {
      'outcome': 'notModified',
      'url': uri.toString(),
      'cachePath': cachePath,
    },
    RefreshAllFailed(:final failures) => {
      'outcome': 'failed',
      'cachePath': cachePath,
      'attempts': failures
          .map((f) => {'url': f.uri.toString(), 'reason': f.reason})
          .toList(),
    },
  };
}

class CatalogShowCommand extends Command<int> {
  CatalogShowCommand() {
    argParser.addFlag(
      'json',
      negatable: false,
      help:
          'Emit the catalog as JSON instead of styled text. Suppresses '
          'all brand styling and headers so the output is pipe-safe.',
    );
  }

  @override
  String get name => 'show';

  @override
  String get description =>
      'Print the merged model catalog (bundled + cache + overrides).';

  @override
  Future<int> run() async {
    final config = _safeLoadConfig();
    if (config == null) return 1;

    final catalog = config.catalogData;

    if (argResults!.flag('json')) {
      stdout.writeln(_jsonEncoder.convert(_catalogJson(catalog)));
      return 0;
    }

    final defaults = catalog.defaults;
    stdout.writeln('$brandDot ${styledOrPlain('Glue Catalog', (s) => s.bold)}');
    stdout.writeln(
      '  ${styledOrPlain('version ${catalog.version}  ·  updated ${catalog.updatedAt}', (s) => s.gray)}',
    );
    stdout.writeln();

    stdout.writeln(
      '  ${styledOrPlain('default', (s) => s.gray)} ${defaults.model}',
    );
    if (defaults.smallModel != null) {
      stdout.writeln(
        '  ${styledOrPlain('small  ', (s) => s.gray)} ${defaults.smallModel}',
      );
    }
    if (defaults.localModel != null) {
      stdout.writeln(
        '  ${styledOrPlain('local  ', (s) => s.gray)} ${defaults.localModel}',
      );
    }

    final providers = catalog.providers.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final provider in providers) {
      stdout.writeln();
      final disabledTag = provider.enabled
          ? ''
          : '  ${styledOrPlain('(disabled)', (s) => s.dim.red)}';
      stdout.writeln(
        '${styledOrPlain(provider.id, (s) => s.bold)}  '
        '${styledOrPlain(provider.name, (s) => s.gray)}$disabledTag',
      );
      final models = provider.models.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      // Per-provider column widths. Pad raw text before applying styling
      // so ANSI escape sequences don't skew the visible width.
      final idWidth = models
          .map((m) => m.id.length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      final nameWidth = models
          .map((m) => m.name.length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      for (final model in models) {
        final flags = <String>[
          if (model.isDefault)
            '$markerOk ${styledOrPlain('default', (s) => s.green)}',
          if (model.recommended) '$markerInfo recommended',
          if (!model.enabled)
            '$markerWarn ${styledOrPlain('disabled', (s) => s.yellow)}',
        ];
        // Only pad name when followed by flags — avoids trailing whitespace
        // on the last column for flag-less rows.
        final paddedName = flags.isEmpty
            ? model.name
            : model.name.padRight(nameWidth);
        final suffix = flags.isEmpty ? '' : '  ${flags.join('  ')}';
        stdout.writeln(
          '  ${model.id.padRight(idWidth)}  ${styledOrPlain(paddedName, (s) => s.gray)}$suffix',
        );
      }
    }
    return 0;
  }
}

Map<String, dynamic> _catalogJson(ModelCatalog catalog) {
  return {
    'version': catalog.version,
    'updatedAt': catalog.updatedAt,
    'defaults': {
      'model': catalog.defaults.model,
      if (catalog.defaults.smallModel != null)
        'smallModel': catalog.defaults.smallModel,
      if (catalog.defaults.localModel != null)
        'localModel': catalog.defaults.localModel,
    },
    'providers':
        (catalog.providers.values.toList()
              ..sort((a, b) => a.id.compareTo(b.id)))
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'enabled': p.enabled,
                'models':
                    (p.models.values.toList()
                          ..sort((a, b) => a.id.compareTo(b.id)))
                        .map(
                          (m) => {
                            'id': m.id,
                            'name': m.name,
                            'default': m.isDefault,
                            'recommended': m.recommended,
                            'enabled': m.enabled,
                          },
                        )
                        .toList(),
              },
            )
            .toList(),
  };
}

class CatalogPathCommand extends Command<int> {
  CatalogPathCommand() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit the path layers as JSON instead of styled text.',
    );
  }

  @override
  String get name => 'path';

  @override
  String get description =>
      'Print the filesystem paths the catalog is loaded from.';

  @override
  Future<int> run() async {
    final env = Environment.detect();
    final cachePath = env.catalogCachePath;
    final overridePath = env.modelsYamlPath;
    final cachePresent = File(cachePath).existsSync();
    final overridePresent = File(overridePath).existsSync();

    if (argResults!.flag('json')) {
      stdout.writeln(
        _jsonEncoder.convert({
          'bundled': 'compiled into binary',
          'cachedRemote': {'path': cachePath, 'present': cachePresent},
          'localOverride': {'path': overridePath, 'present': overridePresent},
          'mergeOrder': ['bundled', 'cachedRemote', 'localOverride'],
        }),
      );
      return 0;
    }

    String status(bool present) => present
        ? '$markerOk ${styledOrPlain('present', (s) => s.green)}'
        : '$markerWarn ${styledOrPlain('missing', (s) => s.yellow)}';

    stdout.writeln(
      '$brandDot ${styledOrPlain('Catalog paths', (s) => s.bold)}',
    );
    stdout.writeln();
    stdout.writeln(
      '  ${styledOrPlain('bundled       ', (s) => s.bold)} '
      '${styledOrPlain('compiled into binary', (s) => s.gray)}',
    );
    stdout.writeln(
      '  ${styledOrPlain('cached remote ', (s) => s.bold)} '
      '${styledOrPlain(cachePath, (s) => s.gray)}  ${status(cachePresent)}',
    );
    stdout.writeln(
      '  ${styledOrPlain('local override', (s) => s.bold)} '
      '${styledOrPlain(overridePath, (s) => s.gray)}  ${status(overridePresent)}',
    );
    stdout.writeln();
    stdout.writeln(
      '  ${styledOrPlain('merge order: bundled → cached remote → local override', (s) => s.dim)}',
    );
    return 0;
  }
}

class CatalogOpenCommand extends Command<int> {
  CatalogOpenCommand() {
    argParser.addFlag(
      'print',
      negatable: false,
      help:
          'Print the URL instead of launching a browser. Useful for '
          'piping into other tools or running in headless shells.',
    );
  }

  @override
  String get name => 'open';

  @override
  String get description =>
      'Open the canonical models.yaml URL in your default browser.';

  @override
  String get invocation => 'glue catalog open [--print]';

  @override
  Future<int> run() async {
    final config = _safeLoadConfig();
    if (config == null) return 1;

    final url =
        config.catalog.remoteUrl?.toString() ?? defaultCatalogUrls.first;
    final printOnly = argResults!.flag('print');

    if (printOnly) {
      stdout.writeln(url);
      return 0;
    }

    stdout.writeln(
      '$brandDot ${styledOrPlain('Opening catalog', (s) => s.bold)}',
    );
    stdout.writeln('  $markerInfo ${styledOrPlain(url, (s) => s.gray)}');

    final launched = await _openBrowser(url);
    if (!launched) {
      stderr.writeln(
        '  $markerWarn ${styledOrPlain('no browser launcher available on this platform', (s) => s.yellow)}',
      );
      stderr.writeln(
        '  ${styledOrPlain('Copy the URL above to open it manually.', (s) => s.gray)}',
      );
      return 1;
    }
    return 0;
  }
}

class CatalogEditCommand extends Command<int> {
  @override
  String get name => 'edit';

  @override
  String get description => r'Open the cached models.yaml in $EDITOR.';

  @override
  String get invocation => 'glue catalog edit';

  @override
  Future<int> run() async {
    final env = Environment.detect();
    final cachePath = env.catalogCachePath;

    if (!File(cachePath).existsSync()) {
      stderr.writeln(
        '$brandDot ${styledOrPlain('Edit catalog', (s) => s.bold)}',
      );
      stderr.writeln(
        '  $markerWarn ${styledOrPlain('no cached catalog at', (s) => s.yellow)} '
        '${styledOrPlain(cachePath, (s) => s.gray)}',
      );
      stderr.writeln();
      stderr.writeln(
        '  ${styledOrPlain('Run', (s) => s.gray)} '
        '${styledOrPlain('glue catalog refresh', (s) => s.bold)} '
        '${styledOrPlain('to download the latest catalog.', (s) => s.gray)}',
      );
      return 1;
    }

    final editor = Platform.environment['EDITOR']?.trim();
    if (editor == null || editor.isEmpty) {
      stderr.writeln(
        '$brandDot ${styledOrPlain('Edit catalog', (s) => s.bold)}',
      );
      stderr.writeln(
        '  $markerError ${styledOrPlain(r'$EDITOR is not set', (s) => s.red)}',
      );
      stderr.writeln(
        '  ${styledOrPlain(r'Set $EDITOR to your preferred editor (e.g. vim, nano, code).', (s) => s.gray)}',
      );
      return 1;
    }

    stdout.writeln(
      '$brandDot ${styledOrPlain('Editing catalog', (s) => s.bold)}',
    );
    stdout.writeln(
      '  $markerInfo ${styledOrPlain(editor, (s) => s.gray)} ${styledOrPlain(cachePath, (s) => s.gray)}',
    );

    final result = await Process.start(
      editor,
      [cachePath],
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );
    return result.exitCode;
  }
}

Future<bool> _openBrowser(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
      return true;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      return true;
    }
    if (Platform.isWindows) {
      await Process.start('rundll32', [
        'url.dll,FileProtocolHandler',
        url,
      ], mode: ProcessStartMode.detached);
      return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}

GlueConfig? _safeLoadConfig() {
  try {
    return GlueConfig.load(environment: Environment.detect());
  } on ConfigError catch (e) {
    stderr.writeln('Failed to load config: ${e.message}');
    return null;
  }
}
