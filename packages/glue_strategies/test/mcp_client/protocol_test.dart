import 'package:glue_strategies/src/mcp_client/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('McpInitializeResult.fromJson', () {
    test('parses a minimal payload', () {
      final result = McpInitializeResult.fromJson({
        'protocolVersion': '2025-03-26',
        'serverInfo': {'name': 'srv', 'version': '1.0.0'},
        'capabilities': const {},
      });
      expect(result.protocolVersion, '2025-03-26');
      expect(result.serverInfo.name, 'srv');
      expect(result.capabilities.supportsSampling, isFalse);
    });

    test('parses tools.listChanged capability', () {
      final result = McpInitializeResult.fromJson({
        'protocolVersion': '2025-03-26',
        'serverInfo': {'name': 'srv', 'version': '1.0.0'},
        'capabilities': {
          'tools': {'listChanged': true},
        },
      });
      expect(result.capabilities.tools?.listChanged, isTrue);
    });

    test('captures sampling capability without crashing', () {
      final result = McpInitializeResult.fromJson({
        'protocolVersion': '2025-03-26',
        'serverInfo': {'name': 'srv', 'version': '1.0.0'},
        'capabilities': {'sampling': {}},
      });
      expect(result.capabilities.supportsSampling, isTrue);
    });
  });

  group('McpToolCallResult.fromJson', () {
    test('text-only content', () {
      final r = McpToolCallResult.fromJson({
        'content': [
          {'type': 'text', 'text': 'hello'},
          {'type': 'text', 'text': 'world'},
        ],
      });
      expect(r.isError, isFalse);
      expect(r.textPayload, 'hello\nworld');
    });

    test('opaque content types render as type tag', () {
      final r = McpToolCallResult.fromJson({
        'content': [
          {'type': 'text', 'text': 'before'},
          {'type': 'image', 'data': '...base64...', 'mimeType': 'image/png'},
          {'type': 'text', 'text': 'after'},
        ],
      });
      expect(r.textPayload, 'before\n[image]\nafter');
    });

    test('isError surfaces through', () {
      final r = McpToolCallResult.fromJson({
        'isError': true,
        'content': [
          {'type': 'text', 'text': 'tool reported failure'},
        ],
      });
      expect(r.isError, isTrue);
      expect(r.textPayload, 'tool reported failure');
    });

    test('missing content produces an empty payload', () {
      final r = McpToolCallResult.fromJson(const {});
      expect(r.content, isEmpty);
      expect(r.textPayload, '');
    });
  });

  group('McpToolDescriptor.fromJson', () {
    test('parses name + description + inputSchema', () {
      final t = McpToolDescriptor.fromJson({
        'name': 'echo',
        'description': 'mirror input',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'message': {'type': 'string'},
          },
        },
      });
      expect(t.name, 'echo');
      expect(t.description, 'mirror input');
      expect(t.inputSchema['type'], 'object');
    });

    test('defaults inputSchema when missing', () {
      final t = McpToolDescriptor.fromJson({'name': 'bare'});
      expect(t.inputSchema['type'], 'object');
      expect(t.description, '');
    });
  });
}
