import 'dart:async';
import 'dart:io';

import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/llm/model_discovery.dart';
import 'package:glue/src/skills/skill_parser.dart';
import 'package:glue/src/skills/skill_registry.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/model_panel_formatter.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/split_panel_modal.dart';

class HistoryPanelEntry {
  final int userMessageIndex;
  final String text;

  const HistoryPanelEntry({
    required this.userMessageIndex,
    required this.text,
  });
}

/// Handles panel modal flows for help, resume, and history.
class PanelController {
  final List<PanelOverlay> _panelStack;
  final void Function() _render;

  PanelController({
    required List<PanelOverlay> panelStack,
    required void Function() render,
  })  : _panelStack = panelStack,
        _render = render;

  void openHelp({
    required List<SlashCommand> commands,
  }) {
    final lines = <String>[];

    lines.add('${'■ COMMANDS'.styled.yellow}');
    lines.add('');
    for (final cmd in commands) {
      final aliases = cmd.aliases.isNotEmpty
          ? ' ${'(${cmd.aliases.map((a) => '/$a').join(', ')})'.styled.gray}'
          : '';
      final name = '/${cmd.name}'.padRight(16);
      lines.add('  ${name.styled.yellow}${cmd.description}$aliases');
    }

    lines.add('');
    lines.add('${'■ KEYBINDINGS'.styled.yellow}');
    lines.add('');
    lines.add('  ${'Ctrl+C'.padRight(16)}Cancel / Exit');
    lines.add('  ${'Escape'.padRight(16)}Cancel generation');
    lines.add('  ${'Up / Down'.padRight(16)}History navigation');
    lines.add('  ${'Ctrl+U'.padRight(16)}Clear line');
    lines.add('  ${'Ctrl+W'.padRight(16)}Delete word');
    lines.add('  ${'Ctrl+A / E'.padRight(16)}Start / End of line');
    lines.add('  ${'PageUp / Dn'.padRight(16)}Scroll output');
    lines.add('  ${'Tab'.padRight(16)}Accept completion');

    lines.add('');
    lines.add('${'■ PERMISSIONS'.styled.yellow}');
    lines.add('');
    lines.add('  ${'Shift+Tab'.padRight(16)}Cycle tool approval mode');
    lines.add('  ${'/info'.padRight(16)}View current mode');

    lines.add('');
    lines.add('${'■ FILE REFERENCES'.styled.yellow}');
    lines.add('');
    lines.add('  ${'@path/to/file'.padRight(16)}Attach file to message');
    lines.add('  ${'@dir/'.padRight(16)}Browse directory');

    final panel = PanelModal(
      title: 'HELP',
      lines: lines,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
    );
    _panelStack.add(panel);
    _render();

    panel.result.then((_) {
      _panelStack.remove(panel);
      _render();
    });
  }

  void openResume({
    required List<SessionMeta> sessions,
    required String Function(DateTime) timeAgo,
    required String Function(String path) shortenPath,
    required String Function(SessionMeta session) onResume,
    required void Function(String message) addSystemMessage,
  }) {
    if (sessions.isEmpty) {
      addSystemMessage('No saved sessions found.');
      _render();
      return;
    }

    const dim = '\x1b[90m';
    const yellow = '\x1b[33m';
    const rst = '\x1b[0m';
    const idW = 12;
    const modelW = 20;
    const pathW = 30;
    const ageW = 10;
    const gap = '  ';

    final displayLines = <String>[];

    displayLines.add(
      '$dim${'ID'.padRight(idW)}$gap'
      '${'MODEL'.padRight(modelW)}$gap'
      '${'DIRECTORY'.padRight(pathW)}$gap'
      '${'AGE'.padRight(ageW)}$rst',
    );
    displayLines.add(
      '$dim${'─' * (idW + 2 + modelW + 2 + pathW + 2 + ageW)}$rst',
    );

    for (final s in sessions) {
      final ago = timeAgo(s.startTime);
      final shortCwd = shortenPath(s.cwd);
      final displayId = s.title ??
          (s.id.length > idW
              ? '${s.id.substring(0, idW - 1)}…'
              : s.id.padRight(idW));
      final model = s.model.length > modelW
          ? '${s.model.substring(0, modelW - 1)}…'
          : s.model;
      final forkBadge =
          s.forkedFrom != null ? '${'[F]'.styled.fg256(208)} ' : '';

      displayLines.add(
        '$forkBadge$yellow${displayId.padRight(idW)}$rst$gap'
        '${model.padRight(modelW)}$gap'
        '$dim${shortCwd.padRight(pathW)}$rst$gap'
        '$dim${ago.padRight(ageW)}$rst',
      );
    }

    final panel = PanelModal(
      title: 'Resume Session',
      lines: displayLines,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
      selectable: true,
      initialIndex: 2,
    );
    _panelStack.add(panel);
    _render();

    panel.selection.then((idx) {
      _panelStack.remove(panel);
      if (idx == null || idx < 2) {
        _render();
        return;
      }
      final result = onResume(sessions[idx - 2]);
      if (result.isNotEmpty) {
        addSystemMessage(result);
      }
      _render();
    });
  }

