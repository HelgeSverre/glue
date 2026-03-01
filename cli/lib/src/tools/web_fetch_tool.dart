import 'package:glue/src/agent/content_part.dart';
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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final url = args['url'];
    if (url is! String || url.isEmpty) {
      return [const TextPart('Error: no URL provided')];
    }

    final maxTokens = args['max_tokens'] as int?;
    final result = await _client.fetch(url, maxTokens: maxTokens);

    if (!result.isSuccess) {
      return [TextPart('Error: ${result.error}')];
    }

    final buf = StringBuffer();
    if (result.title != null) {
      buf.writeln('# ${result.title}');
      buf.writeln('Source: ${result.url}');
      buf.writeln();
    }
    buf.write(result.markdown);
    return [TextPart(buf.toString())];
  }
}
