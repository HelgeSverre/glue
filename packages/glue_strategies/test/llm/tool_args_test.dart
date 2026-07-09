import 'package:glue_strategies/src/llm/tool_args.dart';
import 'package:test/test.dart';

void main() {
  ToolArgsBuffer<String> buffer(String fragments) =>
      ToolArgsBuffer<String>(id: 'id', name: 'tool')..write(fragments);

  test('empty buffer finalises to an empty map', () {
    expect(
      ToolArgsBuffer<String>(id: 'id', name: 'tool').finalizeArguments(),
      isEmpty,
    );
  });

  test('JSON object is parsed into an arguments map', () {
    expect(buffer('{"path":"README.md","n":2}').finalizeArguments(), {
      'path': 'README.md',
      'n': 2,
    });
  });

  test('invalid JSON falls back to _raw', () {
    expect(buffer('{not valid').finalizeArguments(), {'_raw': '{not valid'});
  });

  // L16: valid-but-non-object JSON used to throw a TypeError on the `as Map`
  // cast instead of being caught. It must fall back to `_raw`.
  test('valid JSON string falls back to _raw (L16)', () {
    expect(buffer('"foo"').finalizeArguments(), {'_raw': '"foo"'});
  });

  test('valid JSON array falls back to _raw (L16)', () {
    expect(buffer('[1,2,3]').finalizeArguments(), {'_raw': '[1,2,3]'});
  });

  test('valid JSON number falls back to _raw (L16)', () {
    expect(buffer('42').finalizeArguments(), {'_raw': '42'});
  });
}
