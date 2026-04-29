/// Backwards-compatibility re-export. The pure data types moved to
/// `package:glue_core/src/model_catalog.dart` so strategies
/// and credentials can depend on them without crossing the harness layer.
///
/// New code should import from the proposed-core path directly.
library;

export 'package:glue_core/src/model_catalog.dart';
