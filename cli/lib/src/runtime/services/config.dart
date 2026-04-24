import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/storage/config_store.dart';

/// Feature-facing handle to the active [GlueConfig] plus cross-turn trust
/// preferences.
///
/// Controllers used to take `GlueConfig? Function() getConfig` and
/// `void Function(GlueConfig) setConfig` as separate closures — this
/// service bundles both behind a single injectable dependency, and also
/// owns the trusted-tool allow-list (previously a mutable `Set<String>`
/// field on `App`).
///
/// Concrete, not an interface: tests construct one directly with their own
/// read/write functions.
class Config {
  Config({
    required GlueConfig? Function() read,
    required void Function(GlueConfig next) write,
    required Environment environment,
    Iterable<String> initialTrustedTools = const [],
  })  : _read = read,
        _write = write,
        _environment = environment,
        _trustedTools = Set.of(initialTrustedTools);

  final GlueConfig? Function() _read;
  final void Function(GlueConfig next) _write;
  final Environment _environment;
  final Set<String> _trustedTools;

  /// The active config, or null if not yet loaded.
  GlueConfig? get current => _read();

  /// Replace the active config.
  void update(GlueConfig next) => _write(next);

  /// The set of tool names that auto-approve in confirm mode.
  ///
  /// Exposed as the underlying set so callers like [PermissionGate] see
  /// mutations (via [trustTool]) immediately without reconstruction.
  Set<String> get trustedTools => _trustedTools;

  /// Mark [name] as trusted for the rest of this session and persist the
  /// choice to `~/.glue/config.yaml` so it survives restarts.
  ///
  /// Safe to call multiple times; a no-op when [name] is already trusted.
  /// Persistence failures are swallowed so tool flows can't be blocked by
  /// disk issues — matches the behaviour of the App-side path this
  /// replaces.
  void trustTool(String name) {
    if (!_trustedTools.add(name)) return;
    try {
      final store = ConfigStore(_environment.configPath);
      store.update((c) {
        final tools = (c['trusted_tools'] as List?)?.cast<String>() ?? [];
        if (!tools.contains(name)) {
          tools.add(name);
          c['trusted_tools'] = tools;
        }
      });
    } catch (_) {}
  }
}
