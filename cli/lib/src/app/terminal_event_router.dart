part of 'package:glue/src/app.dart';

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

      // Approval mode toggle — works in all modes.
      if (event case KeyEvent(key: Key.shiftTab)) {
        app._approvalMode = app._approvalMode.toggle;
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
      // Ctrl+End jumps to the bottom and resumes follow-tail. Plain End is
      // reserved for the line editor (jump cursor to end of line).
      if (event case KeyEvent(key: Key.end, ctrl: true)) {
        app._transcript.scrollOffset = 0;
        app._render();
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
          app._transcript.blocks
              .add(ConversationEntry.system(result.commandOutput!));
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

      // Any active autocomplete overlay intercepts Up/Down/Tab/Enter/Esc.
      AutocompleteOverlay? activeOverlay;
      for (final o in <AutocompleteOverlay>[
        app._autocomplete,
        app._shellComplete,
        app._atHint,
      ]) {
        if (o.active) {
          activeOverlay = o;
          break;
        }
      }

      if (activeOverlay != null) {
        if (event case KeyEvent(key: Key.up)) {
          activeOverlay.moveUp();
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.down)) {
          activeOverlay.moveDown();
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.escape)) {
          activeOverlay.dismiss();
          app._render();
          return;
        }
        if (event case KeyEvent(key: Key.tab) || KeyEvent(key: Key.enter)) {
          // Slash-autocomplete: Enter on an exact match submits instead
          // of re-accepting the same text — fall through to submit below.
          final isEnter = event.key == Key.enter;
          final isEnterOnExactMatch = isEnter &&
              identical(activeOverlay, app._autocomplete) &&
              app._autocomplete.selectedText == app.editor.text;
          if (isEnterOnExactMatch) {
            app._autocomplete.dismiss();
          } else {
            final result =
                activeOverlay.accept(app.editor.text, app.editor.cursor);
            if (result != null) {
              app.editor.setText(result.text, cursor: result.cursor);
            }
            app._render();
            return;
          }
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
            app._transcript.blocks
                .add(ConversationEntry.system('Press Ctrl+C again to exit.'));
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
          final totalLines = app._transcript.outputLineGroups.length;
          final firstLine =
              (totalLines - viewportHeight - app._transcript.scrollOffset)
                  .clamp(0, totalLines);
          final outputLineIdx = firstLine + (y - app.layout.outputTop);
          if (outputLineIdx >= 0 &&
              outputLineIdx < app._transcript.outputLineGroups.length) {
            final group = app._transcript.outputLineGroups[outputLineIdx];
            if (group != null) {
              group.expanded = !group.expanded;
              app._render();
              return;
            }
          }
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
