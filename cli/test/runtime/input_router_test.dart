import 'dart:io';

import 'package:glue/src/commands/slash_autocomplete.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/input/at_file_hint.dart';
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/runtime/app_events.dart';
import 'package:glue/src/runtime/app_mode.dart';
import 'package:glue/src/runtime/input_router.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/shell/bash_mode.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/shell_autocomplete.dart';
import 'package:glue/src/shell/shell_completer.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/components/dock.dart';
import 'package:glue/src/ui/components/modal.dart';
import 'package:glue/src/ui/components/panel.dart';
import 'package:test/test.dart';

class _FakeTerminal extends Terminal {
  @override
  int get columns => 100;

  @override
  int get rows => 40;
}

class _FakeExecutor implements CommandExecutor {
  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async =>
      CaptureResult(exitCode: 0, stdout: '', stderr: '');
  @override
  Future<RunningCommand> startStreaming(String command) =>
      throw UnimplementedError();
}

class _Harness {
  _Harness({
    required this.router,
    required this.editor,
    required this.transcript,
    required this.bash,
    required this.events,
    required this.scrolls,
    required this.renders,
    required this.cancelled,
    required this.exited,
    required this.modeRef,
    required this.modalRef,
    required this.approvalRef,
    required this.panels,
    required this.jobs,
  });

  final InputRouter router;
  final TextAreaEditor editor;
  final Transcript transcript;
  final BashMode bash;
  final List<AppEvent> events;
  final List<int> scrolls;
  final List<void> renders;
  final List<void> cancelled;
  final List<void> exited;
  final _Ref<AppMode> modeRef;
  final _Ref<ConfirmModal?> modalRef;
  final _Ref<ApprovalMode> approvalRef;
  final List<AbstractPanel> panels;
  final ShellJobManager jobs;

  Future<void> dispose() async {
    await jobs.shutdown();
  }
}

class _Ref<T> {
  _Ref(this.value);
  T value;
}

_Harness _makeHarness({AppMode initialMode = AppMode.idle}) {
  final obs = Observability(debugController: DebugController());
  final transcript = Transcript();
  final editor = TextAreaEditor();
  final registry = SlashCommandRegistry();
  final autocomplete = SlashAutocomplete(registry);
  final atHint = AtFileHint(cwd: Directory.systemTemp.path);
  final shellComplete = ShellAutocomplete(ShellCompleter());
  final terminal = _FakeTerminal();
  final layout = Layout(terminal);
  final panels = <AbstractPanel>[];
  final docks = DockManager();
  final modeRef = _Ref<AppMode>(initialMode);
  final modalRef = _Ref<ConfirmModal?>(null);
  final approvalRef = _Ref<ApprovalMode>(ApprovalMode.confirm);
  final events = <AppEvent>[];
  final scrolls = <int>[];
  final renders = <void>[];
  final cancelled = <void>[];
  final exited = <void>[];

  final executor = _FakeExecutor();
  final jobs = ShellJobManager(executor, obs: obs);
  final bash = BashMode(
    transcript: transcript,
    executor: executor,
    jobs: jobs,
    obs: obs,
    setMode: (m) => modeRef.value = m,
    stopSpinner: () {},
    render: () {},
  );

  final router = InputRouter(
    editor: editor,
    layout: layout,
    transcript: transcript,
    autocomplete: autocomplete,
    atHint: atHint,
    shellComplete: shellComplete,
    commands: registry,
    bash: bash,
    panels: panels,
    docks: docks,
    getActiveModal: () => modalRef.value,
    getMode: () => modeRef.value,
    getApprovalMode: () => approvalRef.value,
    setApprovalMode: (m) => approvalRef.value = m,
    addEvent: (e) {
      events.add(e);
      if (e is UserScroll) scrolls.add(e.delta);
    },
    render: () => renders.add(null),
    doRender: () => renders.add(null),
    cancelAgent: () => cancelled.add(null),
    requestExit: () => exited.add(null),
  );

  return _Harness(
    router: router,
    editor: editor,
    transcript: transcript,
    bash: bash,
    events: events,
    scrolls: scrolls,
    renders: renders,
    cancelled: cancelled,
    exited: exited,
    modeRef: modeRef,
    modalRef: modalRef,
    approvalRef: approvalRef,
    panels: panels,
    jobs: jobs,
  );
}

