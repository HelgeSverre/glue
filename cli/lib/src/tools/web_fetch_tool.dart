import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/web/web_config.dart';
import 'package:glue/src/web/fetch/web_fetch_client.dart';

class WebFetchTool extends Tool {
  final WebFetchClient _client;

  WebFetchTool(WebFetchConfig config)
      : _client = WebFetchClient(config: config);

  @override
  String get name => 'web_fetch';

  @override
  String get description =>
      'Fetch the content of a web page at the given URL and return it as '
      'clean markdown. Handles static HTML pages. Does not execute JavaScript.';

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
  Future<String> execute(Map<String, dynamic> args) async {
    final url = args['url'];
    if (url is! String || url.isEmpty) return 'Error: no URL provided';

    final maxTokens = args['max_tokens'] as int?;
    final result = await _client.fetch(url, maxTokens: maxTokens);

    if (!result.isSuccess) {
      return 'Error: ${result.error}';
    }

    final buf = StringBuffer();
    if (result.title != null) {
      buf.writeln('# ${result.title}');
      buf.writeln('Source: ${result.url}');
      buf.writeln();
    }
    buf.write(result.markdown);
    return buf.toString();
  }
}
