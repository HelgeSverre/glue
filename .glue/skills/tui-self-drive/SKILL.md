---
name: tui-self-drive
description: Use when working in glue's repo and you need to drive a separate glue process from outside — verifying TUI rendering, asserting a slash command produced the expected output, smoke-testing a feature end-to-end, or having one glue agent self-test another via agent-tui. Triggers on requests to test the TUI, automate a glue session, verify layout/overlay/streaming behavior, or have glue self-drive itself.
---

# TUI Self-Drive

A workflow for driving a separate `glue` process from outside via [`agent-tui`](https://github.com/pproenca/agent-tui), so an agent inside glue can verify TUI behavior end-to-end — slash commands, overlays, streaming output, layout — by spawning a second glue and observing it like a user would.

The value-add of this skill is **glue-specific TUI knowledge** layered on top of `agent-tui`'s generic primitives: which zones render what, when to wait, how overlays appear and dismiss, and what assertions are reliable vs. flaky.

## When to use this

- Verifying a TUI change you just made (a new slash command, a docked panel, an overlay) actually renders correctly under a real terminal.
- Smoke-testing a feature end-to-end before declaring it done — input expansion, model picker, streaming output.
- Reproducing a TUI bug a user reported, by scripting the exact key sequence.
- One-off recordings or demos that need a deterministic input sequence.
- An agent in glue session A wanting to confirm "if I do X in a fresh session, does the UI respond Y?".

## When NOT to use this

- Pure Dart-side unit or widget tests — use `dart test` directly. agent-tui is a real-PTY harness; it's slow and overkill for non-rendering logic.
- Sub-second timing assertions — the loop is `screenshot → decide → press`; expect 100s of ms per step.
- Non-glue automation — for any other TUI app, use `agent-tui`'s upstream skill at <https://github.com/pproenca/agent-tui/blob/master/skills/agent-tui/SKILL.md> directly.
- Headless integration tests where you don't actually need to inspect rendered output.

## Prerequisites

`agent-tui` must be installed and the daemon running. Run this once on a machine; both are idempotent:

```bash
# Install if missing (bun is fastest on macOS; falls back to npm)
command -v agent-tui >/dev/null || bun add -g agent-tui || npm i -g agent-tui

# Verify and start the daemon
agent-tui --version
agent-tui daemon start
```

Other install paths (in order of preference): `pnpm add -g agent-tui`, `cargo install --git https://github.com/pproenca/agent-tui.git --path cli/crates/agent-tui`, or the upstream installer `curl -fsSL https://raw.githubusercontent.com/pproenca/agent-tui/master/install.sh | bash`. Verified: `agent-tui 1.0.1` via `bun add -g`.

The skill assumes a `glue` binary is on `PATH`. If you're testing un-built code, build first:

```bash
cd cli && dart compile exe bin/glue.dart -o glue
export PATH="$PWD:$PATH"
```

For ephemeral sessions (recommended — avoids polluting `~/.glue/`), give glue an isolated `GLUE_HOME`:

```bash
export GLUE_HOME=$(mktemp -d)
```

`agent-tui run` in v1.0.1 inherits the parent shell's environment but **does not have a `--env` flag** despite what the upstream README suggests — set environment variables in the calling shell before invoking `agent-tui run`, e.g. `GLUE_HOME=/tmp/x agent-tui run --format json glue`.

## The core loop

`agent-tui`'s contract is `run → screenshot → press/type/wait → kill`. From inside a glue session, drive it via the `bash` tool:

1. **Spawn.** `agent-tui run --format json glue` returns a `session_id` in the JSON. Keep it.
2. **Settle.** Glue's startup paints async — *always* wait for stable output before the first action: `agent-tui wait --stable --session <id>` or `agent-tui wait "❯" --session <id>` (the input prompt). `--timeout` is in **milliseconds** as a plain integer, e.g. `--timeout 10000`, not `10s`.
3. **Observe.** `agent-tui screenshot --format json --session <id>` returns the current rendered screen as text. Read it to decide the next move; do not act blind.
4. **Act.** `agent-tui type "/model" --session <id>` for text, `agent-tui press Enter --session <id>` for keys, `agent-tui press Ctrl+J` for newline-without-submit.
5. **Re-settle.** Anything that changes the UI needs a fresh screenshot. Use `wait "expected text" --assert` over a fixed sleep — sleeps are flaky.
6. **Kill.** `agent-tui kill --session <id>`. Always. Leaked sessions accumulate in the daemon.

Always pass `--session <id>` once you have one — `agent-tui` defaults to "most recent session", which breaks if there's another concurrent driver.

## Glue-specific gotchas (the actual value)

These are the things that surprise you when driving glue specifically. None of them are in the upstream agent-tui skill.

### Layout zones

Glue paints into four stacked zones: **output** (top, scrollable transcript), **overlay** (modals/docked panels, transient), **status** (single-line bar showing model/provider/session), **input** (bottom, where the user types). When you screenshot, all four are in one capture — assert against the zone you care about, not the whole frame.

- Status-zone assertions (`expect "claude-opus-4-7"` after `/model`) are usually the cheapest and most stable.
- Output-zone assertions need `wait` because output streams in.
- Overlay-zone assertions are timing-sensitive — overlays can dismiss before you screenshot if the UI auto-hides them.

### Slash command autocomplete

Typing `/` in glue triggers an autocomplete overlay listing matching commands. The overlay is in the overlay zone. To dismiss without invoking, send `Escape`. To select via overlay, use `ArrowDown`/`ArrowUp` + `Enter`. To bypass the overlay entirely and run the command directly, type the full name then `Enter` in one go — but be aware the overlay still painted briefly between keystrokes, so a screenshot mid-type may capture it.

### `@file` reference expansion

Typing `@` triggers a file-autocomplete overlay similar to slash commands. Same dismiss pattern (`Escape`). If your test types `@` somewhere it doesn't mean it (e.g. an email address in a prompt), the overlay will appear and steal focus — escape first.

### Multi-line input — you cannot "paste" via `type`

This is the most important gotcha when driving glue and the one that bites first. **`agent-tui type "...\n..."` does not paste into glue's input as a single block.** Every newline byte (including those produced by `\n` in `type`, by `Ctrl+J`, and by `Enter`) is interpreted by glue's input handler as **submit**, fragmenting your "paste" across multiple turns.

Verified in glue + agent-tui 1.0.1:

| Send via agent-tui | Glue interprets as |
|---|---|
| `agent-tui type $'a\nb\nc'` | submit "a"; type "bc" into next prompt |
| `agent-tui press Enter` | submit |
| `agent-tui press Ctrl+J` | submit (LF == Enter) |
| `agent-tui press Alt+Enter` | **literal newline in input buffer** (multi-line mode; continuation lines marked with `·`) |

`agent-tui press` in 1.0.1 only accepts named keys/modifiers (`Enter`, `Ctrl+C`, `Alt+Enter`, `ArrowDown`, …) — there is no way to send raw escape sequences, so terminal **bracketed-paste mode** (`\x1b[200~ … \x1b[201~`) is unavailable as a workaround.

**The workaround:** when you actually need a multi-line block in glue's input, split on `\n` and interleave `Alt+Enter`:

```bash
LINES=("first line of paste" "second line" "third line")
for i in "${!LINES[@]}"; do
  agent-tui type "${LINES[$i]}" --session "$SID"
  if (( i < ${#LINES[@]} - 1 )); then
    agent-tui press Alt+Enter --session "$SID"
  fi
done
agent-tui press Enter --session "$SID"   # finally submit
```

If your "paste" is really just text the LLM should see verbatim and doesn't need to render multi-line, flatten it: replace newlines with `\n` literal escape characters in a single `type` call and trust the model to interpret them.

### `Ctrl+C` exits glue — it does not clear the input

In glue's TUI, `Ctrl+C` is the exit shortcut. Sending it via `agent-tui press Ctrl+C` will end the glue process and the agent-tui session along with it. Subsequent commands fail with `RPC error: No active session` or `Terminal error during write: Input/output error`.

To clear the input line without exiting, send `Escape` or backspace (`agent-tui press Backspace --session "$SID"`) repeatedly.

### Streaming output

LLM output streams token by token. `wait --stable` is the right primitive — it waits for the screen to stop changing for N ms. Don't `wait "specific phrase"` against streaming text unless you're certain of the exact wording the model produces; phrase the assertion against deterministic output (status zone, the `>` echo of your input, or a structured tool output).

### Startup state varies

A fresh `GLUE_HOME` triggers first-run UX (provider/model picker overlay). An existing one may not. For deterministic tests, always set `GLUE_HOME=$(mktemp -d)` and pre-seed `~/.glue/config.yaml` with the provider and model you want, or accept that the first action of every test is dismissing the picker overlay.

### Headless detection

Glue's TUI checks `stdout.isTerminal` and falls back to non-interactive mode if not. agent-tui runs glue under a real PTY, so this works — but if you spawn glue via `bash` directly (without agent-tui) for some reason, you get the headless code path and none of this skill applies.

### Terminal size

`agent-tui run --cols 120 --rows 40` is the default. Glue's responsive layout shifts at narrower widths (panels collapse, status truncates). Pin a known size if your assertions depend on layout.

## Worked example: verify `/model` switches the active model

Goal: from inside a glue session, spawn another glue, run `/model`, pick a specific model, send a prompt, confirm the status zone updated. End-to-end, all via the `bash` tool.

```bash
# 1. Isolated GLUE_HOME so first-run UX is deterministic
export GLUE_HOME=$(mktemp -d)
mkdir -p "$GLUE_HOME"
cat > "$GLUE_HOME/config.yaml" <<'YAML'
provider: anthropic
model: claude-haiku-4-5-20251001
YAML

# 2. Spawn glue, capture the session id
SID=$(agent-tui run --format json glue | jq -r .session_id)

# 3. Settle on the input prompt (timeouts are in milliseconds)
agent-tui wait "❯" --session "$SID" --timeout 10000

# 4. Confirm starting model in the status zone
agent-tui screenshot --session "$SID" --strip-ansi | grep -q "claude-haiku-4-5"

# 5. Open the model picker
agent-tui type "/model" --session "$SID"
agent-tui press Enter --session "$SID"
agent-tui wait "Pick a model" --session "$SID"

# 6. Pick claude-opus-4-7 by typing then submitting
agent-tui type "opus" --session "$SID"
agent-tui press Enter --session "$SID"

# 7. Wait for the picker to close and assert the status zone updated
agent-tui wait --stable --session "$SID"
agent-tui screenshot --session "$SID" --strip-ansi | grep -q "claude-opus-4-7" \
    && echo "PASS: model switched" \
    || (echo "FAIL: status did not update"; agent-tui screenshot --session "$SID"; exit 1)

# 8. Always kill
agent-tui kill --session "$SID"
```

Run that from the agent's `bash` tool. The `grep -q` lines are the assertions; everything else is choreography.

## Common mistakes

| Mistake | Fix |
|---|---|
| Forgetting `--session $SID` after spawning | Pass it on every command; "most recent" is brittle when tests run in parallel |
| `agent-tui type` on multi-line text | Each `\n` submits a turn; use the per-line + `Alt+Enter` recipe (see Multi-line input gotcha) |
| `agent-tui press Ctrl+C` to clear input | Kills glue. Use `Escape` or backspace instead |
| Using `agent-tui run --env KEY=value` | Not implemented in v1.0.1 despite upstream README; set env in the calling shell |
| Acting on a streaming screen | `wait --stable` first; assert after |
| Asserting on streamed LLM text | Assert on status zone, input echo, or structured output instead |
| Leaving `GLUE_HOME` unset | Tests become non-deterministic across machines; always `export GLUE_HOME=$(mktemp -d)` |
| Sleep loops (`sleep 2 && screenshot`) | Use `wait` with a condition and a timeout; sleeps are slower *and* flakier |
| Killing only on success | Wrap with `trap "agent-tui kill --session $SID" EXIT` so failures clean up |
| Forgetting `--strip-ansi` for grep | ANSI escape codes break naive substring matching |
| Tests run before glue is built | `dart compile exe bin/glue.dart -o glue` and put it on `PATH`, or use `dart run bin/glue.dart` (slower startup) |

## Quick reference

| Action | Command |
|---|---|
| Start daemon | `agent-tui daemon start` |
| Spawn glue, get id | `agent-tui run --format json glue \| jq -r .session_id` |
| Wait for prompt | `agent-tui wait "❯" --session $SID --timeout 10000` (ms) |
| Wait for stability | `agent-tui wait --stable --session $SID` |
| Wait for text + assert | `agent-tui wait "expected" --assert --session $SID` |
| Screenshot (clean) | `agent-tui screenshot --session $SID --strip-ansi` |
| Screenshot as JSON | `agent-tui screenshot --format json --session $SID` |
| Type literal text | `agent-tui type "text" --session $SID` |
| Press a key | `agent-tui press Enter --session $SID` |
| Press chord | `agent-tui press Ctrl+C --session $SID` (warning: exits glue) |
| Insert literal newline in glue input | `agent-tui press Alt+Enter --session $SID` |
| Cancel an overlay | `agent-tui press Escape --session $SID` |
| Kill session | `agent-tui kill --session $SID` |
| List leaked sessions | `agent-tui sessions` |

## Further reading

- Upstream `agent-tui` skill (generic primitives, full CLI atlas): <https://github.com/pproenca/agent-tui/blob/master/skills/agent-tui/SKILL.md>
- Glue's TUI architecture (zones, renderer, overlays): see `cli/lib/src/runtime/`, `cli/lib/src/ui/`, `cli/lib/src/terminal/`, and the architecture notes in `CLAUDE.md`.
