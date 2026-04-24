import 'dart:async';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/app.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:test/test.dart';

class _NoopTerminal extends Terminal {
  @override
  Stream<TerminalEvent> get events => const Stream.empty();

  @override
  int get columns => 120;

  @override
  int get rows => 40;

  @override
  void clearScreen() {}

  @override
  void clearLine() {}

  @override
  void disableAltScreen() {}

  @override
  void disableMouse() {}

  @override
  void disableRawMode() {}

  @override
  void enableAltScreen() {}

  @override
  void enableMouse() {}

  @override
  void enableRawMode() {}

  @override
  void hideCursor() {}

  @override
  bool get isRaw => false;

  @override
  void moveTo(int row, int col) {}

  @override
  void resetScrollRegion() {}

  @override
  void restoreCursor() {}

  @override
  void saveCursor() {}

  @override
  void setScrollRegion(int top, int bottom) {}

  @override
  void showCursor() {}

  @override
  void write(String text) {}

  @override
  void writeStyled(String text, {AnsiStyle? style}) {}
}

class _NoopLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {}
}

class _DisposableTool extends Tool {
  int disposeCount = 0;

  @override
  String get name => 'disposable';

  @override
  String get description => 'disposable test tool';

  @override
  List<ToolParameter> get parameters => const [];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      ToolResult(content: 'ok');

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

class _RecordingSink extends ObservabilitySink {
  int flushCount = 0;
  int closeCount = 0;

  @override
  void onSpan(ObservabilitySpan span) {}

  @override
  Future<void> flush() async {
    flushCount++;
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

void main() {
  test('print mode teardown runs when validation returns early', () async {
    final tempDir = Directory.systemTemp.createTempSync('print_mode_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
    environment.ensureDirectories();
    final terminal = _NoopTerminal();
    final tool = _DisposableTool();
    final sink = _RecordingSink();
    final obs = Observability(debugController: DebugController())
      ..addSink(sink);
    final app = App(
      terminal: terminal,
      layout: Layout(terminal),
      editor: TextAreaEditor(),
      agent: Agent(
        llm: _NoopLlm(),
        tools: {tool.name: tool},
        obs: obs,
      ),
      modelId: 'test',
      printMode: true,
      resumeSessionId: '',
      obs: obs,
      environment: environment,
    );

    await app.run();

    expect(tool.disposeCount, 1);
    expect(sink.flushCount, 1);
    expect(sink.closeCount, 1);
  });
}
