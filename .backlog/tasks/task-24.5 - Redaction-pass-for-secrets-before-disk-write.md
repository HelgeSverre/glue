---
id: TASK-24.5
title: Redaction pass for secrets before disk write
status: To Do
assignee: []
created_date: '2026-04-19 00:43'
labels:
  - session-jsonl-2026-04
  - security
dependencies:
  - TASK-24.1
  - TASK-24.2
documentation:
  - cli/docs/plans/2026-04-19-session-jsonl-event-schema-plan.md
parent_task_id: TASK-24
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Session logs persist on disk. Redact secrets before writing — and represent the redaction explicitly in the event, not silently.

**Redact:**
- Known API key env vars (ANTHROPIC_API_KEY, OPENAI_API_KEY, MISTRAL_API_KEY, GROQ_API_KEY, GEMINI_API_KEY, OPENROUTER_API_KEY, LANGFUSE_*)
- Provider auth headers (Authorization, x-api-key, api-key)
- Bearer tokens in any header or URL query
- Cookies
- Common secret patterns: `sk-ant-*`, `sk-*`, `gsk_*`, `AKIA*`, JWTs
- User-configured additional secret patterns (`redaction.custom_patterns` in config)

**Representation in event:**
```json
{
  "type": "tool_call.started",
  "redactions": [
    {"path": "data.arguments.env.OPENAI_API_KEY", "reason": "secret"}
  ],
  "data": {
    "arguments": { "env": { "OPENAI_API_KEY": "[redacted]" } }
  }
}
```

**Files:**
- Create: `cli/lib/src/session/redaction.dart` — pure function `redact(Map) → (redactedData, redactions[])`
- Integrate: called from `SessionStore.logEvent` before write
- Config: `redaction.custom_patterns` (list of regex) in `GlueConfig`

**Security rule:** never log a raw key value anywhere (debug output included). Redact first, then log.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Known API key env vars redacted in event data + paths recorded in `redactions[]`
- [ ] #2 Auth headers (Authorization, x-api-key) redacted from HTTP request events
- [ ] #3 Common secret patterns (sk-*, gsk_*, AKIA*, JWT) redacted by regex
- [ ] #4 User-configured additional patterns honored
- [ ] #5 Redaction never mutates source data (pure function)
- [ ] #6 Debug output path also routes through redaction (no raw keys in any log)
- [ ] #7 Tests cover each secret family + custom pattern + `redactions` array format
<!-- AC:END -->
