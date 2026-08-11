// GENERATED CODE - DO NOT MODIFY BY HAND.
// Run: dart run tool/gen_session_schemas.dart

const sessionMetaV5SchemaJson = r'''{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://getglue.dev/schemas/session/meta-v5.schema.json",
  "title": "Glue session metadata v5",
  "type": "object",
  "required": [
    "schema_version", "id", "glue_version", "transcript_schema_version",
    "cwd", "model_ref", "start_time", "termination_status"
  ],
  "properties": {
    "schema_version": { "const": 5 },
    "id": { "$ref": "#/$defs/nonEmptyString" },
    "glue_version": { "$ref": "#/$defs/nonEmptyString" },
    "transcript_schema_version": { "const": 1 },
    "cwd": { "type": "string" },
    "project_path": { "type": "string" },
    "model_ref": { "$ref": "#/$defs/modelRef" },
    "reasoning_effort": { "type": "string" },
    "show_thoughts": { "type": "boolean" },
    "start_time": { "$ref": "#/$defs/timestamp" },
    "end_time": { "$ref": "#/$defs/timestamp" },
    "termination_status": {
      "enum": ["running", "completed", "cancelled", "failed", "interrupted"]
    },
    "forked_from": { "type": "string" },
    "worktree_path": { "type": "string" },
    "branch": { "type": "string" },
    "base_branch": { "type": "string" },
    "repo_remote": { "type": "string" },
    "head_sha": { "type": "string" },
    "title": { "type": "string" },
    "title_source": { "enum": ["auto", "user"] },
    "title_state": { "enum": ["provisional", "stable"] },
    "title_generation_count": { "type": "integer", "minimum": 0 },
    "title_generated_at": { "$ref": "#/$defs/timestamp" },
    "title_last_evaluated_at": { "$ref": "#/$defs/timestamp" },
    "title_renamed_at": { "$ref": "#/$defs/timestamp" },
    "tags": { "type": "array", "items": { "type": "string" }, "uniqueItems": true },
    "pr_url": { "type": "string", "format": "uri" },
    "pr_status": { "type": "string" },
    "token_count": { "$ref": "#/$defs/nonNegativeInteger" },
    "cache_read_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
    "cache_creation_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
    "message_count": { "$ref": "#/$defs/nonNegativeInteger" },
    "summary": { "type": "string" },
    "runtime_id": { "type": "string" },
    "sandbox_id": { "type": "string" },
    "runtime_bootstrap_sha": { "type": "string" },
    "runtime_remote_url": { "type": "string" },
    "runtime_patch_path": { "type": "string" },
    "runtime_closed_at": { "$ref": "#/$defs/timestamp" }
  },
  "additionalProperties": false,
  "$defs": {
    "nonEmptyString": { "type": "string", "minLength": 1 },
    "modelRef": { "type": "string", "pattern": "^[^/]+/.+$" },
    "timestamp": { "type": "string", "format": "date-time" },
    "nonNegativeInteger": { "type": "integer", "minimum": 0 }
  }
}
''';
const conversationEventV1SchemaJson = r'''{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://getglue.dev/schemas/session/conversation-event-v1.schema.json",
  "title": "Glue conversation event v1",
  "type": "object",
  "required": ["schema_version", "event_id", "session_id", "timestamp", "type", "sequence"],
  "properties": {
    "schema_version": { "const": 1 },
    "event_id": { "$ref": "#/$defs/nonEmptyString" },
    "session_id": { "$ref": "#/$defs/nonEmptyString" },
    "timestamp": { "type": "string", "format": "date-time" },
    "type": {
      "enum": [
        "user_message", "assistant_message", "assistant_thinking",
        "tool_call", "tool_result", "usage", "title_generated",
        "title_reevaluated", "agent_notice", "subagent_spawned",
        "subagent_event", "subagent_usage", "subagent_completed"
      ]
    },
    "sequence": { "type": "integer", "minimum": 1 },
    "turn_id": { "$ref": "#/$defs/nonEmptyString" },
    "request_id": { "$ref": "#/$defs/nonEmptyString" },
    "id": { "$ref": "#/$defs/nonEmptyString" },
    "text": { "type": "string" },
    "model_ref": { "$ref": "#/$defs/modelRef" },
    "stop_reason": { "type": "string" },
    "name": { "$ref": "#/$defs/nonEmptyString" },
    "arguments": { "type": "object" },
    "file_path": { "type": "string" },
    "call_id": { "$ref": "#/$defs/nonEmptyString" },
    "content": { "type": "string" },
    "summary": { "type": "string" },
    "success": { "type": "boolean" },
    "status": { "enum": ["completed", "failed", "cancelled", "denied"] },
    "duration_ms": { "$ref": "#/$defs/nonNegativeInteger" },
    "exit_code": { "type": "integer" },
    "metadata": { "type": "object" },
    "role": { "$ref": "#/$defs/nonEmptyString" },
    "input_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
    "output_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
    "cache_read_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
    "cache_creation_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
    "reasoning_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
    "turn_count": { "type": "integer", "minimum": 1 },
    "title": { "type": "string" },
    "kind": { "type": "string" },
    "message": { "type": "string" },
    "subagent_id": { "$ref": "#/$defs/nonEmptyString" },
    "parent_subagent_id": { "type": "string" },
    "task": { "type": "string" },
    "depth": { "$ref": "#/$defs/nonNegativeInteger" },
    "index": { "$ref": "#/$defs/nonNegativeInteger" },
    "total": { "type": "integer", "minimum": 1 },
    "inner": { "$ref": "#/$defs/subagentInnerEvent" },
    "error": { "type": "string" }
  },
  "allOf": [
    { "if": { "properties": { "type": { "const": "user_message" } } }, "then": { "required": ["text"] } },
    { "if": { "properties": { "type": { "enum": ["assistant_message", "assistant_thinking"] } } }, "then": { "required": ["text", "model_ref"] } },
    { "if": { "properties": { "type": { "const": "tool_call" } } }, "then": { "required": ["id", "name", "arguments"] } },
    { "if": { "properties": { "type": { "const": "tool_result" } } }, "then": { "required": ["call_id", "content", "success", "status"] } },
    { "if": { "properties": { "type": { "const": "usage" } } }, "then": { "required": ["role", "model_ref", "input_tokens", "output_tokens", "turn_count"] } },
    { "if": { "properties": { "type": { "enum": ["title_generated", "title_reevaluated"] } } }, "then": { "required": ["title"] } },
    { "if": { "properties": { "type": { "const": "agent_notice" } } }, "then": { "required": ["kind", "message"] } },
    { "if": { "properties": { "type": { "const": "subagent_spawned" } } }, "then": { "required": ["subagent_id", "task", "depth", "model_ref"] } },
    { "if": { "properties": { "type": { "const": "subagent_event" } } }, "then": { "required": ["subagent_id", "inner"] } },
    { "if": { "properties": { "type": { "const": "subagent_usage" } } }, "then": { "required": ["subagent_id", "model_ref", "input_tokens", "output_tokens", "turn_count"] } },
    { "if": { "properties": { "type": { "const": "subagent_completed" } } }, "then": { "required": ["subagent_id", "status", "duration_ms"] } }
  ],
  "additionalProperties": false,
  "$defs": {
    "nonEmptyString": { "type": "string", "minLength": 1 },
    "modelRef": { "type": "string", "pattern": "^[^/]+/.+$" },
    "nonNegativeInteger": { "type": "integer", "minimum": 0 },
    "subagentInnerEvent": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type": {
          "enum": [
            "assistant_message", "assistant_thinking", "tool_call_pending",
            "tool_call", "tool_result", "agent_done", "agent_error",
            "usage", "agent_notice"
          ]
        },
        "text": { "type": "string" },
        "id": { "type": "string" },
        "name": { "type": "string" },
        "arguments": { "type": "object" },
        "call_id": { "type": "string" },
        "success": { "type": "boolean" },
        "content": { "type": "string" },
        "summary": { "type": "string" },
        "error": { "type": "string" },
        "input_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
        "output_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
        "cache_read_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
        "cache_creation_tokens": { "$ref": "#/$defs/nonNegativeInteger" },
        "kind": { "type": "string" },
        "message": { "type": "string" }
      },
      "additionalProperties": false
    }
  }
}
''';
