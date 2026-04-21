<!-- Generated from docs/reference/session-storage.md. Do not edit by hand. -->
<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->

# Session event types

Current event types appended to `conversation.jsonl`. The event
schema is expanding — tracked by the session JSONL schema plan.

| Event               | Payload fields            |
| ------------------- | ------------------------- |
| `user_message`      | `text`                    |
| `assistant_message` | `text`                    |
| `tool_call`         | `id`, `name`, `arguments` |
| `tool_result`       | `call_id`, `content`      |
| `title_generated`   | `title`                   |
