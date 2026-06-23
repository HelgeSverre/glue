/// Surface-agnostic runtime readiness diagnostics.
///
/// `glue doctor` (and any other surface) asks the active runtime
/// adapter "are you ready to run a session?" without hardcoding
/// per-cloud probing logic. Each adapter owns its own readiness
/// checks (binary-on-PATH, auth, version probes, resolved config) and
/// returns plain [RuntimeDiagnostic] values the surface renders.
///
/// This contract lives in `glue_strategies` (the package that owns
/// [RuntimeFactory]) and deliberately depends on nothing from
/// `glue_harness` — no `GlueConfig`, no `Environment`. Surfaces pass
/// the two things a probe actually needs through
/// [RuntimeDiagnosticContext]: the runtime's already-resolved options
/// map and an environment-variable accessor.
library;

/// Severity of a single [RuntimeDiagnostic]. Surfaces map these onto
/// their own finding/severity types (e.g. `glue doctor`'s
/// `DoctorSeverity`). [info] is for non-actionable, hide-able
/// observations (resolved names, sandbox shapes); [ok] is a passing
/// readiness check worth surfacing.
enum RuntimeDiagnosticLevel { ok, info, warn, error }

/// One readiness observation about a runtime — e.g. "DAYTONA_API_KEY
/// present", "modal not authenticated — run `modal token set`", or an
/// informational "Sprite name: auto".
///
/// Informational, non-actionable observations use
/// [RuntimeDiagnosticLevel.ok] so surfaces that hide info-level noise
/// can still treat them as benign.
class RuntimeDiagnostic {
  final RuntimeDiagnosticLevel level;
  final String message;

  const RuntimeDiagnostic({required this.level, required this.message});

  const RuntimeDiagnostic.ok(this.message) : level = RuntimeDiagnosticLevel.ok;

  const RuntimeDiagnostic.info(this.message)
    : level = RuntimeDiagnosticLevel.info;

  const RuntimeDiagnostic.warn(this.message)
    : level = RuntimeDiagnosticLevel.warn;

  const RuntimeDiagnostic.error(this.message)
    : level = RuntimeDiagnosticLevel.error;
}

/// The minimal context a runtime probe reads. Carries the runtime's
/// resolved options (the YAML section for the selected runtime, the
/// same map [RuntimeFactory.create] receives) and an environment
/// accessor so probes can resolve keys/paths/names exactly as the
/// adapter's own config builder does — without depending on
/// `Environment`/`GlueConfig`.
class RuntimeDiagnosticContext {
  final Map<String, Object?> options;
  final String? Function(String) env;

  const RuntimeDiagnosticContext({required this.options, required this.env});

  /// Convenience accessor mirroring how adapters read a config knob:
  /// the typed option (`options[key] as String?`) first, then the env
  /// var. A present-but-empty option string is honoured as-is, matching
  /// the adapters' own `(options[k] as String?) ?? env[...]` resolution.
  String? optionOrEnv(String optionKey, String envKey) {
    final fromOption = options[optionKey];
    if (fromOption is String) return fromOption;
    return env(envKey);
  }
}

/// Signature an adapter registers to answer runtime readiness probes.
typedef RuntimeDiagnoser =
    Iterable<RuntimeDiagnostic> Function(RuntimeDiagnosticContext ctx);
