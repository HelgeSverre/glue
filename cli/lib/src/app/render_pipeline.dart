part of 'package:glue/src/app.dart';

void _renderImpl(App app) {
  final now = DateTime.now();
  if (now.difference(app._lastRender) < App._minRenderInterval) {
    if (!app._renderScheduled) {
      app._renderScheduled = true;
      Future.delayed(App._minRenderInterval, () {
        app._renderScheduled = false;
        if (DateTime.now().difference(app._lastRender) >=
            App._minRenderInterval) {
          app._doRender();
        }
      });
    }
    return;
  }
  app._doRender();
}

void _doRenderImpl(App app) {
  app._lastRender = DateTime.now();

  final panelActive = app._panelStack.isNotEmpty;
  if (app._renderedPanelLastFrame && !panelActive) {
    app.terminal.resetScrollRegion();
    app.terminal.clearScreen();
    app.layout.apply();
  }

  if (app._blocks.length > AppConstants.maxConversationBlocks) {
    app._blocks.removeRange(
        0, app._blocks.length - AppConstants.maxConversationBlocks);
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
  app._outputLineGroups.clear();
  for (final block in app._blocks) {
    final text = switch (block.kind) {
      _EntryKind.user => renderer.renderUser(block.text),
      _EntryKind.assistant => renderer.renderAssistant(block.text),
      _EntryKind.toolCall => renderer.renderToolCall(block.text, block.args),
      _EntryKind.toolCallRef =>
        renderer.renderToolCallRef(app._toolUi[block.text]?.toRenderState()),
      _EntryKind.toolResult => renderer.renderToolResult(block.text),
      _EntryKind.error => renderer.renderError(block.text),
      _EntryKind.subagent => renderer.renderSubagent(block.text),
      _EntryKind.subagentGroup => renderer.renderSubagent(block.group!.expanded
          ? '${block.group!.summary}\n${block.group!.entries.map((e) => e.render(expanded: true)).join('\n')}'
          : block.group!.summary),
      _EntryKind.system => renderer.renderSystem(block.text),
      _EntryKind.bash => renderer.renderBash(
          block.expandedText ?? 'shell',
          block.text,
          maxLines: app._config?.bashMaxLines ?? 50,
        ),
    };
    final lines = text.split('\n');
    final group = block.kind == _EntryKind.subagentGroup ? block.group : null;
    for (var j = 0; j < lines.length; j++) {
      app._outputLineGroups.add(group);
    }
    app._outputLineGroups.add(null);
    outputLines.addAll(lines);
    outputLines.add('');
  }

  // Splash screen: show animated mascot when only the initial system block.
  final isSplash = app._blocks.length == 1 &&
      app._blocks.first.kind == _EntryKind.system &&
      app._streamingText.isEmpty;
  if (isSplash && app._gooExplosion != null) {
    // Explosion takes over the entire output viewport.
    app._startSplashAnimation();
    final explosionLines = app._gooExplosion!.render();
    outputLines.clear();
    outputLines.addAll(explosionLines);
  } else if (isSplash) {
    app._startSplashAnimation();
    final mascotLines = renderMascot(app._liquidSim!);
    final viewH = app.layout.outputHeight;
    final artH = mascotLines.length;
    final padTop =
        ((viewH - outputLines.length - artH) / 2).clamp(0, viewH).toInt();
    for (var i = 0; i < padTop; i++) {
      outputLines.add('');
    }
    final padLeft = ((app.layout.outputWidth - mascotRenderWidth) / 2)
        .clamp(0, app.layout.outputWidth)
        .toInt();
    app._splashOriginCol = app.layout.outputLeft + padLeft;
    app._splashOriginRow = app.layout.outputTop + outputLines.length;
    for (final line in mascotLines) {
      outputLines.add('${' ' * padLeft}$line');
    }
  } else {
    app._stopSplashAnimation();
  }

  // If streaming, add the partial text.
  if (app._streamingText.isNotEmpty) {
    outputLines
        .addAll(renderer.renderAssistant(app._streamingText).split('\n'));
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
    app._renderedPanelLastFrame = true;
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

  app._renderedPanelLastFrame = false;

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
  app._scrollOffset = app._scrollOffset.clamp(0, maxScroll);

  final firstLine =
      (totalLines - viewportHeight - app._scrollOffset).clamp(0, totalLines);
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
    AppMode.streaming => '${App._spinnerFrames[app._spinnerFrame]} Generating',
    AppMode.toolRunning => '⚙ Tool',
    AppMode.confirming => '? Approve',
    AppMode.bashRunning => '! Running',
  };
  final shortCwd = app._shortenPath(app._cwd);
  final permLabel = '[${app._permissionMode.label}]';
  final statusLeft = ' \x1b[1m$modeIndicator\x1b[22m ';

  const sep = ' │ ';
  final scrollSeg = app._scrollOffset > 0 ? '↑${app._scrollOffset}' : null;
  final rightSegs = [
    app._modelId,
    permLabel,
    shortCwd,
    if (scrollSeg != null) scrollSeg,
    'tok ${app.agent.tokenCount}',
  ];
  final statusRight = ' ${rightSegs.join(sep)} ';
  app.layout.paintStatus(statusLeft, statusRight);

  // 6. Input area — MUST be last so cursor lands here.
  final prompt = switch ((app._mode, app._bashMode)) {
    (AppMode.idle, true) => '! ',
    (AppMode.idle, false) => '❯ ',
    _ => '  ',
  };
  final promptStyle = switch ((app._mode, app._bashMode)) {
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
