import 'package:glue/src/web/search/models.dart';

abstract class WebSearchProvider {
  String get name;
  bool get isConfigured;

  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
  });
}
