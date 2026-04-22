import 'package:glue/src/share/share_models.dart';
import 'package:glue/src/share/share_transcript_builder.dart';
import 'package:test/test.dart';

void main() {
  group('ShareTranscriptBuilder', () {
    test('builds transcript entries from visible session events', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {'type': 'user_message', 'text': 'hello'},
        {'type': 'assistant_message', 'text': 'hi'},
        {
          'type': 'tool_call',
          'name': 'read_file',
          'arguments': {'path': 'README.md'},
        },
        {'type': 'tool_result', 'content': 'contents'},
      ]);

      expect(transcript.entries.map((e) => e.kind), [
        ShareEntryKind.user,
        ShareEntryKind.assistant,
        ShareEntryKind.toolCall,
        ShareEntryKind.toolResult,
      ]);
      expect(transcript.entries.map((e) => e.index), [1, 2, 3, 4]);
      expect(transcript.entries[2].toolName, 'read_file');
      expect(transcript.entries[2].toolArguments, {'path': 'README.md'});
      expect(transcript.entries[3].text, 'contents');
    });

    test('ignores non-visual title lifecycle events', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {'type': 'title_generated', 'title': 'foo'},
        {'type': 'user_message', 'text': 'hello'},
        {'type': 'title_reevaluated', 'title': 'bar'},
      ]);

      expect(transcript.entries, hasLength(1));
      expect(transcript.entries.single.kind, ShareEntryKind.user);
      expect(transcript.entries.single.text, 'hello');
    });

    test('prefers tool result summary over content', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {
          'type': 'tool_result',
          'summary': '2 files changed',
          'content': 'long detailed output',
        },
      ]);

      expect(transcript.entries.single.kind, ShareEntryKind.toolResult);
      expect(transcript.entries.single.text, '2 files changed');
    });

    test('ignores raw subagent-like events until a persisted schema exists',
        () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {'type': 'subagent_message', 'text': 'ui-only update'},
        {'type': 'user_message', 'text': 'hello'},
      ]);

      expect(transcript.entries, hasLength(1));
      expect(transcript.entries.single.kind, ShareEntryKind.user);
      expect(transcript.entries.single.text, 'hello');
    });

    test('supports nested subagent fixture entries', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.fromEntries([
        const ShareEntry(
          index: 1,
          kind: ShareEntryKind.subagentGroup,
          text: 'docs-research',
          subagentId: 'sub-1',
          children: [
            ShareEntry(
              index: 2,
              kind: ShareEntryKind.subagentMessage,
              text: 'checking template packages',
              subagentId: 'sub-1',
              nestingLevel: 1,
            ),
            ShareEntry(
              index: 3,
              kind: ShareEntryKind.subagentGroup,
              text: 'html-safety-review',
              subagentId: 'sub-2',
              nestingLevel: 1,
              children: [
                ShareEntry(
                  index: 4,
                  kind: ShareEntryKind.subagentMessage,
                  text: 'review raw HTML policy',
                  subagentId: 'sub-2',
                  nestingLevel: 2,
                ),
              ],
            ),
          ],
        ),
      ]);

      expect(transcript.entries.single.kind, ShareEntryKind.subagentGroup);
      expect(transcript.entries.single.children, hasLength(2));
      expect(
        transcript.entries.single.children[1].children.single.text,
        'review raw HTML policy',
      );
    });
  });
}
