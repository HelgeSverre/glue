/// Multimodal content parts that can appear inside a [Message].
///
/// **Status:** part of the proposed core data model — see
/// `docs/plans/2026-04-29-harness-layers.md`. Originally lived in
/// `agent/content_part.dart`; relocated so strategies (LLM clients,
/// providers) can depend on it without violating the layer rule.
library;

import 'dart:convert';

sealed class ContentPart {
  const ContentPart();

  static String textOnly(List<ContentPart> parts) {
    return parts.whereType<TextPart>().map((p) => p.text).join();
  }

  static bool hasImages(List<ContentPart> parts) {
    return parts.any((p) => p is ImagePart);
  }
}

class TextPart extends ContentPart {
  final String text;
  const TextPart(this.text);
}

class ImagePart extends ContentPart {
  final List<int> bytes;
  final String mimeType;
  const ImagePart({required this.bytes, required this.mimeType});

  String toBase64() => base64Encode(bytes);
}
