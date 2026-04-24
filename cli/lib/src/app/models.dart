part of 'package:glue/src/app.dart';

/// Target model + prompt for background title generation. Private to the
/// app — the session title flow (Group C) will absorb this.
class _TitleTarget {
  final ModelRef ref;

  const _TitleTarget({required this.ref});
}
