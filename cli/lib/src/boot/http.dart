import 'package:http/http.dart' as http;

typedef HttpClientFactory = http.Client Function(String spanKind);
