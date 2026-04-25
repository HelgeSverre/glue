import 'package:glue/src/ui/components/panel.dart';

/// A feature-facing handle to the modal panel stack.
///
/// Actions build their own [AbstractPanel]s (model pickers, auth prompts,
/// session resume lists, etc.) and route them through this service so the app
/// can keep stack ownership, render scheduling, and key routing in one place.
class Panels {
  Panels({
    required List<AbstractPanel> stack,
    required void Function() render,
  })  : _stack = stack,
        _render = render;

  final List<AbstractPanel> _stack;
  final void Function() _render;

  /// Push [overlay] onto the stack and schedule a render.
  void push(AbstractPanel overlay) {
    _stack.add(overlay);
    _render();
  }

  /// Remove [overlay] from the stack and schedule a render.
  /// No-op if [overlay] is not currently on the stack.
  void remove(AbstractPanel overlay) {
    _stack.remove(overlay);
    _render();
  }
}
