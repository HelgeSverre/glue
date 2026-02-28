import 'package:test/test.dart';
import 'package:glue/src/shell/shell_config.dart';

void main() {
  group('ShellMode', () {
    test('fromString parses valid modes', () {
      expect(ShellMode.fromString('non_interactive'), ShellMode.nonInteractive);
      expect(ShellMode.fromString('interactive'), ShellMode.interactive);
      expect(ShellMode.fromString('login'), ShellMode.login);
    });

    test('fromString returns nonInteractive for unknown', () {
      expect(ShellMode.fromString('bogus'), ShellMode.nonInteractive);
    });
  });

  group('ShellConfig', () {
    test('defaults to sh and nonInteractive', () {
      const config = ShellConfig();
      expect(config.executable, 'sh');
      expect(config.mode, ShellMode.nonInteractive);
    });

    test('buildArgs for bash nonInteractive', () {
      const config = ShellConfig(executable: 'bash');
      expect(config.buildArgs('echo hi'), ['bash', '-c', 'echo hi']);
    });

    test('buildArgs for zsh interactive', () {
      const config = ShellConfig(
        executable: 'zsh',
        mode: ShellMode.interactive,
      );
      expect(config.buildArgs('echo hi'), ['zsh', '-i', '-c', 'echo hi']);
    });

    test('buildArgs for bash login', () {
      const config = ShellConfig(
        executable: 'bash',
        mode: ShellMode.login,
      );
      expect(config.buildArgs('echo hi'), ['bash', '-l', '-c', 'echo hi']);
    });

    test('buildArgs for fish interactive', () {
      const config = ShellConfig(
        executable: 'fish',
        mode: ShellMode.interactive,
      );
      expect(config.buildArgs('echo hi'), ['fish', '-i', '-c', 'echo hi']);
    });

    test('buildArgs for pwsh nonInteractive', () {
      const config = ShellConfig(executable: 'pwsh');
      expect(
        config.buildArgs('echo hi'),
        ['pwsh', '-NoProfile', '-Command', 'echo hi'],
      );
    });

    test('buildArgs for pwsh interactive', () {
      const config = ShellConfig(
        executable: 'pwsh',
        mode: ShellMode.interactive,
      );
      expect(config.buildArgs('echo hi'), ['pwsh', '-Command', 'echo hi']);
    });
  });

  group('ShellConfig.detect', () {
    test('returns executable from explicit value', () {
      final config = ShellConfig.detect(explicit: '/bin/zsh');
      expect(config.executable, '/bin/zsh');
    });

    test('falls back to sh when no SHELL env and no explicit', () {
      final config = ShellConfig.detect(shellEnv: null);
      expect(config.executable, 'sh');
    });

    test('uses SHELL env when no explicit value', () {
      final config = ShellConfig.detect(shellEnv: '/opt/homebrew/bin/zsh');
      expect(config.executable, '/opt/homebrew/bin/zsh');
    });
  });
}
