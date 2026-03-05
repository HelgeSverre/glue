part of 'package:glue/src/app.dart';

void _openPlansPanelImpl(App app) {
  final plans = app._planStore.listPlans();
  app._panels.openPlans(
    plans: plans,
    shortenPath: app._shortenPath,
    timeAgo: _timeAgoImpl,
    onOpenPlan: app._openPlanViewer,
    addSystemMessage: app._addSystemMessage,
  );
}

void _openPlanViewerImpl(App app, PlanDocument plan) {
  final markdown = _safeReadPlan(app, plan.path);
  final panelWidth = _resolvePanelWidth(app.terminal.columns);
  final contentWidth = (panelWidth - 4).clamp(20, panelWidth);
  final renderer = MarkdownRenderer(contentWidth);
  final rendered = renderer.render(markdown).split('\n');

  final lines = <String>[
    'Path: ${app._shortenPath(plan.path)}',
    'Updated: ${plan.modifiedAt.toLocal().toIso8601String().substring(0, 19)}',
    'Size: ${plan.sizeBytes} bytes  Source: ${plan.source}',
    'Keys: ↑/↓/PgUp/PgDn scroll  Esc close  e or Ctrl+E open in \$EDITOR',
    '',
    ...rendered,
  ];

  final panel = PanelModal(
    title: 'PLAN • ${_trimTitle(plan.title)}',
    lines: lines,
    barrier: BarrierStyle.dim,
    width: PanelFluid(0.86, 56),
    height: PanelFluid(0.82, 16),
    onOpenInEditor: () => app._openPlanInEditor(plan.path),
  );
  app._panelStack.add(panel);
  app._render();

  panel.result.then((_) {
    app._panelStack.remove(panel);
    app._render();
  });
}

Future<void> _openPlanInEditorImpl(App app, String path) async {
  final command = _resolveEditorCommand(app._environment.vars);
  if (command == null) {
    app._addSystemMessage(
      'No editor configured. Set \$EDITOR or \$VISUAL to enable plan editing.',
    );
    app._render();
    return;
  }

  final executable = command.$1;
  final args = [...command.$2, path];

  app.terminal.disableMouse();
  app.terminal.write('\x1b[0m');
  app.terminal.showCursor();
  app.terminal.resetScrollRegion();
  app.terminal.disableAltScreen();
  app.terminal.disableRawMode();

  int? exitCode;
  String? error;
  try {
    final proc = await Process.start(
      executable,
      args,
      workingDirectory: app._cwd,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await proc.exitCode;
  } catch (e) {
    error = e.toString();
  } finally {
    app.terminal.enableRawMode();
    app.terminal.enableAltScreen();
    app.terminal.enableMouse();
    app.terminal.clearScreen();
    app.layout.apply();
    app._render();
  }

  if (error != null) {
    app._addSystemMessage('Failed to launch editor "$executable": $error');
    app._render();
    return;
  }

  if (exitCode != 0) {
    app._addSystemMessage('Editor exited with status $exitCode.');
    app._render();
  }
}

String _safeReadPlan(App app, String path) {
  try {
    return app._planStore.readPlan(path);
  } catch (e) {
    return '# Failed to read plan\n\n`$path`\n\n$e';
  }
}

String _trimTitle(String title) {
  final cleaned = title.trim();
  if (cleaned.length <= 54) return cleaned;
  return '${cleaned.substring(0, 54)}…';
}

int _resolvePanelWidth(int terminalColumns) {
  final width = (terminalColumns * 0.86).floor();
  return width.clamp(56, terminalColumns);
}

(String, List<String>)? _resolveEditorCommand(Map<String, String> env) {
  final raw = (env['GLUE_EDITOR'] ?? env['VISUAL'] ?? env['EDITOR'])?.trim();
  if (raw == null || raw.isEmpty) return null;

  final parts = _shellLikeSplit(raw);
  if (parts.isEmpty) return null;
  return (parts.first, parts.sublist(1));
}

List<String> _shellLikeSplit(String input) {
  final out = <String>[];
  final current = StringBuffer();
  var quote = '';
  var escaped = false;

  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    if (escaped) {
      current.write(ch);
      escaped = false;
      continue;
    }
    if (ch == '\\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (ch == quote) {
        quote = '';
      } else {
        current.write(ch);
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      continue;
    }
    if (RegExp(r'\s').hasMatch(ch)) {
      if (current.isNotEmpty) {
        out.add(current.toString());
        current.clear();
      }
      continue;
    }
    current.write(ch);
  }

  if (current.isNotEmpty) {
    out.add(current.toString());
  }
  return out;
}
