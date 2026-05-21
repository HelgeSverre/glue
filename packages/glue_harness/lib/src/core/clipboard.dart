/// Writes text to the system clipboard across platforms.
///
/// Tries a platform-specific list of commands in order (on Linux there are
/// several clipboard tools; try each). Stdin is the only input path — no
/// shell interpretation, so arbitrary binary-safe text works.
///
/// The runner is injectable; tests supply a fake to avoid spawning a real
/// `pbcopy` / `clip` / `wl-copy`.
library;

import 'dart:convert';
import 'dart:io';

class ClipboardProcess {
  const ClipboardProcess({required this.stdin, required this.exitCode});
  final IOSink stdin;
  final Future<int> exitCode;
}

typedef ClipboardRunner =
    Future<ClipboardProcess> Function(
      String executable,
      List<String> arguments,
    );

/// Sink used to emit OSC52 escape sequences. Defaults to stdout; tests
/// override this with a buffer so they can assert on the payload without
/// spamming the real terminal.
typedef Osc52Writer = void Function(String payload);

/// Maximum OSC52 payload size before we refuse to emit. The DCS framing
/// most terminals use to receive OSC52 has a length limit (~100KB is the
/// upper bound; 74KB stays well under it after base64 expansion).
const int osc52MaxBytes = 74 * 1024;

/// Whether the current process is running under a multiplexed or remote
/// shell where host clipboard tools can't reach the user's real clipboard.
/// In those environments the only path that works is OSC52.
bool _remoteOrMultiplexedSession([Map<String, String>? envOverride]) {
  final env = envOverride ?? Platform.environment;
  return env['TMUX'] != null ||
      env['SSH_CONNECTION'] != null ||
      env['SSH_TTY'] != null;
}

/// Encode [text] as an OSC52 set-clipboard escape sequence. When inside
/// tmux (detected by the `TMUX` env var), wrap the sequence in tmux's
/// passthrough DCS so it reaches the outer terminal. Returns `null` if
/// the payload exceeds [osc52MaxBytes] — caller falls back.
String? encodeOsc52(String text, {Map<String, String>? env}) {
  final bytes = utf8.encode(text);
  if (bytes.length > osc52MaxBytes) return null;
  final b64 = base64.encode(bytes);
  final raw = '\x1b]52;c;$b64\x1b\\';
  final environment = env ?? Platform.environment;
  if (environment['TMUX'] != null) {
    // tmux passthrough: \ePtmux;\e<original-with-each-\e-doubled>\e\\
    final escaped = raw.replaceAll('\x1b', '\x1b\x1b');
    return '\x1bPtmux;$escaped\x1b\\';
  }
  return raw;
}

/// Copies [text] to the system clipboard.
///
/// Strategy:
/// 1. If running under tmux or SSH, try OSC52 first (host commands usually
///    can't see the user's real clipboard from there) and fall back to
///    host commands only if OSC52 is unavailable.
/// 2. Otherwise try host commands first (pbcopy/clip/wl-copy/xclip/xsel),
///    then OSC52 as last resort.
///
/// Never throws — process-launch failures (`ProcessException`) and
/// non-zero exits fall through to the next candidate. Returns `false`
/// only if every candidate failed.
Future<bool> copyToClipboard(
  String text, {
  ClipboardRunner? runner,
  Osc52Writer? osc52Writer,
  Map<String, String>? environmentOverride,
}) async {
  final env = environmentOverride ?? Platform.environment;
  final preferOsc52 = _remoteOrMultiplexedSession(env);

  if (preferOsc52 && _tryOsc52(text, writer: osc52Writer, env: env)) {
    return true;
  }
  if (await _tryHostCommands(text, runner: runner)) {
    return true;
  }
  if (!preferOsc52 && _tryOsc52(text, writer: osc52Writer, env: env)) {
    return true;
  }
  return false;
}

bool _tryOsc52(
  String text, {
  Osc52Writer? writer,
  required Map<String, String> env,
}) {
  final payload = encodeOsc52(text, env: env);
  if (payload == null) return false;
  try {
    (writer ?? stdout.write).call(payload);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _tryHostCommands(String text, {ClipboardRunner? runner}) async {
  final run = runner ?? _defaultRunner;
  for (final (exe, args) in _clipboardCommands()) {
    try {
      final process = await run(exe, args);
      process.stdin.write(text);
      await process.stdin.close();
      final code = await process.exitCode;
      if (code == 0) return true;
    } catch (_) {
      // Contract: never throw. Any failure (ProcessException, SocketException
      // from pipe close, etc.) falls through to the next candidate.
    }
  }
  return false;
}

Future<ClipboardProcess> _defaultRunner(
  String executable,
  List<String> arguments,
) async {
  final p = await Process.start(executable, arguments);
  return ClipboardProcess(stdin: p.stdin, exitCode: p.exitCode);
}

List<(String, List<String>)> _clipboardCommands() {
  if (Platform.isMacOS) {
    return [('pbcopy', const [])];
  }
  if (Platform.isWindows) {
    return [('clip', const [])];
  }
  if (Platform.isLinux) {
    return [
      ('wl-copy', const []),
      ('xclip', const ['-selection', 'clipboard']),
      ('xsel', const ['--clipboard', '--input']),
    ];
  }
  return const [];
}
