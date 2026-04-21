import 'package:args/args.dart';
import 'package:glue/glue.dart';
import 'package:test/test.dart';

// We test against the same arg parser configuration used in GlueCommandRunner.
// Duplicated here to avoid importing the bin/ entry point which calls exit().
ArgParser _buildArgParser() {
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

void main() {
  late ArgParser parser;

  setUp(() {
    parser = _buildArgParser();
  });

  group('--resume / -r', () {
    test('bare --resume sets the startup resume-panel flag', () {
      final result = parser.parse(['--resume']);
      expect(result.flag('resume'), isTrue);
    });

    test('bare -r sets the startup resume-panel flag', () {
      final result = parser.parse(['-r']);
      expect(result.flag('resume'), isTrue);
    });

    test('resume flag is false when not provided', () {
      final result = parser.parse([]);
      expect(result.flag('resume'), isFalse);
    });

    test('--resume-id accepts a session ID value', () {
      final result = parser.parse(['--resume-id', '1772331272529-72']);
      expect(result.option('resume-id'), '1772331272529-72');
    });
  });

  group('positional args (prompt)', () {
    test('single quoted string becomes rest', () {
      final result = parser.parse(['review my code']);
      expect(result.rest, ['review my code']);
    });

    test('multiple positional args in rest', () {
      final result = parser.parse(['review', 'my', 'code']);
      expect(result.rest, ['review', 'my', 'code']);
      expect(result.rest.join(' '), 'review my code');
    });

    test('positional args alongside flags', () {
      final result = parser.parse(['-m', 'opus', 'explain this']);
      expect(result.option('model'), 'opus');
      expect(result.rest, ['explain this']);
    });

    test('no positional args means empty rest', () {
      final result = parser.parse(['-m', 'sonnet']);
      expect(result.rest, isEmpty);
    });
  });

  group('--print / -p', () {
    test('-p sets print flag', () {
      final result = parser.parse(['-p', 'hello']);
      expect(result.flag('print'), isTrue);
      expect(result.rest, ['hello']);
    });

    test('--print sets print flag', () {
      final result = parser.parse(['--print', 'hello']);
      expect(result.flag('print'), isTrue);
    });

    test('print is false by default', () {
      final result = parser.parse([]);
      expect(result.flag('print'), isFalse);
    });
  });

  group('--json', () {
    test('sets json flag', () {
      final result = parser.parse(['--json', 'summarize this']);
      expect(result.flag('json'), isTrue);
    });

    test('json is false by default', () {
      final result = parser.parse([]);
      expect(result.flag('json'), isFalse);
    });
  });

  group('--model / -m', () {
    test('accepts model alias', () {
      final result = parser.parse(['-m', 'opus']);
      expect(result.option('model'), 'opus');
    });

    test('accepts full model name', () {
      final result = parser.parse(['-m', 'claude-opus-4-6']);
      expect(result.option('model'), 'claude-opus-4-6');
    });
  });

  group('combined flags', () {
    test('-p -m opus with prompt', () {
      final result = parser.parse(['-p', '-m', 'opus', 'review this code']);
      expect(result.flag('print'), isTrue);
      expect(result.option('model'), 'opus');
      expect(result.rest, ['review this code']);
    });

    test('--resume-id session-id -p with prompt', () {
      final result = parser.parse([
        '--resume-id',
        'sess-123',
        '-p',
        'continue work',
      ]);
      expect(result.option('resume-id'), 'sess-123');
      expect(result.flag('print'), isTrue);
      expect(result.rest, ['continue work']);
    });

    test('--json implies --print should be handled by caller', () {
      final result = parser.parse(['--json', 'summarize']);
      expect(result.flag('json'), isTrue);
      // Note: --json implying --print is handled in _runApp, not the parser
      expect(result.flag('print'), isFalse);
    });
  });

  group('App.buildPrintPrompt (stdin + prompt)', () {
    test('prompt only', () {
      final result = App.buildPrintPrompt(prompt: 'explain this');
      expect(result, 'explain this');
    });

    test('stdin only', () {
      final result = App.buildPrintPrompt(stdinContent: 'file contents here');
      expect(result, '<stdin>\nfile contents here</stdin>');
    });

    test('stdin + prompt combines with tags', () {
      final result = App.buildPrintPrompt(
        prompt: 'summarize this file',
        stdinContent: 'line 1\nline 2',
      );
      expect(result, '<stdin>\nline 1\nline 2</stdin>\n\nsummarize this file');
    });

    test('empty prompt with stdin uses stdin only', () {
      final result = App.buildPrintPrompt(
        prompt: '',
        stdinContent: 'data',
      );
      expect(result, '<stdin>\ndata</stdin>');
    });

    test('both null returns empty string', () {
      final result = App.buildPrintPrompt();
      expect(result, isEmpty);
    });
  });
}
