/// Proposed core data model for the harness-layers refactor.
///
/// **Status:** proposed (PR 2 of harness-layers plan). Not yet wired to
/// consumers — see `docs/plans/2026-04-29-harness-layers.md`.
///
/// This barrel re-exports the types that will eventually move to a
/// dedicated `glue_core` package:
///
/// - Identity types ([SessionId], [ProjectId], …)
/// - Sealed event hierarchy ([SessionEvent] and variants)
/// - Sealed command hierarchy ([SessionCommand] and variants)
///
/// Importing this barrel signals "I'm consuming the proposed contract"
/// and makes future renames cheap.
library;

export 'package:glue/src/_proposed_core/ids.dart';
export 'package:glue/src/_proposed_core/session_command.dart';
export 'package:glue/src/_proposed_core/session_event.dart';
// Re-exported so consumers of the proposed core get the canonical model
// reference type in the same import.
export 'package:glue/src/catalog/model_ref.dart' show ModelRef;
