import 'dart:convert';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';

/// Result of mapping Glue messages to a provider-specific format.
class MappedMessages {
  /// System prompt (Anthropic: separate field; OpenAI: prepended message).
  final String systemPrompt;

  /// Provider-formatted message list.
  final List<Map<String, dynamic>> messages;

  MappedMessages({required this.systemPrompt, required this.messages});
}

/// Maps Glue [Message] objects to provider-specific JSON payloads.
sealed class MessageMapper {
  const MessageMapper();

  MappedMessages mapMessages(
    List<Message> messages, {
    required String systemPrompt,
  });
}

/// Anthropic Messages API format.
///
/// - System prompt is a separate top-level field.
/// - Tool results are sent as `role: "user"` with `type: "tool_result"` blocks.
/// - Assistant tool calls are `type: "tool_use"` content blocks.
class AnthropicMessageMapper extends MessageMapper {
  const AnthropicMessageMapper();

  @override
  MappedMessages mapMessages(
    List<Message> messages, {
    required String systemPrompt,
  }) {
    final mapped = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case Role.user:
          mapped.add({
            'role': 'user',
            'content': [
              {'type': 'text', 'text': msg.text ?? ''}
            ],
          });
        case Role.assistant:
          final content = <Map<String, dynamic>>[];
          if (msg.text != null && msg.text!.isNotEmpty) {
            content.add({'type': 'text', 'text': msg.text});
          }
          for (final tc in msg.toolCalls) {
            content.add({
              'type': 'tool_use',
              'id': tc.id,
              'name': tc.name,
              'input': tc.arguments,
            });
          }
          mapped.add({'role': 'assistant', 'content': content});
        case Role.toolResult:
          final dynamic toolContent;
          if (msg.contentParts != null &&
              ContentPart.hasImages(msg.contentParts!)) {
            toolContent = [
              for (final part in msg.contentParts!)
                if (part is TextPart)
                  {'type': 'text', 'text': part.text}
                else if (part is ImagePart)
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': part.mimeType,
                      'data': part.toBase64(),
                    }
                  }
            ];
          } else {
            toolContent = msg.text ?? '';
          }
          mapped.add({
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': msg.toolCallId,
                'content': toolContent,
              }
            ],
          });
      }
    }

    return MappedMessages(systemPrompt: systemPrompt, messages: mapped);
  }
}

/// OpenAI Chat Completions format.
///
/// - System prompt is a message with `role: "system"`.
/// - Tool results use `role: "tool"` with `tool_call_id`.
/// - Assistant tool calls are stored in `tool_calls` array.
class OpenAiMessageMapper extends MessageMapper {
  const OpenAiMessageMapper();

  @override
  MappedMessages mapMessages(
    List<Message> messages, {
    required String systemPrompt,
  }) {
    final mapped = <Map<String, dynamic>>[];

    // OpenAI: system prompt is a message.
    if (systemPrompt.isNotEmpty) {
      mapped.add({'role': 'system', 'content': systemPrompt});
    }

    for (final msg in messages) {
      switch (msg.role) {
        case Role.user:
          mapped.add({'role': 'user', 'content': msg.text ?? ''});
        case Role.assistant:
          final entry = <String, dynamic>{
            'role': 'assistant',
            'content': msg.text ?? '',
          };
          if (msg.toolCalls.isNotEmpty) {
            entry['tool_calls'] = [
              for (final tc in msg.toolCalls)
                {
                  'id': tc.id,
                  'type': 'function',
                  'function': {
                    'name': tc.name,
                    'arguments': jsonEncode(tc.arguments),
                  },
                }
            ];
          }
          mapped.add(entry);
        case Role.toolResult:
          final textContent = (msg.contentParts != null)
              ? ContentPart.textOnly(msg.contentParts!)
              : (msg.text ?? '');
          mapped.add({
            'role': 'tool',
            'tool_call_id': msg.toolCallId,
            'content': textContent.isNotEmpty ? textContent : (msg.text ?? ''),
          });
          if (msg.contentParts != null &&
              ContentPart.hasImages(msg.contentParts!)) {
            final imageParts = msg.contentParts!.whereType<ImagePart>();
            mapped.add({
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': '[Screenshot from ${msg.toolName ?? "tool"}]',
                },
                for (final img in imageParts)
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:${img.mimeType};base64,${img.toBase64()}',
                    },
                  },
              ],
            });
          }
      }
    }

    return MappedMessages(systemPrompt: systemPrompt, messages: mapped);
  }
}
