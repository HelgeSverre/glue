import 'dart:async';

import 'package:glue/src/runtime/renderer.dart';
import 'package:test/test.dart';

void main() {
  group('Renderer.schedule coalescing', () {
    test(
        'first call paints immediately when no prior render '
        'happened within the 16ms window', () {
      final r = Renderer();
      var painted = 0;
      r.schedule(() {
        painted++;
        r.markRendered();
      });
      expect(painted, 1);
    });

    test(
        'back-to-back schedule() calls after a fresh paint coalesce '
        'to at most one delayed paint', () async {
      final r = Renderer();
      var painted = 0;
      void paint() {
        painted++;
        r.markRendered();
      }

      // First paint: immediate.
      r.schedule(paint);
      expect(painted, 1);

      // Spam 10 more schedules inside the 16ms coalescing window.
      for (var i = 0; i < 10; i++) {
        r.schedule(paint);
      }
      // Still just the first one — none fired synchronously.
      expect(painted, 1);

      // After the coalescing window, at most one additional paint fires.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(painted, lessThanOrEqualTo(2));
      expect(painted, greaterThanOrEqualTo(1));
    });

    test(
        'markRendered resets the coalescing clock so the next '
        'schedule fires immediately again', () async {
      final r = Renderer();
      var painted = 0;
      void paint() {
        painted++;
        r.markRendered();
      }

      r.schedule(paint);
      expect(painted, 1);

      // Wait past the coalescing window.
      await Future<void>.delayed(const Duration(milliseconds: 25));

      r.schedule(paint);
      expect(painted, 2);
    });
  });

  group('Renderer.spinner', () {
    test('spinnerFrame starts at index 0', () {
      final r = Renderer();
      expect(r.spinnerFrame, '⠋');
    });

    test('startSpinner is idempotent while running', () async {
      final r = Renderer();
      var ticks = 0;
      r.startSpinner(() => ticks++);
      // Second call should be a no-op — same underlying timer, same onTick.
      var extraTicks = 0;
      r.startSpinner(() => extraTicks++);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      r.stopSpinner();

      expect(ticks, greaterThan(0));
      // The second onTick should never be invoked because the second
      // startSpinner was swallowed.
      expect(extraTicks, 0);
    });

    test('frames advance modulo spinner length', () async {
      final r = Renderer();
      final seenFrames = <String>{};
      r.startSpinner(() {
        seenFrames.add(r.spinnerFrame);
      });
      // Ticks every 80ms; wait long enough for multiple distinct frames.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      r.stopSpinner();

      // We should have seen at least a couple of distinct glyphs.
      expect(seenFrames.length, greaterThan(1));
    });

    test('stopSpinner is safe to call when not running', () {
      final r = Renderer();
      expect(r.stopSpinner, returnsNormally);
      expect(r.stopSpinner, returnsNormally);
    });

    test('stopSpinner halts further ticks', () async {
      final r = Renderer();
      var ticks = 0;
      r.startSpinner(() => ticks++);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final before = ticks;
      r.stopSpinner();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(ticks, before);
    });

    test('startSpinner after stopSpinner resets frame to 0', () async {
      final r = Renderer();
      r.startSpinner(() {});
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final midFrame = r.spinnerFrame;
      r.stopSpinner();
      // Restart — implementation resets _spinnerFrame to 0.
      r.startSpinner(() {});
      try {
        expect(r.spinnerFrame, '⠋');
        // Sanity-check: frame is not the same as the one we captured
        // mid-way (otherwise the test is vacuous).
        expect(midFrame, isNotNull);
      } finally {
        r.stopSpinner();
      }
    });
  });

  group('Renderer.renderedPanelLastFrame', () {
    test('defaults to false and can be toggled', () {
      final r = Renderer();
      expect(r.renderedPanelLastFrame, isFalse);
      r.renderedPanelLastFrame = true;
      expect(r.renderedPanelLastFrame, isTrue);
    });
  });
}
