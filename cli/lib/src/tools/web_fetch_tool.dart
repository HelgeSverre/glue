import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/web/web_config.dart';
import 'package:glue/src/web/fetch/web_fetch_client.dart';

class WebFetchTool extends Tool {
  final WebFetchClient _client;

  WebFetchTool(WebFetchConfig config, {PdfConfig? pdfConfig})
      : _client = WebFetchClient(config: config, pdfConfig: pdfConfig);

  @override
  String get name => 'web_fetch';

  @override
  String get description =>
      'Fetch the content of a web page or PDF at the given URL and return it '
      'as clean markdown. Handles static HTML pages and PDF documents. '
      'Does not execute JavaScript — use web_browser for dynamic pages.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'url',
          type: 'string',
          description: 'The URL to fetch (must be http or https).',
        ),
        ToolParameter(
          name: 'max_tokens',
          type: 'integer',
          description: 'Maximum approximate token budget for the response.',
          required: false,
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final url = args['url'];
    if (url is! String || url.isEmpty) {
      return ToolResult(
        success: false,
        content: 'Error: no URL provided',
      );
    }

    final maxTokens = args['max_tokens'] as int?;
    final result = await _client.fetch(url, maxTokens: maxTokens);

    if (!result.isSuccess) {
      return ToolResult(
        success: false,
        content: 'Error: ${result.error}',
        summary: 'Failed to fetch $url',
        metadata: {'url': url, 'error': result.error},
      );
    }

    final buf = StringBuffer();
    if (result.title != null) {
      buf.writeln('# ${result.title}');
      buf.writeln('Source: ${result.url}');
      buf.writeln();
    }
    buf.write(result.markdown);
    final body = buf.toString();
    final markdown = result.markdown ?? '';
    return ToolResult(
      content: body,
      summary: 'Fetched $url (${markdown.length} chars)',
      metadata: {
        'url': url,
        'title': result.title,
        'bytes': body.length,
      },
    );
  }
}
