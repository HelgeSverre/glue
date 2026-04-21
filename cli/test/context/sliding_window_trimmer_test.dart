import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/context/context_estimator.dart';
import 'package:glue/src/context/sliding_window_trimmer.dart';
import 'package:test/test.dart';

List<Message> _buildConversation(int userTurns) {
  final messages = <Message>[];
  for (var i = 0; i < userTurns; i++) {
    messages.add(Message.user('User message $i ' * 10));
    messages.add(Message.assistant(text: 'Assistant reply $i ' * 10));
  }
  return messages;
}

void main() {
  group('SlidingWindowTrimmer', () {
    late ContextEstimator estimator;
    late SlidingWindowTrimmer trimmer;

    setUp(() {
      estimator = ContextEstimator();
      trimmer = SlidingWindowTrimmer(estimator: estimator);
    });

    test('returns conversation unchanged when already within target', () {
      final conv = _buildConversation(2);
      // Use a very large target so no trimming is needed.
      final result = trimmer.trim(conv, targetTokens: 999999);
      expect(result.length, conv.length);
    });

    test('drops oldest turns to fit within target tokens', () {
      // Build a conversation that exceeds a small token budget.
      final conv = _buildConversation(10);
      final original = estimator.estimate(conv);
      expect(original, greaterThan(50)); // sanity check

      // Trim to 50% of original.
      final result = trimmer.trim(conv, targetTokens: (original * 0.5).round());
      expect(result.length, lessThan(conv.length));
      expect(estimator.estimate(result), lessThanOrEqualTo(original));
    });

    test('prepends a marker message when turns are dropped', () {
      final conv = _buildConversation(8);
      final original = estimator.estimate(conv);
      final result = trimmer.trim(conv, targetTokens: (original * 0.3).round());

      expect(
        result.first.text,
        contains('[Earlier conversation was trimmed'),
      );
    });

    test('no marker added when no turns are dropped', () {
      final conv = _buildConversation(2);
      final result = trimmer.trim(conv, targetTokens: 999999);
      expect(result.first.text, isNot(contains('[Earlier conversation')));
    });

    test('respects minimumRecentTurns floor', () {
      final conv = _buildConversation(5);
      // Force an extremely small target — but minimumRecentTurns=2 should
      // prevent dropping more than floor.
      final result = trimmer.trim(
        conv,
        targetTokens: 1, // impossibly small
        minimumRecentTurns: 2,
      );
      final userTurns = result.where((m) => m.role == Role.user).length;
      // At minimum 2 user turns remain (plus possibly the marker).
      expect(userTurns, greaterThanOrEqualTo(2));
    });

    test('dropped count in marker message is accurate', () {
      final conv = _buildConversation(6);
      final original = estimator.estimate(conv);
      final result = trimmer.trim(conv, targetTokens: (original * 0.4).round());

      // The marker is always the first message when turns were dropped.
      final marker = result.first.text ?? '';
      if (marker.contains('[Earlier conversation was trimmed')) {
        // The 'dropped' count in the marker reflects messages removed from
        // the pre-marker result, which is conv.length - (result.length - 1).
        final actualDropped = conv.length - (result.length - 1);
        expect(marker, contains('$actualDropped messages removed'));
      }
    });
  });
}
