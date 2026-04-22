import 'package:glue/src/share/renderer/markdown_renderer.dart';
import 'package:glue/src/share/share_models.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('ShareMarkdownRenderer', () {
    final meta = SessionMeta(
      id: 'session-1',
      cwd: '/tmp/project',
      modelRef: 'anthropic/claude-sonnet-4.6',
      startTime: DateTime.parse('2026-04-22T04:00:00Z'),
      title: 'Glue',
    );

    test('renders session metadata header', () {
      final renderer = ShareMarkdownRenderer();

      final output = renderer.render(
        meta: meta,
        transcript: const ShareTranscript(entries: []),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, contains('# Glue Session'));
      expect(output, contains('> **Session ID:** `session-1`'));
      expect(output, contains('> **Title:** Glue'));
      expect(output, contains('> **Model:** `anthropic/claude-sonnet-4.6`'));
      expect(output, contains('> **Directory:** `/tmp/project`'));
    });

    test('preserves assistant markdown', () {
      final renderer = ShareMarkdownRenderer();

      final output = renderer.render(
        meta: meta,
        transcript: const ShareTranscript(entries: [
          ShareEntry(
            index: 1,
            kind: ShareEntryKind.assistant,
            text: 'Here is **bold** and `code`.',
          ),
        ]),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, contains('## Glue'));
      expect(output, contains('Here is **bold** and `code`.'));
    });

    test('renders tool arguments as fenced json', () {
      final renderer = ShareMarkdownRenderer();

      final output = renderer.render(
        meta: meta,
        transcript: const ShareTranscript(entries: [
          ShareEntry(
            index: 2,
            kind: ShareEntryKind.toolCall,
            text: 'read_file',
            toolName: 'read_file',
            toolArguments: {'path': 'README.md'},
          ),
        ]),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, contains('## Tool: read_file'));
      expect(output, contains('### Arguments'));
      expect(output, contains('```json'));
      expect(output, contains('"path": "README.md"'));
    });

    test('renders nested subagent groups hierarchically', () {
      final renderer = ShareMarkdownRenderer();

      final output = renderer.render(
        meta: meta,
        transcript: const ShareTranscript(entries: [
          ShareEntry(
            index: 5,
            kind: ShareEntryKind.subagentGroup,
            text: 'docs-research',
            children: [
              ShareEntry(
                index: 6,
                kind: ShareEntryKind.subagentMessage,
                text: 'checking template packages',
                nestingLevel: 1,
              ),
              ShareEntry(
                index: 7,
                kind: ShareEntryKind.subagentGroup,
                text: 'html-safety-review',
                nestingLevel: 1,
                children: [
                  ShareEntry(
                    index: 8,
                    kind: ShareEntryKind.subagentMessage,
                    text: 'review raw HTML policy',
                    nestingLevel: 2,
                  ),
                ],
              ),
            ],
          ),
        ]),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, contains('## Subagent: docs-research'));
      expect(output, contains('> checking template packages'));
      expect(output, contains('### Subagent: html-safety-review'));
      expect(output, contains('> review raw HTML policy'));
    });
  });
}
