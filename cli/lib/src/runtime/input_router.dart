import 'package:glue/src/app.dart' show AppMode;
import 'package:glue/src/commands/slash_autocomplete.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/input/at_file_hint.dart';
import 'package:glue/src/input/line_editor.dart' show InputAction;
import 'package:glue/src/input/streaming_input_handler.dart';
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/runtime/app_events.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/shell/bash_mode.dart';
import 'package:glue/src/shell/shell_autocomplete.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/components/dock.dart';
import 'package:glue/src/ui/components/modal.dart';
import 'package:glue/src/ui/components/overlays.dart';
import 'package:glue/src/ui/components/panel.dart';

/// Central traffic cop for raw [TerminalEvent]s.
///
/// Given one event, decides who gets to handle it based on current
/// application mode and overlay stack: top panel → confirm modal →
/// docked panel → approval toggle → scroll keys → bash toggle →
/// in-flight-streaming editor → autocomplete overlays → idle editor.
///
/// No business logic of its own. All side effects go through injected
/// dependencies or the [addEvent] callback that feeds App's [AppEvent]
/// bus.
class InputRouter {
  InputRouter({
    required this.editor,
    required this.layout,
    required this.transcript,
    required this.autocomplete,
    required this.atHint,
    required this.shellComplete,
    required this.commands,
    required this.bash,
    required this.panels,
    required this.docks,
    required this.getActiveModal,
    required this.getMode,
    required this.getApprovalMode,
    required this.setApprovalMode,
    required this.addEvent,
    required this.render,
    required this.doRender,
    required this.cancelAgent,
    required this.requestExit,
  });

  final TextAreaEditor editor;
  final Layout layout;
  final Transcript transcript;
  final SlashAutocomplete autocomplete;
  final AtFileHint atHint;
  final ShellAutocomplete shellComplete;
  final SlashCommandRegistry commands;
  final BashMode bash;
  final List<AbstractPanel> panels;
  final DockManager docks;
  final ConfirmModal? Function() getActiveModal;
  final AppMode Function() getMode;
  final ApprovalMode Function() getApprovalMode;
  final void Function(ApprovalMode) setApprovalMode;
  final void Function(AppEvent) addEvent;
  final void Function() render;
  final void Function() doRender;
  final void Function() cancelAgent;
  final void Function() requestExit;

  /// Last Ctrl+C timestamp, used for double-tap-to-exit detection in the
  /// idle path. Scoped to the router because no other path reads it.
  DateTime? _lastCtrlC;

