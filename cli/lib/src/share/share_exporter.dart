import 'dart:io';

import 'package:glue/src/share/renderer/html_renderer.dart';
import 'package:glue/src/share/renderer/markdown_renderer.dart';
import 'package:glue/src/share/share_transcript_builder.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:path/path.dart' as p;

class ShareExportResult {
  final String? markdownPath;
  final String? htmlPath;

  const ShareExportResult({
    this.markdownPath,
    this.htmlPath,
  });
}

enum ShareFormat { html, markdown }

class ShareExporter {
  final ShareTranscriptBuilder _builder;
  final ShareMarkdownRenderer _markdownRenderer;
  final ShareHtmlRenderer _htmlRenderer;

  ShareExporter({
    ShareTranscriptBuilder? builder,
    ShareMarkdownRenderer? markdownRenderer,
    ShareHtmlRenderer? htmlRenderer,
  })  : _builder = builder ?? ShareTranscriptBuilder(),
        _markdownRenderer = markdownRenderer ?? ShareMarkdownRenderer(),
        _htmlRenderer = htmlRenderer ?? ShareHtmlRenderer();

  Future<ShareExportResult> export({
    required SessionStore store,
    required String outputDir,
    ShareFormat format = ShareFormat.html,
    DateTime? exportedAt,
  }) async {
    final events = SessionStore.loadConversation(store.sessionDir);
    final transcript = _builder.build(events);
    if (transcript.entries.isEmpty) {
      throw StateError('Current session has no conversation data.');
    }

    final when = exportedAt ?? DateTime.now().toUtc();
    final baseName = 'glue-session-${store.meta.id}';
    final markdownPath = p.join(outputDir, '$baseName.md');
    final htmlPath = p.join(outputDir, '$baseName.html');

    String? writtenMarkdownPath;
    String? writtenHtmlPath;

    if (format == ShareFormat.markdown) {
      final markdown = _markdownRenderer.render(
        meta: store.meta,
        transcript: transcript,
        exportedAt: when,
      );
      await File(markdownPath).writeAsString(markdown);
      writtenMarkdownPath = markdownPath;
    }

    if (format == ShareFormat.html) {
      final html = _htmlRenderer.render(
        meta: store.meta,
        transcript: transcript,
        exportedAt: when,
      );
      await File(htmlPath).writeAsString(html);
      writtenHtmlPath = htmlPath;
    }

    return ShareExportResult(
      markdownPath: writtenMarkdownPath,
      htmlPath: writtenHtmlPath,
    );
  }
}
