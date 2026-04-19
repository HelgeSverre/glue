---
title: Sessions
description: Every Glue session is an append-only JSONL log you can read, resume, and replay.
sidebar: false
aside: false
outline: false
---

# Sessions

Every session Glue runs is stored as plain text on your machine. No hosted
dashboard, no telemetry upload, no agent ID tied to an account. The file is
JSONL — one event per line, `tail`-able and `grep`-able.

Canonical sources:
- [`docs/reference/session-storage.md`](https://github.com/helgesverre/glue/blob/main/docs/reference/session-storage.md)
- [`docs/reference/glue-home-layout.md`](https://github.com/helgesverre/glue/blob/main/docs/reference/glue-home-layout.md)

## Where sessions live

```text
~/.glue/sessions/<session-id>/
├── meta.json            # identity: model, provider, cwd, title, timestamps, git context
├── conversation.jsonl   # append-only event log
└── state.json           # session-scoped runtime state (Docker mounts, browser containers)
```

The `<session-id>` is a timestamp-based ID. Directories accumulate over time;
automatic GC is <FeatureStatus status="planned" />.

## The event log

<FeatureStatus status="shipping" /> Every event is one JSON object per line,
timestamped in UTC. Current event types:

- `user_message` — prompt you typed
- `assistant_message` — streamed model response
- `tool_call` — the agent invoked a tool (id, name, arguments)
- `tool_result` — result returned to the agent (call_id, content)
- `title_generated` — background title generation

An expanded event schema — covering tool state transitions, runtime events,
file edits, and error details — is <FeatureStatus status="planned" />.

## Example

```jsonl
{"timestamp":"2026-04-19T10:30:00.000Z","type":"user_message","text":"explain the retry logic in http_client.dart"}
{"timestamp":"2026-04-19T10:30:00.420Z","type":"assistant_message","text":"Reading the file and the tests around it."}
{"timestamp":"2026-04-19T10:30:00.510Z","type":"tool_call","id":"t_1","name":"read","arguments":{"path":"cli/lib/src/web/http_client.dart"}}
{"timestamp":"2026-04-19T10:30:00.630Z","type":"tool_result","call_id":"t_1","content":"…"}
{"timestamp":"2026-04-19T10:30:01.900Z","type":"title_generated","title":"HTTP client retry logic walkthrough"}
```

## Resume

<FeatureStatus status="shipping" /> Pass a session ID to continue where you
left off — the `meta.json` and `conversation.jsonl` are replayed back into the
context window before the next prompt.

```sh
glue --resume <session-id>
```

## Replay UI

<FeatureStatus status="planned" /> A dedicated replay surface that reads
`conversation.jsonl` and renders it step-by-step, with tool call collapse,
diff rendering for file edits, and time scrubbing. Until it ships, any JSONL
viewer works — the format is stable.

## Why JSONL

- **No vendor lock-in.** The file is text. Any language can read it.
- **Append-only.** Crash-safe: a partial line at the tail doesn't corrupt
  earlier events.
- **Debug-friendly.** `tail -f` + `jq` is a reasonable observability stack
  for a local-first coding agent.
- **Durable.** Session history doesn't disappear because a hosted service
  rotated its database.

The simplification plan in the repo also removes the previous OTEL/Langfuse
observability wiring. Sessions are the single durable log.

<p><a href="/docs/using-glue/sessions">Sessions guide →</a></p>
