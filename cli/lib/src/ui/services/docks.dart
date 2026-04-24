import 'package:glue/src/ui/components/dock.dart';

/// A feature-facing handle to the docked-panel host.
///
/// Features (skills browser, etc.) register their [DockedPanel]s through this
/// service; the app's [DockManager] stays as the underlying layout engine.
class Docks {
  Docks(this._manager);

  final DockManager _manager;

  /// Register [panel] with the dock host.
  void add(DockedPanel panel) => _manager.add(panel);

  /// Unregister [panel] from the dock host.
  void remove(DockedPanel panel) => _manager.remove(panel);

  /// All currently registered panels, in registration order.
  Iterable<DockedPanel> get panels => _manager.panels;
}
