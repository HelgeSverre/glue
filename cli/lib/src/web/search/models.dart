class WebSearchResult {
  final String title;
  final Uri url;
  final String snippet;
  final DateTime? publishedAt;

  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    this.publishedAt,
  });

  String toText() {
    final buf = StringBuffer();
    buf.writeln('**$title**');
    buf.writeln(url);
    buf.writeln(snippet);
    if (publishedAt != null) {
      buf.writeln(
          'Published: ${publishedAt!.toIso8601String().split('T').first}');
    }
    return buf.toString();
  }
}

class WebSearchResponse {
  final String provider;
  final String query;
  final List<WebSearchResult> results;
  final String? aiSummary;

  const WebSearchResponse({
    required this.provider,
    required this.query,
    required this.results,
    this.aiSummary,
  });

  String toText() {
    if (results.isEmpty) return 'No results found for "$query" (via $provider).';

    final buf = StringBuffer();
    buf.writeln('Search results for "$query" (via $provider):');
    buf.writeln();
    if (aiSummary != null) {
      buf.writeln(aiSummary);
      buf.writeln();
    }
    for (var i = 0; i < results.length; i++) {
      buf.writeln('${i + 1}. ${results[i].toText()}');
    }
    return buf.toString().trim();
  }
}
