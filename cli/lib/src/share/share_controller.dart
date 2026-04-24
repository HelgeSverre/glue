import 'dart:async';
import 'package:glue/src/runtime/transcript.dart';

import 'package:glue/src/core/url_launcher.dart';
import 'package:glue/src/share/gist_publisher.dart';
import 'package:glue/src/share/share_exporter.dart';
import 'package:glue/src/storage/session_store.dart';

/// Handles `/share` — owns its own [ShareExporter] and [GistPublisher] by
/// default; tests can inject fakes. Sits in `share/` so the whole export
/// pipeline (controller, exporter, renderer, gist publisher, html assets)
/// is one directory.
class ShareController {
  ShareController({
    required this.canShare,
    required this.currentStore,
    required this.cwd,
    required this.transcript,
    required this.render,
    ShareExporter? exporter,
    GistPublisher? gistPublisher,
  })  : _exporter = exporter ?? ShareExporter(),
        _gistPublisher = gistPublisher ?? GistPublisher();

  final bool Function() canShare;
  final SessionStore? Function() currentStore;
  final String cwd;
  final Transcript transcript;
  final void Function() render;
  final ShareExporter _exporter;
  final GistPublisher _gistPublisher;

  String shareAction(List<String> args) {
    if (!canShare()) {
      return 'Wait for the current turn to finish before sharing.';
    }

    final store = currentStore();
    if (store == null) {
      return 'No active session yet — nothing to share.';
    }

    final normalized = args
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    if (normalized.length > 1) return 'Usage: /share [html|md|gist]';
    final format = normalized.isEmpty ? 'html' : normalized.first;
    if (!{'html', 'md', 'markdown', 'gist'}.contains(format)) {
      return 'Usage: /share [html|md|gist]';
    }

    final publishGist = format == 'gist';
    final shareFormat = switch (format) {
      'html' => ShareFormat.html,
      'gist' => ShareFormat.markdown,
      'md' || 'markdown' => ShareFormat.markdown,
      _ => ShareFormat.html,
    };
    unawaited(() async {
      try {
        final result = await _exporter.export(
          store: store,
          outputDir: cwd,
          format: shareFormat,
        );
        if (publishGist) {
          final markdownPath = result.markdownPath!;
          try {
            final gist = await _gistPublisher.publish(
              filePath: markdownPath,
              description: _gistDescription(store.meta),
            );
            final opened = await openInBrowser(gist.url);
            transcript.system(
              'Exported markdown transcript to $markdownPath\n'
              'Published gist: ${gist.url}'
              '${opened ? '\nOpened gist in browser.' : '\nCould not open gist in browser automatically.'}',
            );
          } on GistPublishError catch (e) {
            transcript.system(
              'Exported markdown transcript to $markdownPath\n'
              'Gist publish failed: ${e.message}',
            );
          }
          render();
          return;
        }
        final openedHtml = result.htmlPath != null
            ? await openLocalFileInBrowser(result.htmlPath!)
            : null;
        final message = switch (format) {
          'html' => 'Exported HTML transcript to ${result.htmlPath!}',
          'md' ||
          'markdown' =>
            'Exported markdown transcript to ${result.markdownPath!}',
          _ => 'Exported HTML transcript to ${result.htmlPath!}',
        };
        final openNote = openedHtml == null
            ? ''
            : openedHtml
                ? '\nOpened HTML transcript in browser.'
                : '\nCould not open HTML transcript automatically.';
        transcript.system('$message$openNote');
        render();
      } on StateError catch (e) {
        transcript.system(e.message.toString());
        render();
      } catch (e) {
        transcript.system('Share failed: $e');
        render();
      }
    }());

    return '';
  }

  String _gistDescription(SessionMeta meta) {
    final title = (meta.title ?? '').trim();
    if (title.isNotEmpty) return 'Glue session: $title (${meta.id})';
    return 'Glue session ${meta.id}';
  }
}
