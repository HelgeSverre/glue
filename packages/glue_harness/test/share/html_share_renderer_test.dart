import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

void main() {
  group('ShareHtmlRenderer', () {
    final meta = SessionMeta(
      id: const SessionId('session-1'),
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

    test('renders short tool results inline without <details>', () {
      final renderer = ShareHtmlRenderer();
      final shortOutput = List.generate(5, (i) => 'line $i').join('\n');

      final output = renderer.render(
        meta: meta,
        transcript: ShareTranscript(entries: [
          ShareEntry(
            index: 1,
            kind: ShareEntryKind.toolResult,
            text: shortOutput,
          ),
        ]),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, contains('share-tool-result'));
      expect(output, isNot(contains('<details')));
      expect(output, contains('line 4'));
    });

    test('wraps long tool results in a collapsible <details> block', () {
      final renderer = ShareHtmlRenderer(collapseToolOutputAfterLines: 10);
      final longOutput = List.generate(40, (i) => 'line $i').join('\n');

      final output = renderer.render(
        meta: meta,
        transcript: ShareTranscript(entries: [
          ShareEntry(
            index: 1,
            kind: ShareEntryKind.toolResult,
            text: longOutput,
          ),
        ]),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, contains('<details class="share-collapsible">'));
      expect(output, contains('<summary>Show output (40 lines)</summary>'));
      expect(output, contains('share-tool-result'));
      // Body still escaped and present inside the collapsible.
      expect(output, contains('line 39'));
    });

    test('collapseToolOutputAfterLines=0 disables the collapse for any length',
        () {
      final renderer = ShareHtmlRenderer(collapseToolOutputAfterLines: 0);
      final longOutput = List.generate(200, (i) => 'line $i').join('\n');

      final output = renderer.render(
        meta: meta,
        transcript: ShareTranscript(entries: [
          ShareEntry(
            index: 1,
            kind: ShareEntryKind.toolResult,
            text: longOutput,
          ),
        ]),
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(output, isNot(contains('<details')));
    });
  });
}
