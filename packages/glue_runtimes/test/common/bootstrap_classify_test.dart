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

    test('classifies GitHub "Repository not found" (private repo, no creds) as '
        'auth — not a missing git binary', () {
      // Regression for M25: the remote URL contains "git" (github.com)
      // and the message contains "not found", so the missing-binary
      // heuristic (`not found` + `git`) used to misfire here.
      final r = classifyCloneFailure(
        'remote: Repository not found.\n'
        "fatal: repository 'https://github.com/acme/private.git/' not found",
      );
      expect(r.kind, BootstrapErrorKind.auth);
      expect(r.kind, isNot(BootstrapErrorKind.missingBinary));
      expect(r.hint, isNotNull);
    });

    test('classifies bare "remote: Repository not found." as auth', () {
      final r = classifyCloneFailure('remote: Repository not found.');
      expect(r.kind, BootstrapErrorKind.auth);
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
