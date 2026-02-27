# Web Search & Research Tool — Design Plan

## The Problem

When a user asks "does OpenAI support model X?" or "what's the latest on library Y?", Glue
hits a hard wall — it has no way to reach the internet. Every tool in `lib/src/agent/tools.dart`
is filesystem/shell-local. The user has to leave the terminal, search manually, and paste results
back. That's friction the tool should absorb.

## Two Design Options

### Option A — `web_search` Tool (Thin, Fast)

A single tool that accepts a query string, calls a search API, and returns a ranked list of
snippets + URLs. The agent then synthesises the answer from those snippets.

**Pros:** Simple. One tool, one API call, low latency.  
**Cons:** Snippets are often too short. For "does gpt-5.2 exist?" a snippet may not contain
the definitive answer — the agent needs to follow a link.

### Option B — `research` Tool (Headless Subagent with Browser Access)

Spawns a focused subagent whose *only* job is to answer a factual question. That subagent is
given `web_search` + `fetch_url` tools and runs its own ReAct loop until it has a confident
answer, then returns structured output.

**Pros:** Self-directed, can follow links, handles multi-hop questions.  
**Cons:** Higher latency, more tokens, more moving parts.

### Chosen Approach — Both, Layered

Implement `web_search` and `fetch_url` as primitive tools (Option A). The existing
`spawn_subagent` / `spawn_parallel_subagents` machinery then lets the agent compose them into
a research workflow (Option B) without any new plumbing. The user's question about gpt-5.2
would have gone:

```
Agent receives question
 → spawn_subagent("Research whether OpenAI API supports model gpt-5.2 ...")
    → web_search("OpenAI gpt-5.2 model API support")
    → fetch_url("https://platform.openai.com/docs/models")
    → returns structured answer
 → Agent synthesises final reply
```

---

## Tool 1 — `web_search`

### Purpose
Query a search engine and get back a list of result titles, URLs, and snippets.

### Schema

```dart
class WebSearchTool extends Tool {
  @override String get name => 'web_search';

  @override String get description =>
    'Search the web and return a ranked list of results (title, URL, snippet). '
    'Use this to find current information, documentation, or verify facts.';

  @override List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'query',
      type: 'string',
      description: 'The search query.',
    ),
    ToolParameter(
      name: 'num_results',
      type: 'integer',
      description: 'Number of results to return (default: 5, max: 10).',
      required: false,
    ),
  ];
}
```

### Output format

```
1. OpenAI Models — platform.openai.com/docs/models
   The latest GPT-4o, GPT-4 Turbo, and o1 models are listed here. GPT-5 is not yet available.

2. OpenAI API Reference — platform.openai.com/docs/api-reference/models
   Use GET /v1/models to list all models currently accessible to your API key.
```

Plain text, numbered, one blank line between results. Easy for the LLM to parse.

### Provider options (in order of preference)

| Provider | Notes |
|---|---|
| **Brave Search API** | Privacy-respecting, generous free tier (2000 req/month), clean JSON. First choice. |
| **Serper.dev** | Cheap, Google results, 2500 free credits. Good fallback. |
| **DuckDuckGo Instant Answer API** | No key required, but limited — only instant answers, not full SERPs. Last resort. |
| **SerpAPI** | Gold standard quality but expensive. Enterprise option. |

Config resolution: `GLUE_SEARCH_API_KEY` env var → `~/.glue/config.yaml` `search.api_key` →
error if none set.

---

## Tool 2 — `fetch_url`

### Purpose
Fetch a URL and return its text content, stripped of HTML tags and scripts. Lets the agent
read documentation pages, API references, changelogs, etc.

### Schema

```dart
class FetchUrlTool extends Tool {
  @override String get name => 'fetch_url';

  @override String get description =>
    'Fetch a URL and return its readable text content (HTML stripped). '
    'Use after web_search to read a specific page.';

  @override List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'url',
      type: 'string',
      description: 'The URL to fetch.',
    ),
    ToolParameter(
      name: 'max_chars',
      type: 'integer',
      description: 'Max characters to return (default: 8000).',
      required: false,
    ),
  ];
}
```

### Implementation notes

- Use Dart's `http` package (`dart pub add http`).
- Strip HTML with a simple regex pass (remove `<script>`, `<style>`, then all tags).
- Collapse whitespace runs into single spaces.
- Truncate to `max_chars` with a trailing `"… (truncated)"` notice.
- Hard timeout: 15 seconds. Return error string on timeout, no throw.
- Follow redirects (default `http.Client` behaviour).
- Do **not** execute JavaScript — plain HTTP GET only.
- Robots.txt: honour it for politeness, skip check in the fast path (document this caveat).

### Output

Raw text content of the page, truncated. No formatting applied — the agent reads it as-is.

---

## Configuration

New keys in `~/.glue/config.yaml` and `GlueConfig`:

```yaml
search:
  provider: brave          # brave | serper | ddg
  api_key: YOUR_KEY_HERE
  max_results: 5
  fetch_max_chars: 8000
```

Dart:

```dart
class SearchConfig {
  final String provider;      // 'brave'
  final String? apiKey;
  final int maxResults;       // default 5
  final int fetchMaxChars;    // default 8000
}
```

