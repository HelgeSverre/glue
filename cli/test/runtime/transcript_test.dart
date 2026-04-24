import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/subagents.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:test/test.dart';

void main() {
  group('Transcript.blocks ordering', () {
    test('entries append in submission order', () {
      final t = Transcript();
      t.blocks.add(ConversationEntry.user('hello'));
      t.streamingText = 'hi there';
      t.blocks.add(ConversationEntry.assistant('hi there'));
      t.blocks.add(ConversationEntry.toolCall('read_file', {'path': 'a.txt'}));
      t.blocks.add(ConversationEntry.toolResult('file contents'));
      t.blocks.add(ConversationEntry.error('oops'));

      expect(
        t.blocks.map((e) => e.kind).toList(),
        [
          EntryKind.user,
          EntryKind.assistant,
          EntryKind.toolCall,
          EntryKind.toolResult,
          EntryKind.error,
        ],
      );
    });

    test('user entry preserves displayText and expandedText', () {
      final entry = ConversationEntry.user('short', expandedText: 'LONG');
      expect(entry.text, 'short');
      expect(entry.expandedText, 'LONG');
      expect(entry.kind, EntryKind.user);
    });

    test('toolCall entry carries arguments map', () {
      final entry = ConversationEntry.toolCall('write_file', {'path': 'a.txt'});
      expect(entry.kind, EntryKind.toolCall);
      expect(entry.args, {'path': 'a.txt'});
    });
  });

  group('Transcript.system', () {
    test('appends an EntryKind.system entry at the end', () {
      final t = Transcript();
      t.blocks.add(ConversationEntry.user('q'));
      t.system('notice');
      expect(t.blocks.last.kind, EntryKind.system);
      expect(t.blocks.last.text, 'notice');
    });

    test('subsequent system entries each become their own block', () {
      final t = Transcript();
      t.system('a');
      t.system('b');
      expect(t.blocks.map((e) => e.text).toList(), ['a', 'b']);
    });
  });

  group('Transcript.clear', () {
    test(
        'resets blocks, toolUi, streamingText, subagentGroups, '
        'outputLineGroups, scrollOffset', () {
      final t = Transcript();
      t.blocks.add(ConversationEntry.user('hi'));
      t.toolUi['tc1'] = ToolCallUiState(id: 'tc1', name: 'read_file');
      t.streamingText = 'partial';
      final group = SubagentGroup(task: 'do it');
      t.subagentGroups['do it:0'] = group;
      t.outputLineGroups.add(group);
      t.scrollOffset = 7;

      t.clear();

      expect(t.blocks, isEmpty);
      expect(t.toolUi, isEmpty);
      expect(t.streamingText, isEmpty);
      expect(t.subagentGroups, isEmpty);
      expect(t.outputLineGroups, isEmpty);
      expect(t.scrollOffset, 0);
    });
  });

  group('Transcript.handleSubagentUpdate', () {
    test('creates a new group on first update with same task+index key', () {
      final t = Transcript();
      final call = ToolCall(id: 't1', name: 'read_file', arguments: const {});
      final update = SubagentUpdate(
        task: 'find bugs',
        index: 0,
        total: 2,
        event: AgentToolCall(call),
      );
      final changed = t.handleSubagentUpdate(update);

      expect(changed, isTrue);
      expect(t.subagentGroups, hasLength(1));
      final groupKey = t.subagentGroups.keys.single;
      expect(groupKey, 'find bugs:0');
      final group = t.subagentGroups[groupKey]!;
      expect(group.task, 'find bugs');
      expect(group.index, 0);
      expect(group.total, 2);
      expect(group.entries, hasLength(1));
      expect(group.currentTool, 'read_file');
      expect(t.blocks, hasLength(1));
      expect(t.blocks.single.kind, EntryKind.subagentGroup);
      expect(t.blocks.single.group, same(group));
    });

    test(
        'deduplicates by task:index — second update for same key '
        'appends to existing group', () {
      final t = Transcript();
      final call1 = ToolCall(id: 't1', name: 'read_file', arguments: const {});
      final call2 = ToolCall(id: 't2', name: 'grep', arguments: const {});
      t.handleSubagentUpdate(SubagentUpdate(
        task: 'same',
        index: 0,
        total: 1,
        event: AgentToolCall(call1),
      ));
      t.handleSubagentUpdate(SubagentUpdate(
        task: 'same',
        index: 0,
        total: 1,
        event: AgentToolCall(call2),
      ));

      expect(t.subagentGroups, hasLength(1));
      expect(t.subagentGroups['same:0']!.entries, hasLength(2));
      // Only one block was appended (the group block).
      expect(
          t.blocks
              .whereType<ConversationEntry>()
              .where((e) => e.kind == EntryKind.subagentGroup),
          hasLength(1));
    });

    test('different indices produce distinct groups', () {
      final t = Transcript();
      final call = ToolCall(id: 't1', name: 'read_file', arguments: const {});
      t.handleSubagentUpdate(SubagentUpdate(
        task: 'parallel',
        index: 0,
        total: 2,
        event: AgentToolCall(call),
      ));
      t.handleSubagentUpdate(SubagentUpdate(
        task: 'parallel',
        index: 1,
        total: 2,
        event: AgentToolCall(call),
      ));
      expect(t.subagentGroups.keys.toSet(), {'parallel:0', 'parallel:1'});
    });

    test(
        'returns false for ignored events (AgentToolCallPending, '
        'AgentTextDelta)', () {
      final t = Transcript();
      // First create the group via a real event.
      final call = ToolCall(id: 't1', name: 'read_file', arguments: const {});
      t.handleSubagentUpdate(SubagentUpdate(
        task: 'foo',
        index: 0,
        total: 1,
        event: AgentToolCall(call),
      ));
      expect(t.subagentGroups['foo:0']!.entries, hasLength(1));

      final blockCount = t.blocks.length;
      final pendingChanged = t.handleSubagentUpdate(SubagentUpdate(
        task: 'foo',
        index: 0,
        total: 1,
        event: AgentToolCallPending(id: 'x', name: 'grep'),
      ));
      final deltaChanged = t.handleSubagentUpdate(SubagentUpdate(
        task: 'foo',
        index: 0,
        total: 1,
        event: AgentTextDelta('hi'),
      ));

      expect(pendingChanged, isFalse);
      expect(deltaChanged, isFalse);
      // Group unchanged, no new blocks added.
      expect(t.subagentGroups['foo:0']!.entries, hasLength(1));
      expect(t.blocks, hasLength(blockCount));
    });

    test('AgentDone marks group done and clears currentTool', () {
      final t = Transcript();
      final call = ToolCall(id: 't1', name: 'read_file', arguments: const {});
      t.handleSubagentUpdate(SubagentUpdate(
        task: 'x',
        index: null,
        total: null,
        event: AgentToolCall(call),
      ));
      final group = t.subagentGroups['x:0']!;
      expect(group.done, isFalse);
      expect(group.currentTool, 'read_file');

      final changed = t.handleSubagentUpdate(SubagentUpdate(
        task: 'x',
        index: null,
        total: null,
        event: AgentDone(),
      ));
      expect(changed, isTrue);
      expect(group.done, isTrue);
      expect(group.currentTool, isNull);
    });

    test('AgentError appends a ✗ Error entry', () {
      final t = Transcript();
      t.handleSubagentUpdate(SubagentUpdate(
        task: 'x',
        index: null,
        total: null,
        event: AgentToolCall(
            ToolCall(id: 't1', name: 'read_file', arguments: const {})),
      ));
      final changed = t.handleSubagentUpdate(SubagentUpdate(
        task: 'x',
        index: null,
        total: null,
        event: AgentError(StateError('boom')),
      ));
      expect(changed, isTrue);
      final entries = t.subagentGroups['x:0']!.entries;
      expect(entries.last.display, contains('✗ Error'));
      expect(entries.last.display, contains('boom'));
    });
  });

  group('SubagentEntry.render', () {
    test('collapsed render returns display', () {
      final e = SubagentEntry('line', rawContent: '{"k":1}');
      expect(e.render(expanded: false), 'line');
    });

    test('expanded render indents pretty JSON from rawContent', () {
      final e = SubagentEntry('line', rawContent: '{"k":1}');
      final rendered = e.render(expanded: true);
      expect(rendered, startsWith('line'));
      expect(rendered, contains('"k": 1'));
      // Indented with 10 spaces per the implementation.
      expect(rendered, contains('          '));
    });

    test(
        'expanded render falls back to display when rawContent is '
        'not JSON', () {
      final e = SubagentEntry('line', rawContent: 'just a string');
      expect(e.render(expanded: true), 'line');
    });

    test('expanded render without rawContent returns display', () {
      final e = SubagentEntry('line');
      expect(e.render(expanded: true), 'line');
    });
  });

  group('ToolCallUiState phase transitions', () {
    test('starts in preparing phase', () {
      final state = ToolCallUiState(id: 'tc1', name: 'read_file');
      expect(state.phase, ToolPhase.preparing);
    });

    test('can be mutated through phases', () {
      final state = ToolCallUiState(id: 'tc1', name: 'read_file');
      state.phase = ToolPhase.awaitingApproval;
      expect(state.phase, ToolPhase.awaitingApproval);
      state.phase = ToolPhase.running;
      state.phase = ToolPhase.done;
      expect(state.phase, ToolPhase.done);
    });

    test('toRenderState maps every ToolPhase to a ToolCallPhase', () {
      for (final phase in ToolPhase.values) {
        final state = ToolCallUiState(id: 'x', name: 'y', phase: phase);
        // Should not throw and should return a non-null render state.
        expect(state.toRenderState, returnsNormally);
      }
    });
  });

  group('SubagentGroup.summary', () {
    test('includes step count and currentTool while running', () {
      final g = SubagentGroup(task: 'hunt', index: 0, total: 2);
      g.currentTool = 'grep';
      g.entries.add(SubagentEntry('a'));
      g.entries.add(SubagentEntry('b'));
      final summary = g.summary;
      expect(summary, contains('[1/2]'));
      expect(summary, contains('hunt'));
      expect(summary, contains('2 steps'));
      expect(summary, contains('grep'));
    });

    test('shows done marker once complete', () {
      final g = SubagentGroup(task: 'hunt');
      g.entries.add(SubagentEntry('a'));
      g.done = true;
      expect(g.summary, contains('done ✓'));
    });

    test('truncates long task text', () {
      final long = 'x' * 100;
      final g = SubagentGroup(task: long);
      expect(g.summary, contains('…'));
      expect(g.summary.length, lessThan(long.length + 50));
    });
  });
}
