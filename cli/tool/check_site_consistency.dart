// ignore_for_file: avoid_print
/// Consistency checks for the unified getglue.dev site.
///
/// Run via: `dart run tool/check_site_consistency.dart` from the cli/ directory.
/// Wired into `just site-check` so every PR exercises it.
///
/// Checks:
///   1. Every `<FeatureStatus status="..." />` uses an allowed value.
///   2. No page outside `/roadmap` or `/changelog` mentions "interaction
///      mode", "plan mode", "Langfuse", "OTEL", or "OpenTelemetry" — those
///      are removed per the simplification plan.
///   3. The home page (`index.md`) contains no `planned` status pill.
///   4. `docs/snippets/install.md` is the single install command — no other
///      marketing page hand-writes `curl .../install.sh`.
///   5. `data/feature-status.yaml` parses cleanly.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

const _siteRoot = '../website';
const _featureStatusYaml = '../website/data/feature-status.yaml';

const _allowedStatuses = {'shipping', 'experimental', 'planned'};

// Pages we intentionally allow to discuss removed features (history, roadmap,
// the pages that explain the simplification). The rule stays strict for the
// home hero, /features, /models, /runtimes, /web, and anything not listed here.
const _removalAllowlist = {
  'roadmap.md',
  'changelog.md',
  'why.md',
  'sessions.md',
  'docs/advanced/observability.md',
  'docs/contributing/architecture.md',
};

// Removed terms that must not appear on the live site (outside allowlist).
const _bannedTerms = [
  'interaction mode',
  'interaction_mode',
  'plan mode',
  'plan-mode',
  'Langfuse',
  'OpenTelemetry',
  'OTEL',
];

int _failures = 0;

void main() {
  print('Checking site consistency in $_siteRoot/ ...');

  _checkFeatureStatusYaml();
  _checkFeatureStatusUsage();
  _checkBannedTerms();
  _checkHomeNoPlanned();
  _checkInstallSnippetSingleSource();

  if (_failures > 0) {
    print('\n✗ $_failures consistency check(s) failed.');
    exit(1);
  }
  print('\n✓ All site consistency checks passed.');
}

void _fail(String msg) {
  _failures++;
  print('  ✗ $msg');
}

// ---------------------------------------------------------------------------

void _checkFeatureStatusYaml() {
  final file = File(_featureStatusYaml);
  if (!file.existsSync()) {
    _fail('$_featureStatusYaml is missing.');
    return;
  }
  try {
    final yaml = loadYaml(file.readAsStringSync()) as YamlMap;
    final features = yaml['features'] as YamlMap?;
    if (features == null || features.isEmpty) {
      _fail('feature-status.yaml has no `features:` entries.');
      return;
    }
    for (final entry in features.entries) {
      final value = entry.value as YamlMap;
      final status = value['status']?.toString();
      if (status == null) {
        _fail('Feature `${entry.key}` has no `status:` field.');
        continue;
      }
      if (!{..._allowedStatuses, 'removed'}.contains(status)) {
        _fail('Feature `${entry.key}` uses unknown status `$status`.');
      }
    }
  } catch (e) {
    _fail('feature-status.yaml failed to parse: $e');
  }
}

// ---------------------------------------------------------------------------

void _checkFeatureStatusUsage() {
  final pattern = RegExp(r'''<FeatureStatus\s+status=["'](\w+)["']''');
  for (final file in _siteMarkdownFiles()) {
    final text = file.readAsStringSync();
    for (final match in pattern.allMatches(text)) {
      final status = match.group(1)!;
      if (!_allowedStatuses.contains(status)) {
        _fail(
          '${_rel(file)}: <FeatureStatus status="$status" /> '
          'not in {${_allowedStatuses.join(", ")}}.',
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------

void _checkBannedTerms() {
  for (final file in _siteMarkdownFiles()) {
    final rel = _rel(file);
    if (_removalAllowlist.contains(rel)) continue;
    final text = file.readAsStringSync();
    for (final term in _bannedTerms) {
      final re = RegExp(RegExp.escape(term), caseSensitive: false);
      final match = re.firstMatch(text);
      if (match != null) {
        final line = _lineOf(text, match.start);
        _fail('$rel:$line mentions removed feature `$term`.');
      }
    }
  }
}

// ---------------------------------------------------------------------------

void _checkHomeNoPlanned() {
  final home = File('$_siteRoot/index.md');
  if (!home.existsSync()) return;
  final text = home.readAsStringSync();
  // Look specifically for planned pills inside the hero region.
  // The hero is everything before the first `## ` heading.
  final firstH2 = text.indexOf('\n## ');
  final hero = firstH2 == -1 ? text : text.substring(0, firstH2);
  if (RegExp(r'''<FeatureStatus\s+status=["']planned["']''').hasMatch(hero)) {
    _fail(
      'index.md: a `planned` <FeatureStatus> pill appears in the home hero. '
      'Planned features belong on /roadmap, not the hero.',
    );
  }
}

// ---------------------------------------------------------------------------

void _checkInstallSnippetSingleSource() {
  final installLine =
      RegExp(r'curl\s+-fsSL\s+https://getglue\.dev/install\.sh');
  for (final file in _siteMarkdownFiles()) {
    if (_rel(file) == 'snippets/install.md') continue;
    final text = file.readAsStringSync();
    final match = installLine.firstMatch(text);
    if (match != null) {
      final line = _lineOf(text, match.start);
      _fail(
        '${_rel(file)}:$line hand-writes the install command. '
        'Use <InstallSnippet /> instead so snippets/install.md stays the single source.',
      );
    }
  }
}

// ---------------------------------------------------------------------------

Iterable<File> _siteMarkdownFiles() sync* {
  final root = Directory(_siteRoot);
  if (!root.existsSync()) return;
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.md')) continue;
    // Skip node_modules, dist, cache, and auto-generated API reference.
    final rel = _rel(entity);
    if (rel.startsWith('node_modules/')) continue;
    if (rel.startsWith('.vitepress/dist/')) continue;
    if (rel.startsWith('.vitepress/cache/')) continue;
    if (rel.startsWith('api/')) continue;
    if (rel.startsWith('generated/')) continue;
    yield entity;
  }
}

String _rel(File f) {
  final abs = f.absolute.path;
  final rootAbs = Directory(_siteRoot).absolute.path;
  if (abs.startsWith(rootAbs)) {
    return abs.substring(rootAbs.length).replaceAll(RegExp(r'^/'), '');
  }
  return abs;
}

int _lineOf(String text, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}
