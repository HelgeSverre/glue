import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/runtime` — shows the active execution runtime and the registered
/// cloud adapters available to switch to.
class RuntimeCommand extends SlashCommand {
  RuntimeCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'runtime';

  @override
  String get description => 'Show the active execution runtime';

  @override
  String execute(List<String> args) {
    final config = ctx.config;
    final buf = StringBuffer();
    if (config == null) {
      return 'No active config — runtime is not yet resolved.';
    }
    final active = config.effectiveRuntime;
    buf.writeln('Active runtime: $active');
    switch (active) {
      case 'host':
        buf.writeln('  Commands run on the host shell (no isolation).');
      case 'docker':
        buf.writeln(
          '  Docker image: ${config.dockerConfig.image} '
          '(shell: ${config.dockerConfig.shell})',
        );
        if (config.dockerConfig.mounts.isNotEmpty) {
          buf.writeln(
            '  Mounts: ${config.dockerConfig.mounts.map((m) => m.toDockerArg()).join(', ')}',
          );
        }
      case 'daytona':
        final baseUrl = (config.runtimeOptions['api_base_url'] as String?) ??
            ctx.environment.vars['DAYTONA_API_BASE_URL'] ??
            'https://app.daytona.io/api';
        final snapshot =
            (config.runtimeOptions['snapshot'] as String?) ??
                ctx.environment.vars['DAYTONA_SNAPSHOT'];
        buf.writeln('  Daytona base URL: $baseUrl');
        buf.writeln(
          snapshot == null
              ? '  Daytona shape: default (2 vCPU / 4 GiB / 8 GiB disk)'
              : '  Daytona snapshot: $snapshot',
        );
      case 'modal':
        final appName = (config.runtimeOptions['app_name'] as String?) ??
            ctx.environment.vars['MODAL_APP'] ??
            'glue';
        final image = (config.runtimeOptions['image'] as String?) ??
            ctx.environment.vars['MODAL_IMAGE'];
        buf.writeln('  Modal app: $appName');
        buf.writeln(image == null
            ? '  Image: modal default Debian'
            : '  Image: $image');
      case 'sprites':
        final cliPath = (config.runtimeOptions['sprite_cli'] as String?) ??
            ctx.environment.vars['SPRITES_CLI'] ??
            'sprite';
        final name = (config.runtimeOptions['sprite_name'] as String?) ??
            ctx.environment.vars['SPRITES_NAME'];
        buf.writeln('  Sprites CLI: $cliPath');
        buf.writeln(
          name == null
              ? '  Sprite name: auto (a fresh sprite per session)'
              : '  Sprite name: $name (resumes on each session)',
        );
      default:
        buf.writeln('  (no extra details for adapter "$active")');
    }
    final registered = RuntimeFactory.registeredAdapters().toList();
    if (registered.isNotEmpty) {
      buf.writeln(
        'Registered cloud adapters: ${registered.join(', ')}',
      );
    }
    buf.writeln(
      'Override with the GLUE_RUNTIME env var or the `runtime:` config key.',
    );
    return buf.toString().trimRight();
  }
}
