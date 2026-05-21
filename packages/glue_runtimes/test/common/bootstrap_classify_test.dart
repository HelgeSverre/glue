import 'package:test/test.dart';

import 'package:glue_runtimes/src/common/bootstrap.dart';

void main() {
  group('classifyCloneFailure', () {
    test('classifies 401 as auth', () {
      final r = classifyCloneFailure('fatal: Authentication failed for ...');
      expect(r.kind, BootstrapErrorKind.auth);
      expect(r.hint, isNotNull);
    });

    test('classifies username-prompt as auth', () {
      final r = classifyCloneFailure(
        'fatal: could not read Username for \'https://github.com\'',
      );
      expect(r.kind, BootstrapErrorKind.auth);
    });

    test('classifies SSH publickey rejection as auth', () {
      final r = classifyCloneFailure('Permission denied (publickey)');
      expect(r.kind, BootstrapErrorKind.auth);
    });

    test('classifies SAML enforcement as saml', () {
      final r = classifyCloneFailure('SAML enforcement requires authorization');
      expect(r.kind, BootstrapErrorKind.saml);
      expect(r.hint, contains('SAML'));
    });

    test('classifies DNS failure as network', () {
      final r = classifyCloneFailure('Could not resolve host: github.com');
      expect(r.kind, BootstrapErrorKind.network);
    });

    test('classifies timeout as network', () {
      final r = classifyCloneFailure('Connection timed out');
      expect(r.kind, BootstrapErrorKind.network);
    });

    test('classifies missing git binary', () {
      final r = classifyCloneFailure('sh: git: command not found');
      expect(r.kind, BootstrapErrorKind.missingBinary);
    });

    test('falls back to unknown when no pattern matches', () {
      final r = classifyCloneFailure(
        'some weird git internal error 0xdeadbeef',
      );
      expect(r.kind, BootstrapErrorKind.unknown);
      expect(r.hint, isNull);
    });
  });
}
