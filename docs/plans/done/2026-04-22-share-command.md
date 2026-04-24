# /share command spec and implementation plan

## Goal

Add a `/share` slash command that exports the current session's visible conversation history as:

- HTML
- Markdown
- optional GitHub gist via `gh`

The export is for sharing the readable conversation transcript, not for dumping all session metadata or observability logs. It should include:

- user messages
- assistant messages
- tool calls
- tool results
- subagent activity, including nested subagent structure

It should exclude internal-only bookkeeping such as title generation events, observability spans, token/cost internals, and unrelated raw metadata.

## Product scope

### v1

- `/share` defaults to exporting HTML
- `/share html`
- `/share md`
- current active session only
- only available when the app is idle
- self-contained HTML output file
- Markdown output designed for readability and later editing
- subagent activity rendered visually, including nesting

### v1.1 or later

- export a saved session by id/query instead of only the current session
- richer event families once Glue persists more structured events
- search/filter/collapse polish in the HTML export

## What to export from Glue's session log

Glue persists `conversation.jsonl` events through `SessionStore.logEvent()`.
Current user-visible event types in the log are:

- `user_message`
- `assistant_message`
- `tool_call`
- `tool_result`

Current non-share-worthy persisted events include:

- `title_generated`
- `title_reevaluated`

Current in-memory UI events also include subagent updates, but those are not yet represented in the persisted conversation log in a share-friendly structure. For `/share`, we should add a normalized transcript layer that can support both current events and richer subagent events.

Implementation note: until Glue persists subagent events in `conversation.jsonl`, nested subagent export support should remain explicit at the normalized-entry layer rather than pretending raw subagent rows already exist.

## Transcript model for sharing

Introduce a share-focused normalized transcript model rather than rendering directly from raw JSONL.

Suggested model:

```dart
enum ShareEntryKind {
  user,
  assistant,
  toolCall,
  toolResult,
  subagentGroup,
  subagentMessage,
}

class ShareTranscript {
  final SessionMeta meta;
  final DateTime exportedAt;
  final List<ShareEntry> entries;
}

class ShareEntry {
  final int index;
  final ShareEntryKind kind;
  final String text;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final String? subagentId;
  final int nestingLevel;
  final List<ShareEntry> children;
}
```

Notes:

- `index` gives stable HTML anchors like `#entry-12`
- `children` supports nested subagent groups out of the gate
- `nestingLevel` makes Markdown and HTML indentation easy
- the model is intentionally small and future-extensible

## Event normalization rules

### Existing session events

- `user_message` -> `ShareEntryKind.user`
- `assistant_message` -> `ShareEntryKind.assistant`
- `tool_call` -> `ShareEntryKind.toolCall`
- `tool_result` -> `ShareEntryKind.toolResult`

### Tool result content selection

For shared output:

1. use `summary` if present and non-empty
2. otherwise use `content`
3. ignore `metadata` by default

### Ignored event types

Ignore these in v1 export:

- `title_generated`
- `title_reevaluated`
- future non-visual/internal event types unless they become intentionally shareable

### Subagent events

We should support subagent nesting visually from the beginning.
That means the transcript model and renderers should support nested groups even if current persisted session data is still thin.

Recommended path:

- define normalized subagent entry kinds now
- add tests that prove nested subagent structures render properly
- initially support them from normalized model fixtures and future-proof the renderers
- once Glue persists subagent events into the session log, map them into the same model without changing the renderers

## Rendering plan

## Markdown output

The Markdown export should be readable in raw form and easy to edit later.

Suggested structure:

````md
# Glue Session

> **Session ID:** `...`
> **Title:** ...
> **Model:** `provider/model`
> **Started:** ...
> **Exported:** ...
> **Directory:** `/path`

---

<a id="entry-1"></a>

## User

...

---

<a id="entry-2"></a>

## Glue

...

---

<a id="entry-3"></a>

## Tool: read_file

### Arguments

```json
{ ... }
```
````

---

<a id="entry-4"></a>

## Tool result

```text
...
```

````

### Markdown rendering rules

- user messages: plain text preserving line breaks
- assistant messages: preserve original markdown exactly
- tool arguments: pretty-printed fenced JSON
- tool results: fenced `text` blocks by default
- subagent groups: nested headings or list-based sections
- subagent messages: indented blockquotes or nested headings

