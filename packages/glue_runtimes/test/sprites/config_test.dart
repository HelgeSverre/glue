import 'package:glue_runtimes/sprites.dart';
import 'package:test/test.dart';

void main() {
  group('SpritesConfig', () {
    test('defaults to "sprite" on PATH, ephemeral, no fixed name', () {
      const c = SpritesConfig();
      expect(c.spriteCliPath, 'sprite');
      expect(c.spriteName, isNull);
      expect(c.deleteOnClose, isTrue);
    });

    test('copyWith overrides selectively', () {
      const original = SpritesConfig();
      final next = original.copyWith(spriteName: 'mine', deleteOnClose: false);
      expect(next.spriteCliPath, original.spriteCliPath);
      expect(next.spriteName, 'mine');
      expect(next.deleteOnClose, isFalse);
    });
  });

  group('spritesConfigFromOptions', () {
    test('prefers explicit options over env', () {
      final c = spritesConfigFromOptions(
        {'sprite_name': 'opt-sprite', 'sprite_cli': '/opt/bin/sprite'},
        env: {'SPRITES_NAME': 'env-sprite', 'SPRITES_CLI': '/env/sprite'},
      );
      expect(c.spriteName, 'opt-sprite');
      expect(c.spriteCliPath, '/opt/bin/sprite');
    });

    test('falls back to env when options omit a field', () {
      final c = spritesConfigFromOptions(
        const {},
        env: const {'SPRITES_NAME': 'env-sprite'},
      );
      expect(c.spriteName, 'env-sprite');
      expect(c.spriteCliPath, 'sprite');
    });

    test('honours delete_on_close env var', () {
      final c = spritesConfigFromOptions(
        const {},
        env: const {'SPRITES_DELETE_ON_CLOSE': 'false'},
      );
      expect(c.deleteOnClose, isFalse);
    });

    test('options bool wins over env', () {
      final c = spritesConfigFromOptions(
        const {'delete_on_close': false},
        env: const {'SPRITES_DELETE_ON_CLOSE': 'true'},
      );
      expect(c.deleteOnClose, isFalse);
    });
  });
}
