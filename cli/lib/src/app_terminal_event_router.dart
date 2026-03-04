part of 'app.dart';

void _handleTerminalEventImpl(App app, TerminalEvent event) {
  switch (event) {
    case CharEvent() || KeyEvent():
      // Panel modal gets first crack at input.
      if (app._panelStack.isNotEmpty && !app._panelStack.last.isComplete) {
        if (app._panelStack.last.handleEvent(event)) {
          app._doRender();
          return;
        }
      }

      // Confirm modal gets next crack at input.
      if (app._activeModal != null && !app._activeModal!.isComplete) {
        if (app._activeModal!.handleEvent(event)) {
          app._render();
          return;
        }
      }

      // Focused docked panel handles input before editor/autocomplete.
      if (app._dockManager.handleEvent(event)) {
        app._render();
        return;
      }

      // Permission mode cycling — works in all modes.
      if (event case KeyEvent(key: Key.shiftTab)) {
        app._permissionMode = app._permissionMode.next;
        app._syncToolFilter();
        app._render();
        return;
      }

      // Scroll handling — works in all modes.
      if (event case KeyEvent(key: Key.pageUp)) {
        final viewportHeight =
            app.layout.outputBottom - app.layout.outputTop + 1;
        app._events.add(UserScroll(viewportHeight ~/ 2));
        return;
      }
      if (event case KeyEvent(key: Key.pageDown)) {
        final viewportHeight =
            app.layout.outputBottom - app.layout.outputTop + 1;
        app._events.add(UserScroll(-(viewportHeight ~/ 2)));
        return;
      }

      // Bash mode switching — before passing to editor.
      if (app._mode == AppMode.idle) {
        if (!app._bashMode &&
            event is CharEvent &&
            event.char == '!' &&
            app.editor.cursor == 0) {
          app._bashMode = true;
          app._render();
          return;
        }
        if (app._bashMode &&
            event is KeyEvent &&
            event.key == Key.backspace &&
            app.editor.cursor == 0) {
          app._bashMode = false;
          app._shellComplete.dismiss();
          app._render();
          return;
        }
      }

      if (app._mode == AppMode.streaming ||
          app._mode == AppMode.toolRunning ||
          app._mode == AppMode.bashRunning) {
        final result = handleStreamingInput(
          event: event,
          isBashRunning: app._mode == AppMode.bashRunning,
          editor: app.editor,
          autocomplete: app._autocomplete,
          commands: app._commands,
        );
        if (result.commandOutput != null && result.commandOutput!.isNotEmpty) {
          app._blocks.add(_ConversationEntry.system(result.commandOutput!));
        }
        switch (result.action) {
          case StreamingAction.render:
            app._render();
          case StreamingAction.swallowed:
            break;
          case StreamingAction.cancelAgent:
            app._cancelAgent();
          case StreamingAction.cancelBash:
            app._cancelBash();
        }
        return;
      }

      // Autocomplete intercepts keys when active.
      if (app._autocomplete.active) {
        if (event case KeyEvent(key: Key.up)) {
          app._autocomplete.moveUp();
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.down)) {
          app._autocomplete.moveDown();
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.tab)) {
          final accepted = app._autocomplete.accept();
          if (accepted != null) {
            app.editor.setText(accepted);
          }
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.enter)) {
          if (app._autocomplete.selectedText == app.editor.text) {
            app._autocomplete.dismiss();
            // Fall through to normal submit handling.
          } else {
            final accepted = app._autocomplete.accept();
            if (accepted != null) {
              app.editor.setText(accepted);
            }
            app._render();
            return;
          }
        }
        if (event case KeyEvent(key: Key.escape)) {
          app._autocomplete.dismiss();
          app._render();
          return;
        }
      }

      // Shell completion intercepts keys when active (bash mode).
      if (app._shellComplete.active) {
        if (event case KeyEvent(key: Key.up)) {
          app._shellComplete.moveUp();
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.down)) {
          app._shellComplete.moveDown();
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.tab) || KeyEvent(key: Key.enter)) {
          final result = app._shellComplete.accept();
          if (result != null) {
            app.editor.setText(result.text, cursor: result.cursor);
          }
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.escape)) {
          app._shellComplete.dismiss();
          app._render();
          return;
        }
      }

      // @file hint intercepts keys when active.
      if (app._atHint.active) {
        if (event case KeyEvent(key: Key.up)) {
          app._atHint.moveUp();
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.down)) {
          app._atHint.moveDown();
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.enter) || KeyEvent(key: Key.tab)) {
          final start = app._atHint.tokenStart;
          final cursor = app.editor.cursor;
          final accepted = app._atHint.accept();
          if (accepted != null) {
            final buf = app.editor.text;
            final before = buf.substring(0, start);
            final after = buf.substring(cursor);
            app.editor.setText('$before$accepted$after',
                cursor: before.length + accepted.length);
          }
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.escape)) {
          app._atHint.dismiss();
          app._render();
          return;
        }
      }

      // Normal idle mode — full input handling.
      final action = app.editor.handle(event);
      switch (action) {
        case InputAction.submit:
          app._autocomplete.dismiss();
          app._atHint.dismiss();
          app._shellComplete.dismiss();
          final text = app.editor.lastSubmitted;
          if (text.isNotEmpty) {
            app._events.add(UserSubmit(text));
          }
        case InputAction.interrupt:
          final now = DateTime.now();
          if (app._lastCtrlC != null &&
              now.difference(app._lastCtrlC!) <
                  AppConstants.ctrlCDoubleTapWindow) {
            app._lastCtrlC = null;
            app.requestExit();
          } else {
            app._lastCtrlC = now;
            app._blocks
                .add(_ConversationEntry.system('Press Ctrl+C again to exit.'));
            app._render();
          }
        case InputAction.changed:
          if (app._bashMode) {
            app._shellComplete.dismiss();
          } else {
            app._autocomplete.update(app.editor.text, app.editor.cursor);
            if (!app._autocomplete.active) {
              app._atHint.update(app.editor.text, app.editor.cursor);
            } else {
              app._atHint.dismiss();
            }
          }
          app._render();
        case InputAction.requestCompletion:
          if (app._bashMode) {
            app._shellComplete
                .requestCompletions(app.editor.text, app.editor.cursor)
                .then((_) => app._render());
          }
        default:
          break;
      }

    case ResizeEvent(:final cols, :final rows):
      app._events.add(UserResize(cols, rows));

    case MouseEvent(
        :final x,
        :final y,
        :final isScroll,
        :final isScrollUp,
        :final isDown
      ):
      if (isScroll) {
        app._events.add(UserScroll(isScrollUp ? 3 : -3));
      } else if (isDown) {
        if (y >= app.layout.outputTop && y <= app.layout.outputBottom) {
          final viewportHeight =
              app.layout.outputBottom - app.layout.outputTop + 1;
          final totalLines = app._outputLineGroups.length;
          final firstLine = (totalLines - viewportHeight - app._scrollOffset)
              .clamp(0, totalLines);
          final outputLineIdx = firstLine + (y - app.layout.outputTop);
          if (outputLineIdx >= 0 &&
              outputLineIdx < app._outputLineGroups.length) {
            final group = app._outputLineGroups[outputLineIdx];
            if (group != null) {
              group.expanded = !group.expanded;
              app._render();
              return;
            }
          }
        }
        if (app._liquidSim != null) {
          app._handleSplashClick(x, y);
        }
      }

    case PasteEvent():
      // Dismiss popups before inserting paste content.
      app._autocomplete.dismiss();
      app._atHint.dismiss();
      final action = app.editor.handle(event);
      if (action == InputAction.changed) {
        app._autocomplete.update(app.editor.text, app.editor.cursor);
        if (!app._autocomplete.active) {
          app._atHint.update(app.editor.text, app.editor.cursor);
        }
        app._render();
      }
  }
}