Added to `GlueConfig` as `SearchConfig? search`. Null means no search tools registered.

---

## Tool Registration

Tools are currently registered in `AgentCore` (or wherever the tool list is built).
Search tools are optional — only registered when `config.search != null`:

```dart
final tools = [
  ReadFileTool(),
  WriteFileTool(),
  EditFileTool(),
  BashTool(maxLines: config.bashMaxLines),
  GrepTool(),
  ListDirectoryTool(),
  if (config.search != null) ...[
    WebSearchTool(config.search!),
    FetchUrlTool(config.search!),
  ],
  SpawnSubagentTool(manager, depth: depth),
  SpawnParallelSubagentsTool(manager, depth: depth),
];
```

---

## The `research` Workflow (No New Code Required)

With the two primitive tools in place, the agent can answer the gpt-5.2 question like this:

```
User: does OpenAI support gpt-5.2?

Agent thinks: I need current info. I'll spawn a research subagent.

→ spawn_subagent(
    task: "Find out whether OpenAI's API currently supports a model named gpt-5.2.
           Check the official OpenAI models documentation and return a clear yes/no
           with supporting evidence.",
    model: "claude-haiku-4-5"   // cheap, fast for research tasks
  )

  Subagent loop:
  → web_search("OpenAI gpt-5.2 model available API 2025")
  → fetch_url("https://platform.openai.com/docs/models")
  → synthesise: "No. As of [date], OpenAI does not offer a model named gpt-5.2.
                 Available models include gpt-4o, gpt-4-turbo, gpt-4.1, o1, o3-mini.
                 Source: platform.openai.com/docs/models"

Agent: "No, gpt-5.2 doesn't exist. OpenAI's current lineup is: ..."
```

A named **research profile** in config makes this ergonomic:

```yaml
profiles:
  research:
    provider: anthropic
    model: claude-haiku-4-5   # fast + cheap for web lookups
```

The main agent can then `spawn_subagent(..., profile: 'research')` for any web question.

---

## Security & Safety

| Concern | Mitigation |
|---|---|
| SSRF (fetch internal IPs) | Blocklist: `localhost`, `127.*`, `10.*`, `192.168.*`, `169.254.*` |
| Credential leakage via URL | Warn if URL contains `?token=` / `?key=` patterns |
| Malicious page content | Content is plain text only — no execution, no parsing of scripts |
| API key exposure in logs | Keys never logged; config masked in `/config` command output |
| Rate limiting | Honour `Retry-After` headers; surface errors cleanly |

---

## Error Handling

All errors return a descriptive string (never throw to the agent loop):

```
Error: web_search requires GLUE_SEARCH_API_KEY to be set.
Error: fetch_url timed out after 15s — https://example.com
Error: fetch_url returned 403 Forbidden — https://example.com
Error: web_search API error (429 Too Many Requests) — rate limit hit, try later
```

---

## File Changes

| File | Change |
|---|---|
| `lib/src/tools/web_tools.dart` | **New** — `WebSearchTool`, `FetchUrlTool`, `SearchConfig` |
| `lib/src/config/glue_config.dart` | Add `SearchConfig? search`, parse from env/file |
| `lib/src/agent/agent_core.dart` | Register tools conditionally on `config.search != null` |
| `lib/glue.dart` | Export `WebSearchTool`, `FetchUrlTool` |
| `pubspec.yaml` | Add `http: ^1.2.0` dependency |
| `test/tools/web_tools_test.dart` | **New** — mock HTTP, test snippet formatting, truncation, error paths |
| `README.md` | Document `GLUE_SEARCH_API_KEY` setup, provider options |

---

## Implementation Phases

### Phase 1 — `fetch_url` (no API key needed)
Start here. Pure HTTP, immediately useful for "read this doc page for me" tasks.
Validates the HTML-stripping and truncation logic in isolation.

### Phase 2 — `web_search` with Brave
Wire up Brave Search API. Nail the output format. Add config parsing.

### Phase 3 — Research profile
Document the `research` profile pattern. Add example to README.
Optionally add a `/search <query>` slash command as syntactic sugar.

### Phase 4 — DuckDuckGo fallback
No-key fallback using DDG Instant Answer API for users who don't want to set up an API key.
Limited but better than nothing.

---

## Open Questions

1. **Should `fetch_url` be available to all agents by default, or gated behind `search` config?**
   Fetching a URL a user explicitly pastes in feels safe and useful even without a search key.
   Could gate `web_search` on the API key but leave `fetch_url` always registered.

2. **Caching.** Repeated `fetch_url` calls to the same URL within a session should probably be
   cached in-memory (URL → content map) to avoid redundant HTTP round-trips and stay inside
   rate limits. Simple `HashMap<String, String>` on the tool instance is enough.

3. **Streaming fetch.** For large pages, streaming the response and stopping at `max_chars`
   is more efficient than downloading then truncating. Worth doing from the start.

4. **`/search` command.** A `/search <query>` slash command that directly triggers
   `web_search` and renders results without going through the agent loop could be a nice UX
   shortcut. Out of scope for initial implementation.
