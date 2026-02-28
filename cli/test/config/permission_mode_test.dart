import 'package:test/test.dart';
import 'package:glue/src/config/permission_mode.dart';

void main() {
  group('PermissionMode', () {
    test('label returns expected strings', () {
      expect(PermissionMode.confirm.label, 'confirm');
      expect(PermissionMode.acceptEdits.label, 'accept-edits');
      expect(PermissionMode.ignorePermissions.label, 'YOLO');
      expect(PermissionMode.readOnly.label, 'read-only');
    });

    test('next cycles through all modes', () {
      expect(PermissionMode.confirm.next, PermissionMode.acceptEdits);
      expect(PermissionMode.acceptEdits.next, PermissionMode.ignorePermissions);
      expect(PermissionMode.ignorePermissions.next, PermissionMode.readOnly);
      expect(PermissionMode.readOnly.next, PermissionMode.confirm);
    });

    test('full cycle returns to start', () {
      var mode = PermissionMode.confirm;
      for (var i = 0; i < 4; i++) {
        mode = mode.next;
      }
      expect(mode, PermissionMode.confirm);
    });
  });
}
