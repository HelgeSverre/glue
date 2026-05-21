/// ACP content block types — the polymorphic shape that carries
/// text, images, audio, file references, and (for tool results) diffs
/// or terminal handles.
///
/// Used by:
///   - `agent_message_chunk.content`   — assistant text/thinking
///   - `tool_call_update.content[]`    — tool execution output
///   - `session/prompt.prompt[]`       — client→agent input blocks
///
/// See https://agentclientprotocol.com/ § ContentBlock.
library;

import 'dart:convert';

import 'package:glue_core/glue_core.dart';

/// A single content block — sealed for exhaustive switch handling.
sealed class AcpContentBlock {
  const AcpContentBlock();

  Map<String, Object?> toJson();

  /// Parse an inbound content block from the wire shape. Returns
  /// [AcpUnknownBlock] for shapes we don't yet recognise so unknown
  /// types round-trip without losing data.
  factory AcpContentBlock.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    switch (type) {
      case 'text':
        return AcpTextBlock(json['text'] as String? ?? '');
      case 'image':
        return AcpImageBlock(
          mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
          data: json['data'] as String? ?? '',
          uri: json['uri'] as String?,
        );
      case 'audio':
        return AcpAudioBlock(
          mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
          data: json['data'] as String? ?? '',
        );
      case 'resource_link':
        return AcpResourceLinkBlock(
          uri: json['uri'] as String? ?? '',
          name: json['name'] as String?,
          description: json['description'] as String?,
          mimeType: json['mimeType'] as String?,
        );
      default:
        return AcpUnknownBlock(json);
    }
  }

  /// Convert a glue_core [ContentPart] to an ACP block.
  static AcpContentBlock fromContentPart(ContentPart part) {
    return switch (part) {
      TextPart(:final text) => AcpTextBlock(text),
      ImagePart() => AcpImageBlock(
        mimeType: part.mimeType,
        data: part.toBase64(),
      ),
      ResourceLinkPart() => AcpResourceLinkBlock(
        uri: part.uri,
        name: part.name,
        description: part.description,
        mimeType: part.mimeType,
      ),
    };
  }
}

class AcpTextBlock extends AcpContentBlock {
  const AcpTextBlock(this.text);
  final String text;

  @override
  Map<String, Object?> toJson() => {'type': 'text', 'text': text};
}

class AcpImageBlock extends AcpContentBlock {
  const AcpImageBlock({required this.mimeType, required this.data, this.uri});

  /// e.g. `image/png`, `image/jpeg`.
  final String mimeType;

  /// Base64-encoded image bytes.
  final String data;

  /// Optional source URL (e.g. the screenshot's page URL).
  final String? uri;

  /// Decoded image bytes. May be expensive; use sparingly.
  List<int> decodedBytes() => base64Decode(data);

  @override
  Map<String, Object?> toJson() => {
    'type': 'image',
    'mimeType': mimeType,
    'data': data,
    if (uri != null) 'uri': uri,
  };
}

class AcpAudioBlock extends AcpContentBlock {
  const AcpAudioBlock({required this.mimeType, required this.data});
  final String mimeType;
  final String data;

  @override
  Map<String, Object?> toJson() => {
    'type': 'audio',
    'mimeType': mimeType,
    'data': data,
  };
}

class AcpResourceLinkBlock extends AcpContentBlock {
  const AcpResourceLinkBlock({
    required this.uri,
    this.name,
    this.description,
    this.mimeType,
  });

  final String uri;
  final String? name;
  final String? description;
  final String? mimeType;

  @override
  Map<String, Object?> toJson() => {
    'type': 'resource_link',
    'uri': uri,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (mimeType != null) 'mimeType': mimeType,
  };
}

/// Fallback for blocks we don't know about. Preserves the original
/// wire shape so it can be passed through verbatim.
class AcpUnknownBlock extends AcpContentBlock {
  const AcpUnknownBlock(this.raw);
  final Map<String, Object?> raw;

  @override
  Map<String, Object?> toJson() => raw;
}

// ---------------------------------------------------------------------------
// Tool-call result content — wraps a [AcpContentBlock] or a diff/terminal
// reference. Used in `tool_call_update.content[]`.
// ---------------------------------------------------------------------------

sealed class AcpToolCallContent {
  const AcpToolCallContent();
  Map<String, Object?> toJson();
}

/// `{type: 'content', content: ContentBlock}` — the common case for
/// text/image tool output.
class AcpToolCallContentValue extends AcpToolCallContent {
  const AcpToolCallContentValue(this.block);
  final AcpContentBlock block;

  @override
  Map<String, Object?> toJson() => {
    'type': 'content',
    'content': block.toJson(),
  };
}

/// `{type: 'diff', path, oldText, newText}` — for write_file / edit_file.
class AcpToolCallDiff extends AcpToolCallContent {
  const AcpToolCallDiff({
    required this.path,
    required this.oldText,
    required this.newText,
  });

  final String path;
  final String oldText;
  final String newText;

  @override
  Map<String, Object?> toJson() => {
    'type': 'diff',
    'path': path,
    'oldText': oldText,
    'newText': newText,
  };
}

/// `{type: 'terminal', terminalId}` — references a live terminal handle
/// the client opened via the `terminal/*` capability set.
class AcpToolCallTerminal extends AcpToolCallContent {
  const AcpToolCallTerminal(this.terminalId);
  final String terminalId;

  @override
  Map<String, Object?> toJson() => {
    'type': 'terminal',
    'terminalId': terminalId,
  };
}
