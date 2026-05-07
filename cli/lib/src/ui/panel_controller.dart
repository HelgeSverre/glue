import 'package:glue/src/ui/panel_modal.dart';

/// Thin host for the modal/panel stack. Commands push and dismiss panels
/// directly; domain-specific picker/action assembly lives in the command
/// classes themselves.
class PanelController {
  PanelController({
    required List<PanelOverlay> panelStack,
    required void Function() render,
  })  : _panelStack = panelStack,
        _render = render;

  final List<PanelOverlay> _panelStack;
  final void Function() _render;

  /// Push a panel onto the modal stack and re-render.
  void push(PanelOverlay panel) {
    _panelStack.add(panel);
    _render();
  }

  /// Remove a panel from the modal stack and re-render.
  void dismiss(PanelOverlay panel) {
    _panelStack.remove(panel);
    _render();
  }
}
