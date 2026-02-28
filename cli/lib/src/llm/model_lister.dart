import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/glue_config.dart';

class ModelInfo {
  final String id;
  final String? size;

  ModelInfo({required this.id, this.size});
}

class ModelLister {
  final http.Client _http;

  ModelLister({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  Future<List<ModelInfo>> list({
    required LlmProvider provider,
    String? apiKey,
    String ollamaBaseUrl = 'http://localhost:11434',
  }) async {
    return switch (provider) {
      LlmProvider.ollama => _listOllama(ollamaBaseUrl),
      LlmProvider.openai => _listOpenAi(apiKey ?? ''),
      LlmProvider.anthropic => _listAnthropic(apiKey ?? ''),
    };
  }

  Future<List<ModelInfo>> _listOllama(String baseUrl) async {
    final uri = Uri.parse(baseUrl).resolve('/api/tags');
    final response = await _http.get(uri)
        .timeout(Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Ollama API error ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final models = json['models'] as List? ?? [];
    return models.map((m) {
      final map = m as Map<String, dynamic>;
      final name = map['name'] as String? ?? '';
      final sizeBytes = map['size'] as int?;
      final size = sizeBytes != null ? _formatBytes(sizeBytes) : null;
      return ModelInfo(id: name, size: size);
    }).toList();
  }

  Future<List<ModelInfo>> _listOpenAi(String apiKey) async {
    final uri = Uri.parse('https://api.openai.com/v1/models');
    final response = await _http.get(uri, headers: {
      'Authorization': 'Bearer $apiKey',
    }).timeout(Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('OpenAI API error ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List? ?? [];
    final models = data.map((m) {
      final map = m as Map<String, dynamic>;
      return ModelInfo(id: map['id'] as String? ?? '');
    }).toList();
    models.sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  Future<List<ModelInfo>> _listAnthropic(String apiKey) async {
    final uri = Uri.parse('https://api.anthropic.com/v1/models');
    final response = await _http.get(uri, headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    }).timeout(Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Anthropic API error ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List? ?? [];
    final models = data.map((m) {
      final map = m as Map<String, dynamic>;
      return ModelInfo(id: map['id'] as String? ?? '');
    }).toList();
    models.sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