  void handle(TerminalEvent event) {
    switch (event) {
      case CharEvent() || KeyEvent():
        if (panels.isNotEmpty && !panels.last.isComplete) {
          if (panels.last.handleEvent(event)) {
            doRender();
            return;
          }
        }

        final modal = getActiveModal();
        if (modal != null && !modal.isComplete) {
          if (modal.handleEvent(event)) {
            render();
            return;
          }
        }

        if (docks.handleEvent(event)) {
          render();
          return;
        }

        if (event case KeyEvent(key: Key.shiftTab)) {
          setApprovalMode(getApprovalMode().toggle);
          render();
          return;
        }

        if (event case KeyEvent(key: Key.pageUp)) {
          final viewportHeight = layout.outputBottom - layout.outputTop + 1;
          addEvent(UserScroll(viewportHeight ~/ 2));
          return;
        }
        if (event case KeyEvent(key: Key.pageDown)) {
          final viewportHeight = layout.outputBottom - layout.outputTop + 1;
          addEvent(UserScroll(-(viewportHeight ~/ 2)));
          return;
        }
        if (event case KeyEvent(key: Key.end, ctrl: true)) {
          transcript.scrollOffset = 0;
          render();
          return;
        }

        final mode = getMode();

        if (mode == AppMode.idle) {
          if (!bash.active &&
              event is CharEvent &&
              event.char == '!' &&
              editor.cursor == 0) {
            bash.active = true;
            render();
            return;
          }
          if (bash.active &&
              event is KeyEvent &&
              event.key == Key.backspace &&
              editor.cursor == 0) {
            bash.active = false;
            shellComplete.dismiss();
            render();
            return;
          }
        }

        if (mode == AppMode.streaming ||
            mode == AppMode.toolRunning ||
            mode == AppMode.bashRunning) {
          final result = handleStreamingInput(
            event: event,
            isBashRunning: mode == AppMode.bashRunning,
            editor: editor,
            autocomplete: autocomplete,
            commands: commands,
          );
          if (result.commandOutput != null &&
              result.commandOutput!.isNotEmpty) {
            transcript.blocks
                .add(ConversationEntry.system(result.commandOutput!));
          }
          switch (result.action) {
            case StreamingAction.render:
              render();
            case StreamingAction.swallowed:
              break;
            case StreamingAction.cancelAgent:
              cancelAgent();
            case StreamingAction.cancelBash:
              bash.cancel();
          }
          return;
        }

        AutocompleteOverlay? activeOverlay;
        for (final o in <AutocompleteOverlay>[
          autocomplete,
          shellComplete,
          atHint,
        ]) {
          if (o.active) {
            activeOverlay = o;
            break;
          }
        }

        if (activeOverlay != null) {
          if (event case KeyEvent(key: Key.up)) {
            activeOverlay.moveUp();
            render();
            return;
          }
          if (event case KeyEvent(key: Key.down)) {
            activeOverlay.moveDown();
            render();
            return;
          }
          if (event case KeyEvent(key: Key.escape)) {
            activeOverlay.dismiss();
            render();
            return;
          }
          if (event case KeyEvent(key: Key.tab) || KeyEvent(key: Key.enter)) {
            final isEnter = event.key == Key.enter;
            final isEnterOnExactMatch = isEnter &&
                identical(activeOverlay, autocomplete) &&
                autocomplete.selectedText == editor.text;
            if (isEnterOnExactMatch) {
              autocomplete.dismiss();
            } else {
              final result = activeOverlay.accept(editor.text, editor.cursor);
              if (result != null) {
                editor.setText(result.text, cursor: result.cursor);
              }
              render();
              return;
            }
          }
        }

        final action = editor.handle(event);
        switch (action) {
          case InputAction.submit:
            autocomplete.dismiss();
            atHint.dismiss();
            shellComplete.dismiss();
            final text = editor.lastSubmitted;
            if (text.isNotEmpty) {
              addEvent(UserSubmit(text));
            }
          case InputAction.interrupt:
            final now = DateTime.now();
            if (_lastCtrlC != null &&
                now.difference(_lastCtrlC!) <
                    AppConstants.ctrlCDoubleTapWindow) {
              _lastCtrlC = null;
              requestExit();
            } else {
              _lastCtrlC = now;
              transcript.blocks.add(
                  ConversationEntry.system('Press Ctrl+C again to exit.'));
              render();
            }
          case InputAction.changed:
            if (bash.active) {
              shellComplete.dismiss();
            } else {
              autocomplete.update(editor.text, editor.cursor);
              if (!autocomplete.active) {
                atHint.update(editor.text, editor.cursor);
              } else {
                atHint.dismiss();
              }
            }
            render();
          case InputAction.requestCompletion:
            if (bash.active) {
              shellComplete
                  .requestCompletions(editor.text, editor.cursor)
                  .then((_) => render());
            }
          default:
            break;
        }

      case ResizeEvent(:final cols, :final rows):
        addEvent(UserResize(cols, rows));

      case MouseEvent(
          :final y,
          :final isScroll,
          :final isScrollUp,
          :final isDown
        ):
        if (isScroll) {
          addEvent(UserScroll(isScrollUp ? 3 : -3));
        } else if (isDown) {
          if (y >= layout.outputTop && y <= layout.outputBottom) {
            final viewportHeight = layout.outputBottom - layout.outputTop + 1;
            final totalLines = transcript.outputLineGroups.length;
            final firstLine =
                (totalLines - viewportHeight - transcript.scrollOffset)
                    .clamp(0, totalLines);
            final outputLineIdx = firstLine + (y - layout.outputTop);
            if (outputLineIdx >= 0 &&
                outputLineIdx < transcript.outputLineGroups.length) {
              final group = transcript.outputLineGroups[outputLineIdx];
              if (group != null) {
                group.expanded = !group.expanded;
                render();
                return;
              }
            }
          }
        }

      case PasteEvent():
        autocomplete.dismiss();
        atHint.dismiss();
        final action = editor.handle(event);
        if (action == InputAction.changed) {
          autocomplete.update(editor.text, editor.cursor);
          if (!autocomplete.active) {
            atHint.update(editor.text, editor.cursor);
          }
          render();
        }
    }
  }
}
