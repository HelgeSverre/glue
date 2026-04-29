/// Backwards-compatibility re-export for [AppConstants].
///
/// [AppConstants] (including the version constant) moved to
/// `package:glue/src/_proposed_core/app_constants.dart` so strategies
/// can depend on it without crossing the harness boundary. The
/// generated `version_generated.dart` moved alongside it.
///
/// New code should import the proposed-core path directly.
library;

export 'package:glue/src/_proposed_core/app_constants.dart';
