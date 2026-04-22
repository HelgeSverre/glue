import 'package:glue/src/share/html/share_html_assets_loader.dart';
import 'package:glue/src/share/renderer/renderer_support.dart';
import 'package:glue/src/share/share_models.dart';
import 'package:glue/src/storage/session_store.dart';

class ShareHtmlRenderer {
  ShareHtmlRenderer({ShareHtmlAssetsLoader? assetsLoader})
      : _assetsLoader = assetsLoader ?? const ShareHtmlAssetsLoader();

  final ShareHtmlAssetsLoader _assetsLoader;

  String render({
    required SessionMeta meta,
    required ShareTranscript transcript,
    required DateTime exportedAt,
  }) {
    final template = _assetsLoader.loadTemplate();
    final styles = _assetsLoader.loadStylesheet();
    final pageTitle =
        (meta.title ?? '').trim().isNotEmpty ? meta.title! : 'Glue';
    final introText = 'Exported conversation transcript. '
        'Started ${escapeShareHtml(_formatUtcTimestamp(meta.startTime))} '
        '· Exported ${escapeShareHtml(_formatUtcTimestamp(exportedAt))}';
    final transcriptEntries = transcript.entries.map(_entry).join('\n');
    final outlineEntries =
        transcript.entries.map((e) => _outline(e, nested: false)).join('\n');

    return template
        .replaceAll('{{page_title}}', escapeShareHtml(pageTitle))
        .replaceAll('{{styles}}', styles)
        .replaceAll('{{header}}', _header(meta, exportedAt))
        .replaceAll('{{intro_text}}', introText)
        .replaceAll('{{transcript_entries}}', transcriptEntries)
        .replaceAll('{{outline_entries}}', outlineEntries);
  }

  String _header(SessionMeta meta, DateTime exportedAt) =>
      '''<div class="share-header">
      <div class="share-header-inner">
        <div class="share-brand">◆ Glue</div>
        <div class="share-meta">
          <div class="share-meta-item">
            <svg class="share-meta-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
             <path d="M10 3L8 21"></path>
             <path d="M16 3l-2 18"></path>
             <path d="M4 9h16"></path>
             <path d="M3 15h16"></path>
            </svg>
            <span class="share-meta-label">Session</span>
            <code>${escapeShareHtml(meta.id)}</code>
          </div>
          <div class="share-meta-item">
            <svg class="share-meta-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M12 3l7 4v10l-7 4-7-4V7l7-4z"></path>
              <path d="M12 12l7-4"></path>
              <path d="M12 12V21"></path>
              <path d="M12 12L5 8"></path>
            </svg>
            <span class="share-meta-label">Model</span>
            <code>${escapeShareHtml(meta.modelRef)}</code>
          </div>
          <div class="share-meta-item">
            <svg class="share-meta-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M8 2v4"></path>
              <path d="M16 2v4"></path>
              <path d="M3 10h18"></path>
              <rect x="3" y="4" width="18" height="18" rx="2"></rect>
            </svg>
            <span class="share-meta-label">Exported</span>
            <time datetime="${escapeShareHtml(exportedAt.toUtc().toIso8601String())}">${escapeShareHtml(_formatUtcTimestamp(exportedAt))}</time>
          </div>
          <div class="share-meta-item">
            <svg class="share-meta-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M3 7h5l2 2h11v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"></path>
            </svg>
            <span class="share-meta-label">Directory</span>
            <code>${escapeShareHtml(meta.cwd)}</code>
          </div>
        </div>
      </div>
    </div>''';

  String _entry(ShareEntry entry) =>
      '''<section class="share-entry ${_entryClass(entry.kind)}" id="entry-${entry.index}">
  <a class="share-entry-anchor" href="#entry-${entry.index}">#${entry.index}</a>
  <div class="share-entry-content">
    <div class="share-entry-label">${_entryHead(entry)}</div>
    ${_entryBody(entry)}
  </div>
</section>''';

  String _entryClass(ShareEntryKind kind) => switch (kind) {
        ShareEntryKind.user => 'share-entry-user',
        ShareEntryKind.assistant => 'share-entry-assistant',
        ShareEntryKind.toolCall => 'share-entry-tool-call',
        ShareEntryKind.toolResult => 'share-entry-tool-result',
        ShareEntryKind.subagentGroup => 'share-entry-subagent-group',
        ShareEntryKind.subagentMessage => 'share-entry-subagent-message',
      };

  String _entryHead(ShareEntry entry) => switch (entry.kind) {
        ShareEntryKind.user => '❯ You',
        ShareEntryKind.assistant => '◆ Glue',
        ShareEntryKind.toolCall =>
          '▶ Tool: ${escapeShareHtml(shareToolDisplayName(entry))}',
        ShareEntryKind.toolResult => '✓ Tool result',
        ShareEntryKind.subagentGroup =>
          '◈ Subagent: ${escapeShareHtml(entry.text)}',
        ShareEntryKind.subagentMessage => '◈ ${escapeShareHtml(entry.text)}',
      };

  String _entryBody(ShareEntry entry) {
    switch (entry.kind) {
      case ShareEntryKind.user:
      case ShareEntryKind.subagentMessage:
        return '<div class="share-entry-body">${escapeShareHtml(entry.text)}</div>';
      case ShareEntryKind.assistant:
        return '<div class="share-entry-body">${renderAssistantMarkdownHtml(entry.text)}</div>';
      case ShareEntryKind.toolCall:
        return '<pre class="share-pre share-tool-args">${escapeShareHtml(prettyShareJson(entry.toolArguments ?? const <String, dynamic>{}))}</pre>';
      case ShareEntryKind.toolResult:
        return '<pre class="share-pre share-tool-result">${escapeShareHtml(entry.text)}</pre>';
      case ShareEntryKind.subagentGroup:
        final children = entry.children.map(_entry).join();
        return '<div class="share-entry-body">${escapeShareHtml(entry.text)}</div><div class="share-children">$children</div>';
    }
  }

  String _outline(ShareEntry entry, {required bool nested}) {
    final css = nested ? ' class="is-nested"' : '';
    final out = StringBuffer(
      '<a$css href="#entry-${entry.index}">#${entry.index} ${escapeShareHtml(shareOutlineLabel(entry.kind))}</a>',
    );
    for (final child in entry.children) {
      out.write(_outline(child, nested: true));
    }
    return out.toString();
  }

  String _formatUtcTimestamp(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute UTC';
  }
}