  void openHistory({
    required List<HistoryPanelEntry> entries,
    required void Function(int userMessageIndex, String messageText) onFork,
    required void Function(String message) addSystemMessage,
  }) {
    if (entries.isEmpty) {
      addSystemMessage('No conversation history.');
      _render();
      return;
    }

    final displayLines = <String>[];
    for (var i = 0; i < entries.length; i++) {
      final text = entries[i].text.replaceAll('\n', ' ');
      displayLines.add('${(i + 1).toString().padLeft(3)}. $text');
    }

    final panel = PanelModal(
      title: 'History',
      lines: displayLines,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
      selectable: true,
    );
    _panelStack.add(panel);
    _render();

    panel.selection.then((idx) {
      if (idx == null) {
        _panelStack.remove(panel);
        _render();
        return;
      }

      _openHistoryActionPanel(
        entry: entries[idx],
        onFork: onFork,
        addSystemMessage: addSystemMessage,
      );
    });
  }

  Future<void> openModel({
    required GlueConfig config,
    required String cacheDir,
    required String currentModelId,
    required String Function(ModelEntry entry) onModelSelected,
    required void Function(String message) addSystemMessage,
    required bool Function() isSelectionEnabled,
  }) async {
    final discovery = ModelDiscovery(cacheDir: cacheDir);
    final entries = await discovery.discoverAll(config);

    if (entries.isEmpty) {
      addSystemMessage('No models available (no API keys configured).');
      _render();
      return;
    }

    final formatted =
        formatModelPanelLines(entries, currentModelId: currentModelId);
    final panel = PanelModal(
      title: 'Switch Model',
      lines: formatted.lines,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 8),
      selectable: true,
    );
    for (var i = 0; i < formatted.initialIndex; i++) {
      panel.handleEvent(KeyEvent(Key.down));
    }
    _panelStack.add(panel);
    _render();

