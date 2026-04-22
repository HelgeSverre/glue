import 'package:acp/acp.dart';
import 'package:glue/src/acp/glue_acp_agent.dart';
import 'package:test/test.dart';

void main() {
  group('glueAcpRequiresApproval', () {
    test('returns true for mutating tools', () {
      expect(glueAcpRequiresApproval('write_file'), isTrue);
      expect(glueAcpRequiresApproval('edit_file'), isTrue);
      expect(glueAcpRequiresApproval('bash'), isTrue);
    });

    test('returns false for read/search tools', () {
      expect(glueAcpRequiresApproval('read_file'), isFalse);
      expect(glueAcpRequiresApproval('list_directory'), isFalse);
      expect(glueAcpRequiresApproval('grep'), isFalse);
      expect(glueAcpRequiresApproval('skill'), isFalse);
    });
  });

  group('glueAcpIsAllowedPermissionOutcome', () {
    test('returns true for selected allow_once', () {
      expect(
        glueAcpIsAllowedPermissionOutcome(<String, dynamic>{
          'outcome': 'selected',
          'optionId': 'allow_once',
        }),
        isTrue,
      );
    });

    test('returns false for non-allow outcomes and malformed payloads', () {
      expect(
        glueAcpIsAllowedPermissionOutcome(<String, dynamic>{
          'outcome': 'selected',
          'optionId': 'reject_once',
        }),
        isFalse,
      );
      expect(
        glueAcpIsAllowedPermissionOutcome(<String, dynamic>{
          'outcome': 'dismissed',
          'optionId': 'allow_once',
        }),
        isFalse,
      );
      expect(glueAcpIsAllowedPermissionOutcome(<String, dynamic>{}), isFalse);
      expect(
        glueAcpIsAllowedPermissionOutcome(<String, dynamic>{
          'outcome': 123,
          'optionId': true,
        }),
        isFalse,
      );
    });
  });

  group('glueAcpPromptToText', () {
    test('converts text/resource/embedded blocks in order', () {
      final text = glueAcpPromptToText(<ContentBlock>[
        const TextContent(text: 'hello'),
        const ResourceLink(name: 'readme', uri: 'file:///repo/README.md'),
        const EmbeddedResource(resource: <String, dynamic>{'kind': 'snippet'}),
      ]);

      expect(
        text,
        'hello\n'
        '[resource] readme (file:///repo/README.md)\n'
        '[embedded_resource] {"kind":"snippet"}',
      );
    });

    test('marks unsupported content blocks explicitly', () {
      final text = glueAcpPromptToText(<ContentBlock>[
        const UnknownContentBlock(type: 'future_block', rawJson: <String, dynamic>{}),
      ]);
      expect(text, contains('[unsupported_content:UnknownContentBlock]'));
    });
  });
}
