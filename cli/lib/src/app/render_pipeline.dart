part of 'package:glue/src/app.dart';

void _doRenderImpl(App app) {
  app._renderer.markRendered();

  final panelActive = app._panelStack.isNotEmpty;
  if (app._renderer.renderedPanelLastFrame && !panelActive) {
    app.terminal.resetScrollRegion();
    app.terminal.clearScreen();
    app.layout.apply();
  }

  if (app._transcript.blocks.length > AppConstants.maxConversationBlocks) {
    app._transcript.blocks.removeRange(
        0, app._transcript.blocks.length - AppConstants.maxConversationBlocks);
  }
  final dockInsets = app._dockManager.resolveInsets(
    terminalColumns: app.terminal.columns,
    terminalRows: app.terminal.rows,
  );
  app.layout.applyDockGutters(
    left: dockInsets.left,
    top: dockInsets.top,
    right: dockInsets.right,
    bottom: dockInsets.bottom,
  );

  app.terminal.hideCursor();
  final renderer = BlockRenderer(app.layout.outputWidth);

  // 1. Build all output lines from blocks.
  final outputLines = <String>[];
  app._transcript.outputLineGroups.clear();
  for (final block in app._transcript.blocks) {
    final text = switch (block.kind) {
      EntryKind.user => renderer.renderUser(block.text),
      EntryKind.assistant => renderer.renderAssistant(block.text),
      EntryKind.toolCall => renderer.renderToolCall(block.text, block.args),
      EntryKind.toolCallRef => renderer.renderToolCallRef(
          app._transcript.toolUi[block.text]?.toRenderState()),
      EntryKind.toolResult => renderer.renderToolResult(block.text),
      EntryKind.error => renderer.renderError(block.text),
      EntryKind.subagent => renderer.renderSubagent(block.text),
      EntryKind.subagentGroup => renderer.renderSubagent(block.group!.expanded
          ? '${block.group!.summary}\n${block.group!.entries.map((e) => e.render(expanded: true)).join('\n')}'
          : block.group!.summary),
      EntryKind.system => renderer.renderSystem(block.text),
      EntryKind.bash => renderer.renderBash(
          block.expandedText ?? 'shell',
          block.text,
          maxLines: app._config?.bashMaxLines ?? 50,
        ),
    };
    final lines = text.split('\n');
    final group = block.kind == EntryKind.subagentGroup ? block.group : null;
    for (var j = 0; j < lines.length; j++) {
      app._transcript.outputLineGroups.add(group);
    }
    app._transcript.outputLineGroups.add(null);
    outputLines.addAll(lines);
    outputLines.add('');
  }

  // If streaming, add the partial text.
  if (app._transcript.streamingText.isNotEmpty) {
    outputLines.addAll(
        renderer.renderAssistant(app._transcript.streamingText).split('\n'));
  }

  // Inline modal (if active) — appended to the output flow.
  if (app._activeModal != null && !app._activeModal!.isComplete) {
    outputLines.add('');
    outputLines.addAll(app._activeModal!.render(app.layout.outputWidth));
  }

  // Trailing blank line so content doesn't butt against the status bar.
  outputLines.add('');

  // Panel stack takes over the full viewport.
  if (panelActive) {
    app._renderer.renderedPanelLastFrame = true;
    var grid = outputLines;
    for (final panel in app._panelStack) {
      grid = panel.render(app.terminal.columns, app.terminal.rows, grid);
    }
    app.terminal.hideCursor();
    for (var i = 0; i < grid.length && i < app.terminal.rows; i++) {
      app.terminal.moveTo(i + 1, 1);
      app.terminal.clearLine();
      app.terminal.write(grid[i]);
    }
    return;
  }

  app._renderer.renderedPanelLastFrame = false;

  // 2. Reserve overlay space for autocomplete (before computing viewport).
  final overlayHeight = app._shellComplete.active
      ? app._shellComplete.overlayHeight
      : app._autocomplete.active
          ? app._autocomplete.overlayHeight
          : app._atHint.overlayHeight;
  app.layout.setOverlayHeight(overlayHeight);

  // 3. Compute visible window.
  final viewportHeight = app.layout.outputBottom - app.layout.outputTop + 1;
  final totalLines = outputLines.length;
  final maxScroll = (totalLines - viewportHeight).clamp(0, totalLines);
  app._transcript.scrollOffset =
      app._transcript.scrollOffset.clamp(0, maxScroll);

  final firstLine = (totalLines - viewportHeight - app._transcript.scrollOffset)
      .clamp(0, totalLines);
  final endLine = (firstLine + viewportHeight).clamp(0, totalLines);
  final visibleLines = firstLine < endLine
      ? outputLines.sublist(firstLine, endLine)
      : <String>[];

  app.layout.paintOutputViewport(visibleLines);

  // 3b. Render docked panels over output after content paint.
  final dockPlans = app._dockManager.buildRenderPlans(
    viewport: DockViewport(
      outputTop: app.layout.outputTop,
      outputBottom: app.layout.outputBottom,
      outputLeft: app.layout.outputLeft,
      outputRight: app.layout.outputRight,
      overlayTop: app.layout.overlayTop,
    ),
    terminalColumns: app.terminal.columns,
  );
  for (final plan in dockPlans) {
    app.layout.paintRect(
      row: plan.rect.row,
      col: plan.rect.col,
      width: plan.rect.width,
      height: plan.rect.height,
      lines: plan.lines,
    );
  }

  // 4. Autocomplete / @file / shell overlay.
  if (app._shellComplete.active) {
    app.layout.paintOverlay(app._shellComplete.render(app.layout.outputWidth));
  } else if (app._autocomplete.active) {
    app.layout.paintOverlay(app._autocomplete.render(app.layout.outputWidth));
  } else if (app._atHint.active) {
    app.layout.paintOverlay(app._atHint.render(app.layout.outputWidth));
  } else {
    app.layout.paintOverlay([]);
  }

  // 5. Status bar.
  final modeIndicator = switch (app._mode) {
    AppMode.idle => 'Ready',
    AppMode.streaming => '${app._renderer.spinnerFrame} Generating',
    AppMode.toolRunning => '⚙ Tool',
    AppMode.confirming => '? Approve',
    AppMode.bashRunning => '! Running',
  };
  final shortCwd = app._shortenPath(app._cwd);
  final modeLabel = '[${app._approvalMode.label}]';
  final statusLeft = ' \x1b[1m$modeIndicator\x1b[22m ';

  const sep = ' · ';
  final scrollSeg = app._transcript.scrollOffset > 0
      ? '↑${app._transcript.scrollOffset}'
      : null;
  final rightSegs = [
    _statusModelLabel(app),
    modeLabel,
    ansiTruncate(shortCwd, 30),
    if (scrollSeg != null) scrollSeg,
    '${_formatTokens(app.agent.tokenCount)} tokens',
  ];
  final statusRight = ' ${rightSegs.join(sep)} ';
  app.layout.paintStatus(statusLeft, statusRight);

  // 6. Input area — MUST be last so cursor lands here.
  final prompt = switch ((app._mode, app._bash.active)) {
    (AppMode.idle, true) => '! ',
    (AppMode.idle, false) => '❯ ',
    _ => '  ',
  };
  final promptStyle = switch ((app._mode, app._bash.active)) {
    (AppMode.idle, true) => AnsiStyle.red,
    (AppMode.idle, false) => AnsiStyle.yellow,
    _ => AnsiStyle.dim,
  };
  final showCursor =
      !(app._mode == AppMode.confirming && app._activeModal != null);
  app.layout.paintInput(
    prompt,
    app.editor.lines,
    app.editor.cursorRow,
    app.editor.cursorCol,
    showCursor: showCursor,
    promptStyle: promptStyle,
  );
}

String _formatTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${n ~/ 1000}.${(n % 1000) ~/ 100}k';
  return '${n ~/ 1000}k';
}
