/// Typed wrappers around opaque identifier strings.
///
/// **Status:** proposed (PR 2 of harness-layers plan). Not yet wired to
/// consumers — see `docs/plans/2026-04-29-harness-layers.md`.
///
/// Dart 3 [extension type]s give us zero-cost wrappers that distinguish
/// IDs at the type level without runtime overhead. A function that asks
/// for a [SessionId] cannot accidentally be passed a [ProjectId].
library;

extension type const ProjectId(String value) {}

extension type const SessionId(String value) {}

extension type const TurnId(String value) {}

extension type const ToolCallId(String value) {}

extension type const SubagentId(String value) {}

extension type const SkillId(String value) {}

extension type const PermissionRequestId(String value) {}

/// e.g. `'anthropic'`, `'openai'`, `'ollama'`, `'copilot'`.
extension type const ProviderId(String value) {}

// NOTE: a structured `ModelRef` class already exists in
// `package:glue/src/catalog/model_ref.dart`. We do not duplicate it as an
// extension type here. When `glue_core` is extracted, the structured form
// will move there alongside these IDs.
