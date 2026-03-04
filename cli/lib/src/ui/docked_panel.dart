import 'package:glue/src/terminal/terminal.dart';

enum DockEdge { left, top, right, bottom }

enum DockMode { floating, pinned }

abstract class DockedPanel {
  DockEdge get edge;
  set edge(DockEdge value);

  DockMode get mode;
  set mode(DockMode value);

  /// Size along the docking axis:
  /// - columns for left/right
  /// - rows for top/bottom
  int get extent;

  bool get visible;
  bool get hasFocus;

  bool handleEvent(TerminalEvent event);

  /// Render panel content into [width] x [height].
  List<String> render(int width, int height);

  void show();
  void dismiss();
}
