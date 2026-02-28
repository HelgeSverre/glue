import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observed_tool.dart';
import 'package:test/test.dart';

class _MockSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];

  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

class _MockTool extends Tool {
  final String _name;
  final String _description;
  final List<ToolParameter> _parameters;
  String Function(Map<String, dynamic>)? handler;

  _MockTool({
    String name = 'mock_tool',
    String description = 'A mock tool',
    List<ToolParameter>? parameters,
    this.handler,
  })  : _name = name,
        _description = description,
        _parameters = parameters ?? const [];

  @override
  String get name => _name;

  @override
  String get description => _description;

  @override
  List<ToolParameter> get parameters => _parameters;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    if (handler != null) return handler!(args);
    return 'mock result';
  }
}

void main() {
  late _MockSink sink;
  late Observability obs;

  setUp(() {
    sink = _MockSink();
    obs = Observability(debugController: DebugController());
    obs.addSink(sink);
  });

  test('delegates name to inner tool', () {
    final inner = _MockTool(name: 'my_tool');
    final observed = ObservedTool(inner: inner, obs: obs);
    expect(observed.name, 'my_tool');
  });

  test('delegates description to inner tool', () {
    final inner = _MockTool(description: 'Does something');
    final observed = ObservedTool(inner: inner, obs: obs);
    expect(observed.description, 'Does something');
  });

  test('delegates parameters to inner tool', () {
    final params = [
      const ToolParameter(
        name: 'path',
        type: 'string',
        description: 'File path',
      ),
    ];
    final inner = _MockTool(parameters: params);
    final observed = ObservedTool(inner: inner, obs: obs);
    expect(observed.parameters, equals(params));
  });

  test('creates and ends span on successful execute', () async {
    final inner = _MockTool(name: 'read_file');
    final observed = ObservedTool(inner: inner, obs: obs);

    await observed.execute({'path': 'test.txt'});

    expect(sink.spans, hasLength(1));
    expect(sink.spans.first.name, 'tool.read_file');
    expect(sink.spans.first.kind, 'tool');
    expect(sink.spans.first.endTime, isNotNull);
  });

  test('records tool.name and tool.args attributes', () async {
    final inner = _MockTool(name: 'read_file');
    final observed = ObservedTool(inner: inner, obs: obs);
    final args = {'path': 'test.txt'};

    await observed.execute(args);

    expect(sink.spans.first.attributes['tool.name'], 'read_file');
    expect(sink.spans.first.attributes['tool.args'], args);
  });

  test('records tool.result_length on success', () async {
    final inner = _MockTool(handler: (_) => 'hello world');
    final observed = ObservedTool(inner: inner, obs: obs);

    await observed.execute({});

    expect(sink.spans.first.attributes['tool.result_length'], 11);
  });

  test('returns result from inner tool', () async {
    final inner = _MockTool(handler: (_) => 'expected output');
    final observed = ObservedTool(inner: inner, obs: obs);

    final result = await observed.execute({});

    expect(result, 'expected output');
  });

  test('creates and ends span with error on execute failure', () async {
    final inner = _MockTool(handler: (_) => throw Exception('tool broke'));
    final observed = ObservedTool(inner: inner, obs: obs);

    expect(
      () => observed.execute({}),
      throwsA(isA<Exception>()),
    );

    await Future<void>.delayed(Duration.zero);

    expect(sink.spans, hasLength(1));
    expect(sink.spans.first.attributes['error'], contains('tool broke'));
    expect(sink.spans.first.endTime, isNotNull);
  });

  test('rethrows exception from inner tool', () async {
    final inner = _MockTool(handler: (_) => throw StateError('bad state'));
    final observed = ObservedTool(inner: inner, obs: obs);

    expect(
      () => observed.execute({}),
      throwsA(isA<StateError>()),
    );
  });

  group('wrapToolsWithObservability', () {
    test('wraps all tools in the map', () {
      final tool1 = _MockTool(name: 'tool_a');
      final tool2 = _MockTool(name: 'tool_b');
      final tools = {'tool_a': tool1, 'tool_b': tool2};

      final wrapped = wrapToolsWithObservability(tools, obs);

      expect(wrapped.length, 2);
      expect(wrapped['tool_a'], isA<ObservedTool>());
      expect(wrapped['tool_b'], isA<ObservedTool>());
    });

    test('preserves tool keys', () {
      final tool = _MockTool(name: 'my_tool');
      final tools = {'my_tool': tool};

      final wrapped = wrapToolsWithObservability(tools, obs);

      expect(wrapped.containsKey('my_tool'), isTrue);
      expect(wrapped['my_tool']!.name, 'my_tool');
    });

    test('wrapped tools produce spans', () async {
      final tool = _MockTool(name: 'test_tool');
      final tools = {'test_tool': tool};
      final wrapped = wrapToolsWithObservability(tools, obs);

      await wrapped['test_tool']!.execute({});

      expect(sink.spans, hasLength(1));
      expect(sink.spans.first.name, 'tool.test_tool');
    });
  });
}
