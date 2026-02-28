import 'package:glue/src/observability/debug_controller.dart';
import 'package:test/test.dart';

void main() {
  test('default state is disabled', () {
    final controller = DebugController();
    expect(controller.enabled, isFalse);
  });

  test('can be constructed with enabled=true', () {
    final controller = DebugController(enabled: true);
    expect(controller.enabled, isTrue);
  });

  test('toggle flips state from disabled to enabled', () {
    final controller = DebugController();
    controller.toggle();
    expect(controller.enabled, isTrue);
  });

  test('toggle flips state from enabled to disabled', () {
    final controller = DebugController(enabled: true);
    controller.toggle();
    expect(controller.enabled, isFalse);
  });

  test('double toggle returns to original state', () {
    final controller = DebugController();
    controller.toggle();
    controller.toggle();
    expect(controller.enabled, isFalse);
  });

  test('enable sets state to true', () {
    final controller = DebugController();
    controller.enable();
    expect(controller.enabled, isTrue);
  });

  test('disable sets state to false', () {
    final controller = DebugController(enabled: true);
    controller.disable();
    expect(controller.enabled, isFalse);
  });

  test('enable is idempotent', () {
    final controller = DebugController(enabled: true);
    controller.enable();
    expect(controller.enabled, isTrue);
  });

  test('disable is idempotent', () {
    final controller = DebugController();
    controller.disable();
    expect(controller.enabled, isFalse);
  });
}
