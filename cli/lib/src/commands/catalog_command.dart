/// Top-level `glue catalog …` subcommands.
///
/// `refresh` fetches the canonical model catalog into the user's cache so
/// `~/.glue/cache/models.yaml` overlays the bundled snapshot on next start.
/// `show` prints the active merged catalog. `path` reports where each layer
/// is resolved from.
///
/// The `/model` slash command remains the interactive surface inside a
/// running session; this CLI surface is for scripted setup and diagnostics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';

const _jsonEncoder = JsonEncoder.withIndent('  ');

/// Brand dot used in headers across the Glue CLI surface (doctor, catalog).
/// Kept in sync with `renderDoctorReport` in `src/doctor/doctor.dart`.
String get _brandDot => '●'.styled.rgb(250, 204, 21).toString();

/// Doctor-style severity markers, reused so `catalog` reads as a sibling of
/// `doctor`. See `_marker` in `src/doctor/doctor.dart`.
String get _markerOk => '✓'.styled.green.toString();
String get _markerInfo => '·'.styled.gray.toString();
String get _markerWarn => '!'.styled.yellow.toString();
String get _markerError => '✗'.styled.red.toString();

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
  }

  @override
  String get name => 'catalog';

  @override
  String get description => 'Inspect and refresh the bundled model catalog.';
}

class CatalogRefreshCommand extends Command<int> {
  CatalogRefreshCommand({RemoteCatalogFetcher? fetcher}) : _fetcher = fetcher {
    argParser
      ..addOption(
        'url',
        help: 'Override the source URL for this run. Tried before the '
            'configured `catalog.remote_url` and the built-in defaults.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the refresh outcome as JSON instead of styled text. '
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

    final cachePath = Platform.environment['GLUE_CATALOG_CACHE'] ??
        '${env.cacheDir}/models.yaml';

    if (!asJson) stdout.writeln('$_brandDot ${'Refreshing catalog'.styled.bold}');

    final outcome = await refreshCatalog(
      candidates: candidates,
      cachePath: cachePath,
      fetcher: _fetcher ?? RemoteCatalogFetcher(),
      onAttempt: asJson
          ? null
          : (uri) =>
              stdout.writeln('  $_markerInfo ${uri.toString().styled.gray}'),
    );

    if (asJson) {
      stdout.writeln(_jsonEncoder.convert(_refreshJson(outcome, cachePath)));
      return outcome is RefreshAllFailed ? 1 : 0;
    }

    switch (outcome) {
      case RefreshWrote(:final bytes):
        stdout.writeln(
          '  $_markerOk ${'wrote'.styled.green} $cachePath  '
          '${'($bytes bytes)'.styled.gray}',
        );
        return 0;
      case RefreshNotModified():
        stdout.writeln(
          '  $_markerOk ${'up to date'.styled.green} '
          '${'(304 Not Modified)'.styled.gray}',
        );
        return 0;
      case RefreshAllFailed(:final failures):
        for (final f in failures) {
          stderr.writeln(
            '  $_markerError ${f.uri.host.styled.red}  '
            '${f.reason.styled.gray}',
          );
        }
        stderr.writeln();
        stderr.writeln('  ${'Failed to refresh catalog.'.styled.red}');
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
      help: 'Emit the catalog as JSON instead of styled text. Suppresses '
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
    stdout.writeln('$_brandDot ${'Glue Catalog'.styled.bold}');
    stdout.writeln(
      '  ${'version ${catalog.version}  ·  updated ${catalog.updatedAt}'.styled.gray}',
    );
    stdout.writeln();

    stdout.writeln('  ${'default'.styled.gray} ${defaults.model}');
    if (defaults.smallModel != null) {
      stdout.writeln('  ${'small  '.styled.gray} ${defaults.smallModel}');
    }
    if (defaults.localModel != null) {
      stdout.writeln('  ${'local  '.styled.gray} ${defaults.localModel}');
    }

    final providers = catalog.providers.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final provider in providers) {
      stdout.writeln();
      final disabledTag =
          provider.enabled ? '' : '  ${'(disabled)'.styled.dim.red}';
      stdout.writeln(
        '${provider.id.styled.bold}  ${provider.name.styled.gray}$disabledTag',
      );
      final models = provider.models.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      // Per-provider column widths. Pad raw text before applying styling
      // so ANSI escape sequences don't skew the visible width.
      final idWidth =
          models.map((m) => m.id.length).fold<int>(0, (a, b) => a > b ? a : b);
      final nameWidth = models
          .map((m) => m.name.length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      for (final model in models) {
        final flags = <String>[
          if (model.isDefault) '$_markerOk ${'default'.styled.green}',
          if (model.recommended) '$_markerInfo recommended',
          if (!model.enabled) '$_markerWarn ${'disabled'.styled.yellow}',
        ];
        // Only pad name when followed by flags — avoids trailing whitespace
        // on the last column for flag-less rows.
        final paddedName = flags.isEmpty
            ? model.name
            : model.name.padRight(nameWidth);
        final suffix = flags.isEmpty ? '' : '  ${flags.join('  ')}';
        stdout.writeln(
          '  ${model.id.padRight(idWidth)}  ${paddedName.styled.gray}$suffix',
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
    'providers': (catalog.providers.values.toList()
          ..sort((a, b) => a.id.compareTo(b.id)))
        .map((p) => {
              'id': p.id,
              'name': p.name,
              'enabled': p.enabled,
              'models': (p.models.values.toList()
                    ..sort((a, b) => a.id.compareTo(b.id)))
                  .map((m) => {
                        'id': m.id,
                        'name': m.name,
                        'default': m.isDefault,
                        'recommended': m.recommended,
                        'enabled': m.enabled,
                      })
                  .toList(),
            })
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
    final cachePath = Platform.environment['GLUE_CATALOG_CACHE'] ??
        '${env.cacheDir}/models.yaml';
    final overridePath = env.modelsYamlPath;
    final cachePresent = File(cachePath).existsSync();
    final overridePresent = File(overridePath).existsSync();

    if (argResults!.flag('json')) {
      stdout.writeln(_jsonEncoder.convert({
        'bundled': 'compiled into binary',
        'cachedRemote': {'path': cachePath, 'present': cachePresent},
        'localOverride': {'path': overridePath, 'present': overridePresent},
        'mergeOrder': ['bundled', 'cachedRemote', 'localOverride'],
      }));
      return 0;
    }

    String status(bool present) => present
        ? '$_markerOk ${'present'.styled.green}'
        : '$_markerWarn ${'missing'.styled.yellow}';

    stdout.writeln('$_brandDot ${'Catalog paths'.styled.bold}');
    stdout.writeln();
    stdout.writeln(
      '  ${'bundled       '.styled.bold} ${'compiled into binary'.styled.gray}',
    );
    stdout.writeln(
      '  ${'cached remote '.styled.bold} ${cachePath.styled.gray}  ${status(cachePresent)}',
    );
    stdout.writeln(
      '  ${'local override'.styled.bold} ${overridePath.styled.gray}  ${status(overridePresent)}',
    );
    stdout.writeln();
    stdout.writeln(
      '  ${'merge order: bundled → cached remote → local override'.styled.dim}',
    );
    return 0;
  }
}

GlueConfig? _safeLoadConfig() {
  try {
    return GlueConfig.load(environment: Environment.detect());
  } on ConfigError catch (e) {
    stderr.writeln('Failed to load config: ${e.message}');
    return null;
  }
}
