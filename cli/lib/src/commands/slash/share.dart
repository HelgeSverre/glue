import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/arg_completers.dart' as arg_completers;
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/share` — export the current session as html, markdown, or a public gist.
class ShareCommand extends SlashCommand {
  ShareCommand(this.ctx);

  final SlashCommandContext ctx;
  final SessionShareExporter _exporter = SessionShareExporter();
  final SessionGistPublisher _gistPublisher = SessionGistPublisher();

  @override
  String get name => 'share';

  @override
  String get description =>
      'Export the current session as html, markdown, or gist';

  @override
  SlashArgCompleter? get argCompleter => arg_completers.shareArgCandidates;

  @override
  String execute(List<String> args) {
    if (!ctx.isIdle) {
      return 'Wait for the current turn to finish before sharing.';
    }
    final store = ctx.session.currentStore;
    if (store == null) return 'No active session yet — nothing to share.';

    final normalized = args
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    if (normalized.length > 1) return 'Usage: /share [html|md|gist]';
    final format = normalized.isEmpty ? 'html' : normalized.first;
    if (!{'html', 'md', 'markdown', 'gist'}.contains(format)) {
      return 'Usage: /share [html|md|gist]';
    }

    final outputDir = ctx.cwd;
    final publishGist = format == 'gist';
    final shareFormat = switch (format) {
      'html' => ShareFormat.html,
      'gist' => ShareFormat.markdown,
      'md' || 'markdown' => ShareFormat.markdown,
      _ => ShareFormat.html,
    };

    () async {
      try {
        final result = await _exporter.export(
          store: store,
          outputDir: outputDir,
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
            ctx.conversation.notify(
              'Exported markdown transcript to $markdownPath\n'
              'Published gist: ${gist.url}'
              '${opened ? '\nOpened gist in browser.' : '\nCould not open gist in browser automatically.'}',
            );
          } on GistPublishError catch (e) {
            ctx.conversation.notify(
              'Exported markdown transcript to $markdownPath\n'
              'Gist publish failed: ${e.message}',
            );
          }
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
        ctx.conversation.notify('$message$openNote');
      } on StateError catch (e) {
        ctx.conversation.notify(e.message.toString());
      } catch (e) {
        ctx.conversation.notify('Share failed: $e');
      }
    }();

    return '';
  }

  String _gistDescription(SessionMeta meta) {
    final title = (meta.title ?? '').trim();
    if (title.isNotEmpty) return 'Glue session: $title (${meta.id})';
    return 'Glue session ${meta.id}';
  }
}
