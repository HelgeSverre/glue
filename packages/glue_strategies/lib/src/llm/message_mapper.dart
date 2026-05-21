import 'dart:convert';

import 'package:glue_core/glue_core.dart';

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

    // Track tool_use IDs from the most recent assistant message so we can
    // drop orphaned tool_result blocks that would trigger a 400 from the API.
    var lastToolUseIds = <ToolCallId>{};

    for (final msg in messages) {
      switch (msg.role) {
        case Role.user:
          lastToolUseIds = <ToolCallId>{};
          final parts = msg.contentParts;
          if (parts != null && parts.isNotEmpty) {
            // Multimodal user input — text + images + resource links.
            mapped.add({
              'role': 'user',
              'content': [
                if (msg.text != null && msg.text!.isNotEmpty)
                  {'type': 'text', 'text': msg.text},
                for (final part in parts)
                  if (part is TextPart)
                    {'type': 'text', 'text': part.text}
                  else if (part is ImagePart)
                    {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': part.mimeType,
                        'data': part.toBase64(),
                      },
                    }
                  else if (part is ResourceLinkPart)
                    {'type': 'text', 'text': part.toMarkdownLink()},
              ],
            });
          } else {
            mapped.add({
              'role': 'user',
              'content': [
                {'type': 'text', 'text': msg.text ?? ''},
              ],
            });
          }
        case Role.assistant:
          lastToolUseIds = {for (final tc in msg.toolCalls) tc.id};
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
          // Skip tool_result whose tool_use_id has no matching tool_use in the
          // preceding assistant message – this prevents Anthropic API 400s
          // caused by orphaned results after session resume/fork.
          final toolCallIdStr = msg.toolCallId;
          if (toolCallIdStr != null &&
              !lastToolUseIds.contains(ToolCallId(toolCallIdStr))) {
            continue;
          }
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
                    },
                  }
                else if (part is ResourceLinkPart)
                  {'type': 'text', 'text': part.toMarkdownLink()},
            ];
          } else if (msg.contentParts != null &&
              ContentPart.hasResourceLinks(msg.contentParts!)) {
            // Pure text + links — render the links inline.
            toolContent = ContentPart.textWithLinks(msg.contentParts!);
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
              },
            ],
          });
      }
    }

    return MappedMessages(systemPrompt: systemPrompt, messages: mapped);
  }
}

/// Gemini Developer API (`v1beta/models/{model}:streamGenerateContent`) format.
///
/// - System prompt is kept separate; the request builder lifts it into the
///   top-level `systemInstruction.parts[].text` field.
/// - Roles are `user` and `model` (no `assistant`, no `system`, no `tool`).
/// - Tool calls are `{functionCall: {name, args}}` parts on `model` messages.
/// - Tool results are `{functionResponse: {name, response: {content}}}` parts
///   on `user` messages.
/// - Image parts become `{inlineData: {mimeType, data}}`.
/// - Orphaned tool results (no matching prior `functionCall`) are dropped, and
///   consecutive same-role messages are coalesced — Gemini requires alternating
///   user/model turns.
class GeminiMessageMapper extends MessageMapper {
  const GeminiMessageMapper();

  @override
  MappedMessages mapMessages(
    List<Message> messages, {
    required String systemPrompt,
  }) {
    final mapped = <Map<String, dynamic>>[];

    // Track the most recent assistant `functionCall` names so we can drop
    // orphaned tool_result messages after session resume/fork.
    var lastFunctionCallNames = <String>{};

    void appendOrCoalesce(String role, List<Map<String, dynamic>> parts) {
      if (parts.isEmpty) return;
      if (mapped.isNotEmpty && mapped.last['role'] == role) {
        (mapped.last['parts'] as List).addAll(parts);
      } else {
        mapped.add({'role': role, 'parts': parts});
      }
    }

    for (final msg in messages) {
      switch (msg.role) {
        case Role.user:
          lastFunctionCallNames = {};
          appendOrCoalesce('user', [
            {'text': msg.text ?? ''},
          ]);
        case Role.assistant:
          lastFunctionCallNames = {for (final tc in msg.toolCalls) tc.name};
          final parts = <Map<String, dynamic>>[];
          if (msg.text != null && msg.text!.isNotEmpty) {
            parts.add({'text': msg.text});
          }
          for (final tc in msg.toolCalls) {
            final fc = <String, dynamic>{'name': tc.name, 'args': tc.arguments};
            final part = <String, dynamic>{'functionCall': fc};
            // Echo back the opaque thoughtSignature captured from the
            // previous response. Required for thinking-mode Gemini models —
            // see https://ai.google.dev/gemini-api/docs/thought-signatures.
            if (tc.thoughtSignature != null) {
              part['thoughtSignature'] = tc.thoughtSignature;
            }
            parts.add(part);
          }
          appendOrCoalesce('model', parts);
        case Role.toolResult:
          // Gemini matches tool results to calls by *name*, not id, so drop
          // results whose name doesn't match a recent assistant call.
          final name = msg.toolName ?? '';
          if (name.isEmpty || !lastFunctionCallNames.contains(name)) {
            continue;
          }
          final parts = <Map<String, dynamic>>[];

          final imageParts = msg.contentParts == null
              ? const <ImagePart>[]
              : msg.contentParts!.whereType<ImagePart>().toList();
          final hasImages = imageParts.isNotEmpty;
          final textContent = (msg.contentParts != null)
              ? ContentPart.textOnly(msg.contentParts!)
              : (msg.text ?? '');

          parts.add({
            'functionResponse': {
              'name': name,
              'response': {
                'content': textContent.isNotEmpty
                    ? textContent
                    : (msg.text ?? ''),
              },
            },
          });

          if (hasImages) {
            for (final img in imageParts) {
              parts.add({
                'inlineData': {
                  'mimeType': img.mimeType,
                  'data': img.toBase64(),
                },
              });
            }
          }

          appendOrCoalesce('user', parts);
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
          final parts = msg.contentParts;
          if (parts != null && parts.isNotEmpty) {
            mapped.add({
              'role': 'user',
              'content': [
                if (msg.text != null && msg.text!.isNotEmpty)
                  {'type': 'text', 'text': msg.text},
                for (final part in parts)
                  if (part is TextPart)
                    {'type': 'text', 'text': part.text}
                  else if (part is ImagePart)
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url':
                            'data:${part.mimeType};base64,${part.toBase64()}',
                      },
                    }
                  else if (part is ResourceLinkPart)
                    {'type': 'text', 'text': part.toMarkdownLink()},
              ],
            });
          } else {
            mapped.add({'role': 'user', 'content': msg.text ?? ''});
          }
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
                },
            ];
          }
          mapped.add(entry);
        case Role.toolResult:
          // textWithLinks renders ResourceLinkParts as `[name](uri)`
          // alongside any text parts; image parts are streamed in a
          // separate user-role message below.
          final textContent = (msg.contentParts != null)
              ? ContentPart.textWithLinks(msg.contentParts!)
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
