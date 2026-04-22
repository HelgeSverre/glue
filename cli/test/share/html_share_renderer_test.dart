import 'package:glue/src/share/renderer/html_renderer.dart';
import 'package:glue/src/share/share_models.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('ShareHtmlRenderer', () {
    final meta = SessionMeta(
      id: 'session-1',
      cwd: '/tmp/project',
      modelRef: 'anthropic/claude-sonnet-4.6',
      startTime: DateTime.parse('2026-04-22T04:00:00Z'),
      title: 'Glue',
    );

    test('renders a complete self-contained HTML document', () {
      final renderer = ShareHtmlRenderer();

      final output = renderer.render(
        meta: meta,
        transcript: const ShareTranscript(entries: []),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, contains('<!DOCTYPE html>'));
      expect(output, contains('<title>Glue</title>'));
      expect(output, contains('<div class="share-header">'));
      expect(output, contains('Session'));
      expect(output, contains('anthropic/claude-sonnet-4.6'));
      expect(output, contains('Exported'));
      expect(output, contains('2026-04-22 04:20 UTC'));
    });

    test('renders assistant markdown to html', () {
      final renderer = ShareHtmlRenderer();

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

      expect(output, contains('id="entry-1"'));
      expect(output, contains('◆ Glue'));
      expect(output, contains('<strong>bold</strong>'));
      expect(output, contains('<code>code</code>'));
    });

    test('escapes raw html before rendering assistant markdown', () {
      final renderer = ShareHtmlRenderer();

      final output = renderer.render(
        meta: meta,
        transcript: const ShareTranscript(entries: [
          ShareEntry(
            index: 1,
            kind: ShareEntryKind.assistant,
            text: 'Before <script>alert(1)</script> **after**',
          ),
        ]),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, isNot(contains('<script>alert(1)</script>')));
      expect(output, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
      expect(output, contains('<strong>after</strong>'));
    });

    test('renders tool call and result blocks', () {
      final renderer = ShareHtmlRenderer();

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
          ShareEntry(
            index: 3,
            kind: ShareEntryKind.toolResult,
            text: 'contents',
          ),
        ]),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, contains('▶ Tool: read_file'));
      expect(output, contains('class="share-pre share-tool-args"'));
      expect(output, contains('"path": "README.md"'));
      expect(output, contains('✓ Tool result'));
      expect(output, contains('class="share-pre share-tool-result"'));
    });

    test('escapes literal html in tool results without stripping it', () {
      final renderer = ShareHtmlRenderer();

      final output = renderer.render(
        meta: meta,
        transcript: const ShareTranscript(entries: [
          ShareEntry(
            index: 3,
            kind: ShareEntryKind.toolResult,
            text: '<div>contents</div>',
          ),
        ]),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, contains('&lt;div&gt;contents&lt;/div&gt;'));
      expect(
        output,
        isNot(
          contains(
            '<pre class="share-pre share-tool-result"><div>contents</div></pre>',
          ),
        ),
      );
    });

    test('renders nested subagent entries', () {
      final renderer = ShareHtmlRenderer();

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

      expect(output, contains('◈ Subagent: docs-research'));
      expect(output, contains('class="share-children"'));
      expect(output, contains('checking template packages'));
      expect(output, contains('◈ Subagent: html-safety-review'));
      expect(output, contains('review raw HTML policy'));
      expect(output, contains('#8 Subagent message'));
    });
  });
}
