import 'dart:io';

typedef GhRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class GistPublishError implements Exception {
  final String message;
  GistPublishError(this.message);

  @override
  String toString() => message;
}

class GistPublishResult {
  final String filePath;
  final String url;

  const GistPublishResult({
    required this.filePath,
    required this.url,
  });
}

class SessionGistPublisher {
  final GhRunner _runner;

  SessionGistPublisher({GhRunner? runner}) : _runner = runner ?? Process.run;

  Future<GistPublishResult> publish({
    required String filePath,
    required String description,
  }) async {
    if (!File(filePath).existsSync()) {
      throw GistPublishError('Markdown transcript not found: $filePath');
    }

    await _ensureAuthenticated();
    final result = await _runGh([
      'gist',
      'create',
      filePath,
      '--desc',
      description,
    ]);
    if (result.exitCode != 0) {
      throw GistPublishError(_failureMessage(
        prefix: 'GitHub CLI failed to create a gist.',
        result: result,
      ));
    }

    final url = _extractUrl(result.stdout.toString());
    if (url == null) {
      throw GistPublishError(
        'GitHub CLI did not return a gist URL after creation.',
      );
    }

    return GistPublishResult(filePath: filePath, url: url);
  }

  Future<void> _ensureAuthenticated() async {
    final result = await _runGh(['auth', 'status']);
    if (result.exitCode == 0) return;

    throw GistPublishError(_failureMessage(
      prefix:
          'GitHub CLI is not authenticated. Run `gh auth login` and try again.',
      result: result,
    ));
  }

  Future<ProcessResult> _runGh(List<String> arguments) async {
    try {
      return await _runner('gh', arguments);
    } on ProcessException {
      throw GistPublishError(
        'GitHub CLI (`gh`) is not installed or not available on PATH.',
      );
    }
  }

  String? _extractUrl(String output) {
    final match = RegExp(r'https://gist\.github\.com/\S+').firstMatch(output);
    return match?.group(0);
  }

  String _failureMessage({
    required String prefix,
    required ProcessResult result,
  }) {
    final stderr = result.stderr.toString().trim();
    final stdout = result.stdout.toString().trim();
    final detail = stderr.isNotEmpty ? stderr : stdout;
    if (detail.isEmpty) return prefix;
    return '$prefix $detail';
  }
}
