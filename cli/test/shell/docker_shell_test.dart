// Standalone test script for verifying ShellCompleter in Docker containers.
//
// Run with: dart run test/shell/docker_shell_test.dart
// Expects the target shell to be installed in the container.
import 'dart:io';

import 'package:glue/src/shell/shell_completer.dart';

int _passed = 0;
int _failed = 0;

void check(String name, bool condition, [String? detail]) {
  if (condition) {
    _passed++;
    stdout.writeln('  ✓ $name');
  } else {
    _failed++;
    stdout.writeln('  ✗ $name${detail != null ? ' — $detail' : ''}');
  }
}

Future<void> testTokenStart() async {
  stdout.writeln('\n── tokenStart ──');
  final c = ShellCompleter(shellType: ShellType.bash);
  check('empty → 0', c.tokenStart('') == 0);
  check('"ls" → 0', c.tokenStart('ls') == 0);
  check('"git checkout" → 4', c.tokenStart('git checkout') == 4);
  check('"cat " → 4', c.tokenStart('cat ') == 4);
  check('"git checkout --fo" → 13', c.tokenStart('git checkout --fo') == 13);
}

Future<void> testBash() async {
  stdout.writeln('\n── bash completion ──');
  final c = ShellCompleter(shellType: ShellType.bash);

  // Check bash is available.
  final which = await Process.run('which', ['bash']);
  if (which.exitCode != 0) {
    stdout.writeln('  SKIP: bash not found');
    return;
  }

  // Command completion.
  final cmds = await c.complete('ech');
  check('compgen -c "ech" returns results', cmds.isNotEmpty,
      'got ${cmds.length} results');
  check('"echo" is in results', cmds.any((r) => r.text == 'echo'),
      'results: ${cmds.map((r) => r.text).take(10).toList()}');

  // File completion in temp dir.
  final dir = Directory.systemTemp.createTempSync('docker_test_');
  try {
    File('${dir.path}/alpha.txt').createSync();
    File('${dir.path}/alpha_two.txt').createSync();
    Directory('${dir.path}/alpha_dir').createSync();

    final files = await c.complete('ls ${dir.path}/alpha');
    check('compgen -f returns file results', files.isNotEmpty,
        'got ${files.length} results');

    final texts = files.map((r) => r.text).toSet();
    check('alpha.txt in results', texts.contains('${dir.path}/alpha.txt'),
        'results: $texts');
    check('alpha_two.txt in results',
        texts.contains('${dir.path}/alpha_two.txt'), 'results: $texts');
    check('alpha_dir in results', texts.contains('${dir.path}/alpha_dir'),
        'results: $texts');

    // Check isDirectory flag.
    final dirCandidate = files.where((r) => r.text.endsWith('alpha_dir'));
    check('alpha_dir marked as directory',
        dirCandidate.isNotEmpty && dirCandidate.first.isDirectory);

    final fileCandidate = files.where((r) => r.text.endsWith('alpha.txt'));
    check('alpha.txt not marked as directory',
        fileCandidate.isNotEmpty && !fileCandidate.first.isDirectory);
  } finally {
    dir.deleteSync(recursive: true);
  }

  // Empty token after space — should complete files in cwd.
  final cwd = await c.complete('ls ');
  check('compgen -f "" returns cwd files', cwd.isNotEmpty,
      'got ${cwd.length} results');
}

Future<void> testFish() async {
  stdout.writeln('\n── fish completion ──');
  final c = ShellCompleter(shellType: ShellType.fish);

  // Check fish is available.
  final which = await Process.run('which', ['fish']);
  if (which.exitCode != 0) {
    stdout.writeln('  SKIP: fish not found');
    return;
  }

  // Command completion.
  final cmds = await c.complete('echo');
  check('complete -C "echo" returns results', cmds.isNotEmpty,
      'got ${cmds.length} results');
  check('"echo" is in results', cmds.any((r) => r.text == 'echo'),
      'results: ${cmds.map((r) => r.text).take(10).toList()}');

  // Fish provides descriptions.
  final withDesc = cmds.where((r) => r.description != null);
  check('some results have descriptions', withDesc.isNotEmpty,
      '${withDesc.length}/${cmds.length} have descriptions');

  // File completion.
  final dir = Directory.systemTemp.createTempSync('docker_test_fish_');
  try {
    File('${dir.path}/beta.txt').createSync();
    Directory('${dir.path}/beta_dir').createSync();

    final files = await c.complete('ls ${dir.path}/beta');
    check('fish file completion returns results', files.isNotEmpty,
        'got ${files.length} results');
  } finally {
    dir.deleteSync(recursive: true);
  }
}

Future<void> testZsh() async {
  stdout.writeln('\n── zsh completion (bash fallback) ──');
  // zsh falls back to bash-style compgen.
  final c = ShellCompleter(shellType: ShellType.zsh);

  final which = await Process.run('which', ['bash']);
  if (which.exitCode != 0) {
    stdout.writeln('  SKIP: bash not found (zsh uses bash fallback)');
    return;
  }

  final cmds = await c.complete('ech');
  check('zsh (bash fallback) compgen -c "ech" works', cmds.isNotEmpty,
      'got ${cmds.length} results');
  check('"echo" in zsh results', cmds.any((r) => r.text == 'echo'));
}

Future<void> testSh() async {
  stdout.writeln('\n── sh completion (bash fallback) ──');
  final c = ShellCompleter(shellType: ShellType.sh);

  final which = await Process.run('which', ['bash']);
  if (which.exitCode != 0) {
    stdout.writeln('  SKIP: bash not found (sh uses bash fallback)');
    return;
  }

  final cmds = await c.complete('ech');
  check('sh (bash fallback) compgen -c "ech" works', cmds.isNotEmpty,
      'got ${cmds.length} results');
  check('"echo" in sh results', cmds.any((r) => r.text == 'echo'));
}

Future<void> testShellDetection() async {
  stdout.writeln('\n── shell detection ──');
  final shell = Platform.environment['SHELL'] ?? '(unset)';
  final c = ShellCompleter();
  stdout.writeln('  \$SHELL=$shell → detected: ${c.shellType}');
  check('\$SHELL parsed without error', true);
}

Future<void> main() async {
  stdout.writeln('=== ShellCompleter Docker Test ===');
  stdout.writeln('Platform: ${Platform.operatingSystem}');
  stdout.writeln('\$SHELL: ${Platform.environment['SHELL'] ?? '(unset)'}');

  await testTokenStart();
  await testShellDetection();
  await testBash();
  await testFish();
  await testZsh();
  await testSh();

  stdout.writeln('\n══════════════════════════════');
  stdout.writeln('Passed: $_passed  Failed: $_failed');
  if (_failed > 0) {
    exit(1);
  }
  stdout.writeln('All checks passed!');
}
