/// Backwards-compatibility re-export. ModelRef moved to
/// `package:glue/src/_proposed_core/model_ref.dart` so any subsystem can
/// depend on it without crossing the harness layer boundary.
///
/// New code should import from the proposed-core path directly.
library;

export 'package:glue/src/_proposed_core/model_ref.dart';
