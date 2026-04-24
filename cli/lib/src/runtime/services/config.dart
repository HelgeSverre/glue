import 'package:glue/src/config/glue_config.dart';

/// Feature-facing handle to the active [GlueConfig].
///
/// Controllers used to take `GlueConfig? Function() getConfig` and
/// `void Function(GlueConfig) setConfig` as separate closures — this service
/// bundles both behind a single injectable dependency.
///
/// Concrete, not an interface: tests construct one directly with their own
/// read/write functions.
class Config {
  Config({
    required GlueConfig? Function() read,
    required void Function(GlueConfig next) write,
  })  : _read = read,
        _write = write;

  final GlueConfig? Function() _read;
  final void Function(GlueConfig next) _write;

  /// The active config, or null if not yet loaded.
  GlueConfig? get current => _read();

  /// Replace the active config.
  void update(GlueConfig next) => _write(next);
}
