import 'package:args/args.dart';

List<String> normalizeCliArgs(List<String> args) {
  final normalized = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--resume=')) {
      normalized.add('--resume-id=${arg.substring('--resume='.length)}');
      continue;
    }
    if (arg == '--resume' || arg == '-r') {
      final next = i + 1 < args.length ? args[i + 1] : null;
      if (next != null && !_looksLikeOption(next)) {
        normalized.add('--resume-id=$next');
        i++;
        continue;
      }
    }
    normalized.add(arg);
  }
  return normalized;
}

bool _looksLikeOption(String arg) => arg.startsWith('-');

ArgParser buildTestArgParser() {
  return ArgParser()
    ..addFlag('version', abbr: 'v', negatable: false)
    ..addFlag('print', abbr: 'p', negatable: false)
    ..addFlag('json', negatable: false)
    ..addOption('model', abbr: 'm')
    ..addFlag('resume', abbr: 'r', negatable: false)
    ..addOption('resume-id')
    ..addFlag('continue', negatable: false)
    ..addFlag('debug', abbr: 'd', negatable: false);
}