Suggested subagent markdown shape:

```md
## Subagent: docs-research

> searching renderer options

### Tool: web_search
...
````

This keeps the transcript editable and structurally obvious.

## HTML output

The HTML export should be self-contained and should not be produced by converting terminal ANSI output.

Visual direction for v1:

- compact
- minimal
- no rounded "AI card" look
- no status-color border system around entries
- should feel like Glue's real terminal rendering, but fullscreen and shareable
- should resemble the website hero terminal more than a dashboard app

Instead:

1. normalize session events into share entries
2. render structured HTML from that model
3. render assistant markdown to HTML
4. render tool args/results as escaped code blocks
5. show subagent nesting as indented transcript structure, not nested cards

### HTML structure

Each entry should have an anchor id, but the outer presentation should stay close to terminal transcript rows rather than boxed cards.

```html
<section class="transcript-entry entry-user" id="entry-12">
  <a class="entry-anchor" href="#entry-12">#12</a>
  <div class="entry-head">❯ You</div>
  <div class="entry-body">...</div>
</section>
```

Suggested role classes:

- `entry-user`
- `entry-assistant`
- `entry-tool-call`
- `entry-tool-result`
- `entry-subagent-group`
- `entry-subagent-message`

Styling guidance:

- use text color and spacing, not decorative borders, to distinguish entry kinds
- square edges or no visible card treatment
- code/result blocks may still use subtle background panels for readability
- subagent nesting should look like transcript indentation/tree structure

### Assistant markdown to HTML

Do not inline giant handcrafted HTML strings in Dart.
The HTML document should come from template files plus a renderer pipeline.

Assistant content should use the `markdown` package to convert markdown to HTML.
Recommended package:

- `markdown`

Use GitHub-flavored extensions where appropriate.
Remember: the package does not sanitize HTML, so we should decide whether to:

- escape raw HTML before markdown rendering, or
- accept trusted local content for v1 and document the tradeoff

### HTML template strategy

We should avoid huge inline string literals in Dart.
Recommended approach:

- store templates as asset-like files under a source-controlled template directory, for example:
  - `lib/src/share/templates/share_page.html.mustache`
  - `lib/src/share/templates/share_entry.mustache`
  - `lib/src/share/templates/share_markdown.mustache`
- load template files at runtime from the package source tree
- render with a simple placeholder/partials system

Recommended package:

- `mustache_template`

Why:

- mature and small
- supports partials
- keeps templates readable and editable
- HTML escaping by default
- no build_runner/codegen burden

Less attractive options explored:

- `html_template`: powerful, but oriented around generated template functions and build tooling; heavier than needed for a CLI export file generator
- `template_engine`: feature-rich, but likely overpowered for this use case and less obviously minimal than Mustache

Recommendation:

- use `mustache_template` for outer HTML/Markdown document scaffolding
- use `markdown` for assistant-message HTML rendering
- keep per-entry rendering in Dart or via small Mustache partials, whichever ends up simpler after first implementation

## File layout proposal

Suggested new files:

- `lib/src/share/share_models.dart`
- `lib/src/share/share_transcript_builder.dart`
- `lib/src/share/session_share_exporter.dart`
- `lib/src/share/html_share_renderer.dart`
- `lib/src/share/markdown_share_renderer.dart`
- `lib/src/share/gist_publisher.dart` later
- `lib/src/share/templates/share_page.html.mustache`
- `lib/src/share/templates/share_entry.html.mustache`
- `lib/src/share/templates/share_document.md.mustache`

## Output naming

Default output names:

- `glue-session-<session-id>.html`
- `glue-session-<session-id>.md`

Default output directory:

- current working directory

Rationale:

- easy to find and share
- mirrors Copilot's style closely enough

## Command UX

### Success

- `Exported HTML transcript to /path/glue-session-123.html`
- `Exported markdown transcript to /path/glue-session-123.md`
- `Exported session to:\n  /path/glue-session-123.html\n  /path/glue-session-123.md`

### Failure

- `No active session yet — nothing to share.`
- `Current session has no conversation data.`
- `Wait for the current turn to finish before sharing.`

## Test plan

Follow TDD in small steps.

### Transcript builder tests

Add a new test file such as:

- `test/share/share_transcript_builder_test.dart`

Test cases:

1. builds transcript entries from user/assistant/tool call/tool result events
2. ignores non-visual events like title generation
3. prefers tool result summary over full content
4. handles missing tool arguments as empty map
5. ignores malformed/unknown event types safely
6. preserves event order
7. builds nested subagent groups from normalized subagent fixtures
8. supports nested subagent message ordering inside a parent group

### Markdown renderer tests

Add:

- `test/share/markdown_share_renderer_test.dart`

Test cases:

1. renders session metadata header
2. preserves assistant markdown verbatim
3. renders tool arguments as fenced JSON
4. renders tool results as fenced text
5. emits entry anchors
6. renders nested subagent groups visibly and hierarchically
7. handles empty transcript without crashing

### HTML renderer tests

Add:

- `test/share/html_share_renderer_test.dart`

Test cases:

1. renders a complete self-contained HTML document
2. emits entry anchor ids like `entry-1`
3. renders assistant markdown to HTML paragraphs/headings/code blocks
4. escapes user text and tool output correctly
5. renders tool call arguments in code blocks/details sections
6. renders nested subagent entries with nested containers/classes
7. includes session metadata header
8. keeps output stable enough for snapshot-like assertions on important sections

### Export coordinator tests

Add:

- `test/share/session_share_exporter_test.dart`

Test cases:

1. writes markdown file for current session
2. writes html file for current session
3. uses expected file naming
4. fails cleanly when no active session exists
5. fails cleanly when conversation is empty

### Slash command tests

Extend command tests, likely in:

- `test/commands/builtin_commands_test.dart`
- or app command helper tests if those exist

Test cases:

1. `/share` defaults to html
2. `/share html` selects html only
3. `/share md` selects markdown only
4. invalid subcommand returns helpful usage text
5. busy app state returns the idle-only error

### Gist tests later

If implemented:

- `test/share/gist_publisher_test.dart`

Test cases:

1. reports missing `gh`
2. reports unauthenticated `gh`
3. parses gist URL from successful command output
4. defaults to publishing markdown export

## Open questions to answer before implementation

1. **Where should templates live?**
   - under `lib/src/share/templates/`
   - or under a top-level `templates/` directory
     Recommendation: keep them under `lib/src/share/templates/` with small file-loader helpers.

2. **Do we want to add `mustache_template` as a dependency now, or start with file-based placeholders using a tiny internal renderer?**
   Recommendation: add `mustache_template` now to avoid inventing our own templating mini-language.

3. **How should raw HTML embedded in assistant markdown be handled?**
   - allow as trusted content
   - or pre-escape to avoid risky exports
     Recommendation: decide explicitly before shipping; safest default is to avoid passing raw HTML through unless needed.

4. **How should subagent events be persisted?**
   Current session logs do not appear to store share-friendly nested subagent entries yet. We need a concrete persisted event schema.
   Suggested future event types:
   - `subagent_start`
   - `subagent_message`
   - `subagent_tool_call`
   - `subagent_tool_result`
   - `subagent_finish`
     with `subagent_id` and optional `parent_subagent_id`.

5. **Do we collapse long tool outputs in HTML by default?**
   Recommendation: yes, use `<details>` for tool output and maybe auto-collapse over a line threshold.

6. **Should Markdown include HTML anchors?**
   Recommendation: yes, use simple `<a id="entry-n"></a>` anchors for parity with HTML.

7. **Should `/share gist` publish HTML, Markdown, or both?**
   Current implementation: Markdown only, with HTML optional later if it proves worthwhile.

## Proposed implementation order

1. add spec/prototype docs
2. add failing tests for transcript builder
3. implement normalized transcript builder for current event types plus nested subagent fixtures
4. add failing markdown renderer tests
5. implement markdown renderer
6. add failing HTML renderer tests
7. implement HTML renderer using template files
8. add export coordinator tests
9. wire `/share` into slash commands
10. revisit gist support once core export is stable

## Prototype notes

A self-contained prototype HTML file should live at:

- `docs/prototypes/share-conversation.html`

Purpose:

- sketch layout before Dart implementation
- validate visual treatment of nested subagents
- test dark theme, anchors, sticky header, code blocks, and long outputs
- serve as a design target for template files later
