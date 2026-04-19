---
pageClass: page-marketing
sidebar: false
aside: false
outline: false
---

# Features

Every feature has a status: <FeatureStatus status="shipping" />
available today, <FeatureStatus status="experimental" /> works but rough, and
<FeatureStatus status="planned" /> not yet in the binary.

## Agent loop

<FeatureStatus status="shipping" /> The core ReAct loop: prompt → reason → tool
call → tool result → next step. Streamed to the terminal, interruptible, and
fully logged.

**When you use this:** any time you want an agent to make multi-step progress
rather than one-shot answers.

## File editing

<FeatureStatus status="shipping" /> Targeted edits, multi-file patches, write
new files. Every edit is visible in the transcript as a diff summary.

**When you use this:** "add a retry for ECONNRESET" · "rename this helper
across the repo" · "convert these tests to the new fixture style".

## Command execution

<FeatureStatus status="shipping" /> Run shell commands through the user's
`$SHELL`. Output is captured, streamed back, and written to the session log.

**When you use this:** running tests, build steps, linters, or any command you
want the agent to observe.

## Models and providers

<FeatureStatus status="shipping" /> Curated default catalog. `provider/model`
IDs. `adapter: openai` for any OpenAI-compatible endpoint. Credentials live in
`~/.glue/credentials.json`, separate from project config.

**When you use this:** switching providers mid-session, running locally with
Ollama, hitting a self-hosted endpoint.

<p><a href="/models">Model catalog →</a></p>

## Host runtime

<FeatureStatus status="shipping" /> Commands run on your machine in your normal
environment — fastest path, uses the tools you already have installed.

## Docker sandbox

<FeatureStatus status="shipping" /> Ephemeral containers for risky work. Mount
the workspace, drop the container when the session ends. Sandbox polish is
<FeatureStatus status="experimental" />.

## Cloud runtimes

<FeatureStatus status="planned" /> Offload to remote workers (E2B, Modal,
Daytona, custom SSH or container workers). Tracked by the runtime boundary
plan.

<p><a href="/runtimes">Runtime capabilities →</a></p>

## Sessions

<FeatureStatus status="shipping" /> Append-only JSONL logs of every session,
under `~/.glue/sessions/`. Resumable across runs. Replay UI is
<FeatureStatus status="planned" />; the expanded event schema is
<FeatureStatus status="planned" />.

<p><a href="/sessions">How sessions work →</a></p>

## Web tools

<FeatureStatus status="shipping" /> Fetch pages, extract content, run browser
automation. The browser CDP backend is
<FeatureStatus status="experimental" />.

<p><a href="/web">Web tools →</a></p>

## Subagents

<FeatureStatus status="shipping" /> Delegate a sub-task to a separate agent
with its own context and tool set. Useful for parallel search or independent
investigations.

## Skills

<FeatureStatus status="shipping" /> Discoverable, runnable skill definitions
the agent can invoke as first-class tools.

## MCP integration

<FeatureStatus status="shipping" /> Talk to any MCP server as a tool source.
Useful for editor integration, external search providers, and custom tool
backends.
