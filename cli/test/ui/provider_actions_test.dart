/// Unit tests for `providerActionsFor` — the pure-function action-list
/// builder used by `_openProviderActionPanel`.
library;

import 'package:glue/src/runtime/controllers/provider_controller.dart';
import 'package:test/test.dart';

void main() {
  group('providerActionsFor', () {
    test('local provider → Test only', () {
      expect(
        providerActionsFor(connected: false, isLocal: true),
        [ProviderAction.test],
      );
      expect(
        providerActionsFor(connected: true, isLocal: true),
        [ProviderAction.test],
        reason: 'local providers have no auth; Disconnect is nonsense',
      );
    });

    test('remote + not connected → Connect, Test', () {
      expect(
        providerActionsFor(connected: false, isLocal: false),
        [ProviderAction.connect, ProviderAction.test],
      );
    });

    test('remote + connected → Disconnect, Test', () {
      expect(
        providerActionsFor(connected: true, isLocal: false),
        [ProviderAction.disconnect, ProviderAction.test],
      );
    });
  });

  group('ProviderAction labels', () {
    test('map to expected UI strings', () {
      expect(ProviderAction.connect.label, 'Connect');
      expect(ProviderAction.disconnect.label, 'Disconnect');
      expect(ProviderAction.test.label, 'Test');
    });
  });
}