    unawaited(panel.selection.then((idx) {
      _panelStack.remove(panel);
      if (idx == null) {
        _render();
        return;
      }
      if (!isSelectionEnabled()) {
        _render();
        return;
      }
      final entry = formatted.entries[idx];
      final result = onModelSelected(entry);
      addSystemMessage(result);
      _render();
    }));
  }

  void openSkills({
    required SkillRegistry registry,
    required String Function(String path) shortenPath,
    required List<String> Function(String text, int width) wrapText,
    required Future<void> Function(String name) onSkillSelected,
    required void Function(String message) addSystemMessage,
  }) {
    if (registry.isEmpty) {
      addSystemMessage('No skills found.\n\n'
          'To add skills, create directories with SKILL.md files in:\n'
          '  ~/.glue/skills/<skill-name>/SKILL.md (global)\n'
          '  .glue/skills/<skill-name>/SKILL.md (project-local)');
      _render();
      return;
    }

    final skills = registry.list();

    const cyan = '\x1b[36m';
    const green = '\x1b[32m';
    const rst = '\x1b[0m';

    final maxNameLen =
        skills.fold<int>(0, (m, s) => s.name.length > m ? s.name.length : m);
    final leftItems = skills.map((s) {
      final tag = switch (s.source) {
        SkillSource.project => '${green}project$rst',
        SkillSource.global => '${cyan}global$rst',
        SkillSource.custom => '${cyan}custom$rst',
      };
      return '${s.name.padRight(maxNameLen)}  $tag';
    }).toList();

    List<String> buildDetail(int idx, int width) {
      if (idx < 0 || idx >= skills.length) return [];
      final s = skills[idx];
      final lines = <String>[];

      const bold = '\x1b[1m';
      const dim = '\x1b[2m';
      const lbl = '\x1b[32m';

      lines.add('$bold${s.name}$rst');
      lines.add('');

      final wrapped = wrapText(s.description, width);
      lines.addAll(wrapped);
      lines.add('');

      final shortDir = shortenPath(s.skillDir);
      lines.add('${lbl}Source$rst      $dim$shortDir$rst');
      if (s.license != null) {
        lines.add('${lbl}License$rst    $dim${s.license}$rst');
      }
      if (s.compatibility != null) {
        lines.add('${lbl}Requires$rst   $dim${s.compatibility}$rst');
      }
      for (final entry in s.metadata.entries) {
        final key = entry.key[0].toUpperCase() + entry.key.substring(1);
        final pad = ' ' * (11 - key.length);
        lines.add('$lbl$key$rst$pad$dim${entry.value}$rst');
      }

      return lines;
    }

    final panel = SplitPanelModal(
      title: 'SKILLS',
      leftItems: leftItems,
      buildRightLines: buildDetail,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.6, 12),
    );
    _panelStack.add(panel);
    _render();

    unawaited(panel.selection.then((idx) async {
      _panelStack.remove(panel);
      if (idx == null) {
        _render();
        return;
      }
      final skill = skills[idx];
      await onSkillSelected(skill.name);
      _render();
    }));
  }

  void _openHistoryActionPanel({
    required HistoryPanelEntry entry,
    required void Function(int userMessageIndex, String messageText) onFork,
    required void Function(String message) addSystemMessage,
  }) {
    final panel = PanelModal(
      title: 'Action',
      lines: ['Fork conversation', 'Copy to clipboard'],
      barrier: BarrierStyle.dim,
      height: PanelFixed(4),
      width: PanelFixed(30),
      selectable: true,
    );
    _panelStack.add(panel);
    _render();

    panel.selection.then((idx) {
      _panelStack.clear();
      if (idx == null) {
        _render();
        return;
      }
      switch (idx) {
        case 0:
          onFork(entry.userMessageIndex, entry.text);
        case 1:
          unawaited(() async {
            final copied = await _copyToClipboard(entry.text);
            addSystemMessage(
              copied
                  ? 'Copied to clipboard.'
                  : 'Clipboard copy failed on this platform.',
            );
            _render();
          }());
      }
    });
  }

  Future<bool> _copyToClipboard(String text) async {
    final commands = _clipboardCommands();
    for (final command in commands) {
      try {
        final process = await Process.start(command.$1, command.$2);
        process.stdin.write(text);
        await process.stdin.close();
        final exitCode = await process.exitCode;
        if (exitCode == 0) return true;
      } catch (_) {
        // Try next clipboard command fallback.
      }
    }
    return false;
  }

  List<(String, List<String>)> _clipboardCommands() {
    if (Platform.isMacOS) {
      return [('pbcopy', const [])];
    }
    if (Platform.isWindows) {
      return [('clip', const [])];
    }
    if (Platform.isLinux) {
      return [
        ('wl-copy', const []),
        ('xclip', const ['-selection', 'clipboard']),
        ('xsel', const ['--clipboard', '--input']),
      ];
    }
    return const [];
  }
}
