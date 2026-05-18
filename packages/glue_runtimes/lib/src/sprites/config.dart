/// Configuration for the Sprites runtime adapter.
///
/// Glue's sprites adapter wraps the official `sprite` CLI rather than
/// hitting the REST/WebSocket API directly. The CLI's exec protocol
/// (`control-ws`) is binary, in active RC flux (the CLI at
/// `v0.0.1-rc30` auto-upgrades to `rc43` mid-session), and the only
/// stable REST surface today is sprite lifecycle — there's no
/// `/filesystem` endpoint in the current API. Re-implementing the
/// exec wire protocol in Dart would be a treadmill of catching up
/// with breaking changes. The CLI is also already authenticated via
/// the user's Fly.io account, so glue doesn't need to manage tokens.
///
/// Trade-off: requires the `sprite` binary in `$PATH` and the user
/// to have run `sprite login`. Both surfaced by `glue doctor`.
class SpritesConfig {
  /// Path to the `sprite` binary. Override if it lives outside
  /// `$PATH` (e.g. test harnesses).
  final String spriteCliPath;

  /// User-chosen sprite name. When `null`, [SpritesRuntime.start]
  /// generates a unique name. Re-using a name across sessions resumes
  /// the existing sprite — sprites are persistent and auto-sleep when
  /// idle.
  final String? spriteName;

  /// When `true` (default), [SpritesRuntime.close] deletes the sprite
  /// on shutdown. Set to `false` to keep the sprite for the next
  /// session — it'll auto-sleep, costing nothing while asleep.
  final bool deleteOnClose;

  /// How long to wait for a freshly-created sprite to become ready.
  final Duration startTimeout;

  /// Cap on how long a single exec call may run before being killed.
  /// Per-call timeouts override via the optional `timeout` parameter.
  final Duration execTimeout;

  const SpritesConfig({
    this.spriteCliPath = 'sprite',
    this.spriteName,
    this.deleteOnClose = true,
    this.startTimeout = const Duration(minutes: 2),
    this.execTimeout = const Duration(minutes: 30),
  });

  SpritesConfig copyWith({
    String? spriteCliPath,
    String? spriteName,
    bool? deleteOnClose,
    Duration? startTimeout,
    Duration? execTimeout,
  }) =>
      SpritesConfig(
        spriteCliPath: spriteCliPath ?? this.spriteCliPath,
        spriteName: spriteName ?? this.spriteName,
        deleteOnClose: deleteOnClose ?? this.deleteOnClose,
        startTimeout: startTimeout ?? this.startTimeout,
        execTimeout: execTimeout ?? this.execTimeout,
      );
}
