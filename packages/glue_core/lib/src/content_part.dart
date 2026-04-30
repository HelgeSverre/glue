/// Multimodal content parts that can appear inside a [Message] or a
/// [ToolResult.contentParts].
///
/// Three concrete subtypes today:
///   - [TextPart] — plain text
///   - [ImagePart] — bytes + mime type, used for vision-capable LLMs
///     and surfaced over ACP as `image` content blocks
///   - [ResourceLinkPart] — opaque reference to a resource (URI +
///     metadata). Falls back to a textual rendering for LLMs that
///     don't natively support it; surfaced over ACP as `resource_link`
///     content blocks for editor/web UIs that can render them as
///     clickable links.
library;

import 'dart:convert';

sealed class ContentPart {
  const ContentPart();

  /// Concatenates the text of every [TextPart] in [parts]. Image and
  /// resource-link parts are skipped — for those, render them
  /// according to their type.
  static String textOnly(List<ContentPart> parts) {
    return parts.whereType<TextPart>().map((p) => p.text).join();
  }

  /// True if any part is an [ImagePart].
  static bool hasImages(List<ContentPart> parts) {
    return parts.any((p) => p is ImagePart);
  }

  /// True if any part is a [ResourceLinkPart].
  static bool hasResourceLinks(List<ContentPart> parts) {
    return parts.any((p) => p is ResourceLinkPart);
  }

  /// Concatenates [parts] as text, rendering each variant in a way the
  /// LLM can read: text passes through; resource_link renders as a
  /// `[name](uri)` markdown link; image parts are skipped (they need
  /// to flow through a separate image-content channel).
  static String textWithLinks(List<ContentPart> parts) {
    final buf = StringBuffer();
    for (final part in parts) {
      switch (part) {
        case TextPart(:final text):
          buf.write(text);
        case ResourceLinkPart():
          if (buf.isNotEmpty) buf.write('\n');
          buf.write(part.toMarkdownLink());
        case ImagePart():
          // Images flow through provider-specific image channels.
          break;
      }
    }
    return buf.toString();
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

/// Reference to an external resource that the agent (or its tools) is
/// pointing the user at — e.g. a URL fetched, a file written, a
/// repository link.
///
/// LLM message mappers render this as a textual "[name](uri)" snippet
/// so the model sees something useful. ACP message mappers emit a
/// dedicated `resource_link` content block so editors / web UIs can
/// render it as an inline link with metadata.
class ResourceLinkPart extends ContentPart {
  const ResourceLinkPart({
    required this.uri,
    this.name,
    this.description,
    this.mimeType,
  });

  /// Where the resource lives. Typically `http(s)://…` or `file://…`.
  final String uri;

  /// Display name for the link (e.g. the page title, the basename).
  /// Falls back to [uri] in textual rendering when null.
  final String? name;

  /// Optional human-readable hover/preview text.
  final String? description;

  /// Optional content type hint — `text/html`, `application/pdf`, …
  final String? mimeType;

  /// Markdown-style rendering for LLM payloads that have no
  /// `resource_link` concept.
  String toMarkdownLink() => '[${name ?? uri}]($uri)';
}
