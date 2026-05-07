import 'package:glue_harness/glue_harness.dart';
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

    test('ignores unknown event types', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {'type': 'subagent_message', 'text': 'old fictional type'},
        {'type': 'user_message', 'text': 'hello'},
      ]);

      expect(transcript.entries, hasLength(1));
      expect(transcript.entries.single.kind, ShareEntryKind.user);
      expect(transcript.entries.single.text, 'hello');
    });

    test('builds a subagent group from spawned/event/completed rows', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {'type': 'user_message', 'text': 'analyze repo'},
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-1',
          'task': 'docs-research',
          'depth': 0,
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-1',
          'inner': {
            'type': 'tool_call',
            'name': 'read_file',
            'arguments': {'path': 'README.md'},
          },
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-1',
          'inner': {'type': 'tool_result', 'content': 'contents'},
        },
        {'type': 'subagent_completed', 'subagent_id': 'sub-1'},
        {'type': 'assistant_message', 'text': 'done'},
      ]);

      expect(
        transcript.entries.map((e) => e.kind).toList(),
        [
          ShareEntryKind.user,
          ShareEntryKind.subagentGroup,
          ShareEntryKind.assistant,
        ],
      );
      final group = transcript.entries[1];
      expect(group.subagentId, 'sub-1');
      expect(group.text, 'docs-research');
      expect(group.children, hasLength(2));
      expect(group.children[0].kind, ShareEntryKind.toolCall);
      expect(group.children[0].toolName, 'read_file');
      expect(group.children[1].kind, ShareEntryKind.toolResult);
      expect(group.children[1].text, 'contents');
    });

    test('builds two sequential subagent groups', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-a',
          'task': 'first',
          'index': 0,
          'total': 2,
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-a',
          'inner': {'type': 'assistant_message', 'text': 'progress a'},
        },
        {'type': 'subagent_completed', 'subagent_id': 'sub-a'},
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-b',
          'task': 'second',
          'index': 1,
          'total': 2,
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-b',
          'inner': {'type': 'assistant_message', 'text': 'progress b'},
        },
        {'type': 'subagent_completed', 'subagent_id': 'sub-b'},
      ]);

      final groups = transcript.entries
          .where((e) => e.kind == ShareEntryKind.subagentGroup)
          .toList();
      expect(groups, hasLength(2));
      expect(groups.map((g) => g.subagentId), ['sub-a', 'sub-b']);
      expect(groups[0].children.single.text, 'progress a');
      expect(groups[1].children.single.text, 'progress b');
    });

    test('three parallel subagents with interleaved events render as siblings',
        () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {'type': 'user_message', 'text': 'go'},
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-a',
          'task': 'task-a',
          'depth': 0,
          'index': 0,
          'total': 3,
        },
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-b',
          'task': 'task-b',
          'depth': 0,
          'index': 1,
          'total': 3,
        },
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-c',
          'task': 'task-c',
          'depth': 0,
          'index': 2,
          'total': 3,
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-a',
          'inner': {'type': 'assistant_message', 'text': 'a-progress'},
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-b',
          'inner': {'type': 'assistant_message', 'text': 'b-progress'},
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-c',
          'inner': {'type': 'assistant_message', 'text': 'c-progress'},
        },
        {'type': 'subagent_completed', 'subagent_id': 'sub-a'},
        {'type': 'subagent_completed', 'subagent_id': 'sub-b'},
        {'type': 'subagent_completed', 'subagent_id': 'sub-c'},
        {'type': 'assistant_message', 'text': 'all done'},
      ]);

      expect(
        transcript.entries.map((e) => e.kind).toList(),
        [
          ShareEntryKind.user,
          ShareEntryKind.subagentGroup,
          ShareEntryKind.subagentGroup,
          ShareEntryKind.subagentGroup,
          ShareEntryKind.assistant,
        ],
        reason:
            'parallel subagents must render as siblings, not nested under each '
            'other, and the trailing assistant message must stay top-level',
      );
      final groups = transcript.entries
          .where((e) => e.kind == ShareEntryKind.subagentGroup)
          .toList();
      expect(groups.map((g) => g.subagentId), ['sub-a', 'sub-b', 'sub-c']);
      for (final g in groups) {
        expect(g.nestingLevel, 0);
      }
      expect(groups[0].children.single.text, 'a-progress');
      expect(groups[1].children.single.text, 'b-progress');
      expect(groups[2].children.single.text, 'c-progress');
    });

    test(
        'parallel subagents completing out of spawn order still render as '
        'siblings', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-a',
          'task': 'a',
          'depth': 0,
        },
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-b',
          'task': 'b',
          'depth': 0,
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-a',
          'inner': {'type': 'assistant_message', 'text': 'a says'},
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-b',
          'inner': {'type': 'assistant_message', 'text': 'b says'},
        },
        {'type': 'subagent_completed', 'subagent_id': 'sub-b'},
        {'type': 'subagent_completed', 'subagent_id': 'sub-a'},
        {'type': 'user_message', 'text': 'next'},
      ]);

      expect(transcript.entries.map((e) => e.kind).toList(), [
        ShareEntryKind.subagentGroup,
        ShareEntryKind.subagentGroup,
        ShareEntryKind.user,
      ]);
      expect(transcript.entries[0].subagentId, 'sub-a');
      expect(transcript.entries[1].subagentId, 'sub-b');
      expect(transcript.entries[0].children.single.text, 'a says');
      expect(transcript.entries[1].children.single.text, 'b says');
    });

    test(
        'parallel sibling that spawns its own nested child via parent_subagent_id',
        () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-a',
          'task': 'a',
          'depth': 0,
        },
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-b',
          'task': 'b',
          'depth': 0,
        },
        {
          'type': 'subagent_spawned',
          'subagent_id': 'sub-a-child',
          'task': 'a-child',
          'depth': 1,
          'parent_subagent_id': 'sub-a',
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'sub-a-child',
          'inner': {'type': 'assistant_message', 'text': 'child of a'},
        },
        {'type': 'subagent_completed', 'subagent_id': 'sub-a-child'},
        {'type': 'subagent_completed', 'subagent_id': 'sub-a'},
        {'type': 'subagent_completed', 'subagent_id': 'sub-b'},
      ]);

      expect(transcript.entries.map((e) => e.subagentId).toList(),
          ['sub-a', 'sub-b']);
      final a = transcript.entries[0];
      expect(a.children, hasLength(1));
      expect(a.children.single.kind, ShareEntryKind.subagentGroup);
      expect(a.children.single.subagentId, 'sub-a-child');
      expect(a.children.single.children.single.text, 'child of a');
      expect(transcript.entries[1].children, isEmpty);
    });

    test('handles a nested subagent that spawns its own subagent', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {
          'type': 'subagent_spawned',
          'subagent_id': 'parent',
          'task': 'parent-task',
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'parent',
          'inner': {'type': 'assistant_message', 'text': 'parent says hi'},
        },
        {
          'type': 'subagent_spawned',
          'subagent_id': 'child',
          'task': 'child-task',
          'depth': 1,
        },
        {
          'type': 'subagent_event',
          'subagent_id': 'child',
          'inner': {'type': 'assistant_message', 'text': 'child works'},
        },
        {'type': 'subagent_completed', 'subagent_id': 'child'},
        {'type': 'subagent_completed', 'subagent_id': 'parent'},
      ]);

      expect(transcript.entries, hasLength(1));
      final parent = transcript.entries.single;
      expect(parent.kind, ShareEntryKind.subagentGroup);
      expect(parent.subagentId, 'parent');
      expect(parent.children, hasLength(2));
      expect(parent.children[0].kind, ShareEntryKind.subagentMessage);
      expect(parent.children[0].text, 'parent says hi');
      expect(parent.children[1].kind, ShareEntryKind.subagentGroup);
      expect(parent.children[1].subagentId, 'child');
      expect(parent.children[1].children.single.text, 'child works');
    });

    test('skips orphaned subagent events without a matching open group', () {
      final builder = ShareTranscriptBuilder();

      final transcript = builder.build([
        {
          'type': 'subagent_event',
          'subagent_id': 'never-spawned',
          'inner': {'type': 'assistant_message', 'text': 'orphan'},
        },
        {'type': 'user_message', 'text': 'hello'},
      ]);

      expect(transcript.entries, hasLength(1));
      expect(transcript.entries.single.kind, ShareEntryKind.user);
    });

    test('normalizer carries parent_subagent_id through subagent_spawned', () {
      final spawned = normalizeSessionEvent({
        'type': 'subagent_spawned',
        'subagent_id': 'child',
        'parent_subagent_id': 'parent',
        'task': 'do thing',
        'depth': 1,
      });

      expect(spawned, isNotNull);
      expect(spawned!.kind, NormalizedSessionEventKind.subagentSpawned);
      expect(spawned.subagentId, 'child');
      expect(spawned.parentSubagentId, 'parent');

      // Missing/empty parent_subagent_id stays null (top-level spawn case).
      final topLevel = normalizeSessionEvent({
        'type': 'subagent_spawned',
        'subagent_id': 'top',
        'task': 'top task',
        'depth': 0,
      });
      expect(topLevel!.parentSubagentId, isNull);
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
