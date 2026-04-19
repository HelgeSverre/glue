---
sidebar: false
aside: false
outline: false
---

# Why Glue

Coding work already happens in terminals. Glue is an agent that lives where you
already work, not a browser tab, not a panel bolted onto an IDE.

## Small surface area

IDE assistants keep piling on: side panels, auto-completions, chat docks, inline
previews, mode switchers. Glue keeps a narrow surface:

- one prompt
- one session
- a small set of honest tools (read, edit, run, search, fetch)
- a transcript you can read, log, and resume

When the product does less, you keep more control over what happens to your
files.

## Terminal-native by choice

A full-screen TUI is acceptable because Glue already owns the session while it
works. You see every tool call, every file change, and every command output in
order. No hidden actions; nothing happens in a panel you forgot about.

## Run risky work somewhere else

Some work shouldn't touch your laptop: scraping, dependency installs for
unknown packages, one-off data processing, malware-adjacent analysis. Glue can
run inside an ephemeral Docker container <FeatureStatus status="shipping" /> or,
later, on a remote runtime <FeatureStatus status="planned" /> while you keep
using your host machine normally.

## Curated models, not a picker zoo

Startup fetching every legacy model from every provider is noisy and slow. Glue
ships with a curated catalog <FeatureStatus status="shipping" /> covering the
providers that matter: Anthropic, OpenAI, Gemini, Mistral, Groq, Ollama,
OpenRouter. OpenAI-compatible endpoints slot in through an `adapter: openai`
config. Credentials stay out of project files.

## Local-first observability

You don't need OpenTelemetry or an account on a hosted dashboard to debug a
session. Glue writes a JSONL log of every event: prompts, assistant messages,
tool calls, tool results, errors. The file is text. `tail` works. `grep` works.
Replay UI builds on top later.

## What Glue is not

- Not an autonomous developer replacement.
- Not an IDE.
- Not a chat product.
- Not a hosted service — sessions live on your machine, not ours.

## What we optimize for

- The CLI starts fast.
- The TUI stays out of your way.
- Tool calls read like a normal transcript.
- Config is small; every field has a reason to exist.
- Planned features stay labelled `planned` until they ship.