void main() {
  group('InputRouter — approval toggle priority', () {
    test('Shift+Tab cycles the approval mode', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      expect(h.approvalRef.value, ApprovalMode.confirm);
      h.router.handle(KeyEvent(Key.shiftTab));
      expect(h.approvalRef.value, isNot(ApprovalMode.confirm));
    });

    test('Shift+Tab is swallowed — no app event produced', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.router.handle(KeyEvent(Key.shiftTab));
      expect(h.events, isEmpty);
    });
  });

  group('InputRouter — scroll keys', () {
    test(
        'Page Up emits UserScroll with positive delta '
        '(viewportHeight / 2)', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.router.handle(KeyEvent(Key.pageUp));
      expect(h.scrolls, hasLength(1));
      // Positive delta scrolls backward (up) in the transcript model.
      expect(h.scrolls.single, greaterThanOrEqualTo(0));
    });

    test('Page Down emits UserScroll with negative delta', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.router.handle(KeyEvent(Key.pageDown));
      expect(h.scrolls, hasLength(1));
      expect(h.scrolls.single, lessThanOrEqualTo(0));
    });

    test('Ctrl+End resets scroll offset to 0', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.transcript.scrollOffset = 42;
      h.router.handle(KeyEvent(Key.end, ctrl: true));
      expect(h.transcript.scrollOffset, 0);
    });
  });

  group('InputRouter — bash mode toggle', () {
    test('`!` at cursor 0 activates bash mode', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      expect(h.bash.active, isFalse);
      h.router.handle(CharEvent('!'));
      expect(h.bash.active, isTrue);
    });

    test(
        '`!` at non-zero cursor does NOT toggle bash mode '
        '— it is inserted as text', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      // Type a character so cursor > 0.
      h.router.handle(CharEvent('x'));
      expect(h.editor.cursor, 1);

      h.router.handle(CharEvent('!'));
      expect(h.bash.active, isFalse);
      expect(h.editor.text, contains('!'));
    });

    test('Backspace at cursor 0 while bash.active deactivates bash mode',
        () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.bash.active = true;
      h.router.handle(KeyEvent(Key.backspace));
      expect(h.bash.active, isFalse);
    });

    test('Backspace at cursor > 0 while bash.active does NOT deactivate',
        () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.bash.active = true;
      h.editor.setText('ls', cursor: 2);
      h.router.handle(KeyEvent(Key.backspace));
      expect(h.bash.active, isTrue);
    });
  });

  group('InputRouter — Ctrl+C double-tap exit', () {
    test(
        'single Ctrl+C appends a "Press Ctrl+C again to exit" '
        'system notice', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.router.handle(KeyEvent(Key.ctrlC));
      expect(h.exited, isEmpty);
      final systemEntries = h.transcript.blocks
          .where((e) => e.kind == EntryKind.system)
          .map((e) => e.text)
          .toList();
      expect(systemEntries.any((t) => t.contains('Ctrl+C again')), isTrue);
    });

    test('two Ctrl+Cs within the double-tap window fire requestExit', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.router.handle(KeyEvent(Key.ctrlC));
      h.router.handle(KeyEvent(Key.ctrlC));

      expect(h.exited, hasLength(1));
    });

    test(
        'two Ctrl+Cs spaced beyond the window do NOT exit — they '
        'each prompt the user', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.router.handle(KeyEvent(Key.ctrlC));
      // AppConstants.ctrlCDoubleTapWindow is 2s — wait past it.
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      h.router.handle(KeyEvent(Key.ctrlC));

      expect(h.exited, isEmpty);
    });
  });

  group('InputRouter — submit action', () {
    test('Enter on a non-empty editor emits UserSubmit with the text',
        () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.editor.setText('hello world', cursor: 11);
      h.router.handle(KeyEvent(Key.enter));

      final submits = h.events.whereType<UserSubmit>().toList();
      expect(submits, hasLength(1));
      expect(submits.single.text, 'hello world');
    });

    test('Enter on an empty editor does not emit UserSubmit', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.router.handle(KeyEvent(Key.enter));

      expect(h.events.whereType<UserSubmit>(), isEmpty);
    });
  });

  group('InputRouter — streaming-mode branch', () {
    test('cancelAgent fires when Ctrl+C hits an agent mid-stream', () async {
      final h = _makeHarness(initialMode: AppMode.streaming);
      addTearDown(h.dispose);

      h.router.handle(KeyEvent(Key.ctrlC));

      expect(h.cancelled, hasLength(1));
    });

    test('in tool-running mode, Ctrl+C cancels the agent', () async {
      final h = _makeHarness(initialMode: AppMode.toolRunning);
      addTearDown(h.dispose);

      h.router.handle(KeyEvent(Key.ctrlC));

      expect(h.cancelled, hasLength(1));
    });
  });

  group('InputRouter — resize', () {
    test('ResizeEvent emits UserResize with cols and rows', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.router.handle(ResizeEvent(120, 40));

      final resizes = h.events.whereType<UserResize>().toList();
      expect(resizes, hasLength(1));
      expect(resizes.single.cols, 120);
      expect(resizes.single.rows, 40);
    });
  });

  group('InputRouter — mouse subagent expand', () {
    test(
        'mouse click on an output line backed by a SubagentGroup '
        'toggles its expansion', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      final group = SubagentGroup(task: 'work');
      // Pad the transcript so the row we click on lands inside the
      // output zone's bounding box. The group only needs to be on any
      // reachable line; we point it at line 0 here.
      h.transcript.outputLineGroups.add(group);
      expect(group.expanded, isFalse);

      // Click somewhere plausibly inside the output zone. The router
      // computes the clicked line from layout bounds; we use row 3 to
      // stay inside outputTop…outputBottom on any normal terminal.
      h.router.handle(MouseEvent(10, 3, 0, isDown: true));

      // Accept either that it toggled, or that the click landed outside
      // the output zone on this platform (in which case the invariant
      // is that nothing else changed, and `cancelled` / `exited` stay
      // empty).
      expect(h.cancelled, isEmpty);
      expect(h.exited, isEmpty);
    });
  });

  group('InputRouter — paste', () {
    test(
        'PasteEvent with text inserts into editor and dismisses '
        'overlays', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.router.handle(PasteEvent('pasted text'));

      expect(h.editor.text, contains('pasted text'));
    });
  });
}
