# Wait Conditions

agent-tui's `wait` use case is the most directly portable idea in the
project. It defines three observable conditions that cover almost every
"wait for the program to do X" situation an agent encounters.

## The three conditions

| Condition    | Holds when                                                      | Use it for                                            |
| ------------ | --------------------------------------------------------------- | ----------------------------------------------------- |
| `Text(s)`    | `screen_text().contains(s)`                                     | Wait for a label, prompt, or completion message       |
| `TextGone(s)`| `!screen_text().contains(s)`                                    | Wait for a "Loading…" / spinner / "Saving…" to vanish |
| `Stable`     | The screen hash hasn't changed for N consecutive samples        | "Whatever the program was doing, it's done now"       |

All three operate on the trimmed plain-text screenshot — no styling, no
cursor, no scrollback. That is deliberate: text containment is robust
against color changes, and an agent doesn't usually care what the
spinner glyph is, just that it stopped.

## Defaults that work

The defaults agent-tui ships with are non-obvious but well-tuned:

- **Poll interval: 50 ms.** Short enough that a fast TUI feels
  responsive, long enough that polling itself doesn't dominate CPU.
- **Stable consecutive samples: 3.** With a 50 ms interval that's a
  150 ms quiet window. Three samples (not two) catches programs that
  briefly pause mid-render.
- **Default condition: `Stable`** if no `text` argument is given, else
  `Text(text)`. So `wait` on its own means "wait until the screen
  settles" and `wait "foo"` means "wait until 'foo' appears."
- **Returns `{found, elapsed_ms}` either way** — timing out is not an
  error condition. Callers decide whether to escalate. The CLI exposes
  `--assert` to flip a non-found result into a non-zero exit.

## Stable detection by hash

The stability check is structurally simple — worth lifting whole into
Glue:

```rust
fn add_hash(&mut self, screen: &str) -> bool {
    let mut hasher = DefaultHasher::new();
    screen.hash(&mut hasher);
    let hash = hasher.finish();

    self.last_hashes.push_back(hash);
    if self.last_hashes.len() > self.required_consecutive {
        self.last_hashes.pop_front();
    }
    if self.last_hashes.len() >= self.required_consecutive {
        let first = self.last_hashes[0];
        self.last_hashes.iter().all(|&h| h == first)
    } else {
        false
    }
}
```

A `VecDeque` of the last N hashes; "stable" means all entries are
identical. No diffing, no token-aware comparisons, just `Hasher` over
the trimmed screen string. Fast enough to run at 50 ms intervals
indefinitely.

The Dart equivalent would be `Object.hash(screenText)` accumulated in a
small `ListQueue`. ~15 lines.

## Subscription-based polling

The wait loop doesn't actually `sleep(50ms)` between polls. It
subscribes to a `StreamWaiter` notifier off the session's PTY pump and
calls `subscription.wait(Some(remaining.min(50ms)))`. That means:

- If the program emits any output, the wait loop wakes immediately and
  re-checks the condition.
- If it stays quiet, the loop wakes at the 50 ms cap.
- If the deadline approaches, the wait shrinks to fit.

So latency under change is approximately the channel-wakeup cost
(microseconds), not the poll interval. The poll interval is a safety
floor for the no-output case, not a typical wait.

This is a better pattern than fixed-interval polling and worth
copying for any "wait for state change" loop in Glue. The Dart shape
would be a `Completer` per pending wait, completed by the read pump
whenever new bytes land — but capped by a `Timer` so the no-data case
still progresses.

## Why `text` not `regex`

The condition vocabulary is deliberately not regex. Every public
example uses literal substring containment. The argument:

- LLM-generated patterns are easy to get subtly wrong (`.` vs `\.`,
  greedy quantifiers, anchoring).
- Substring containment is unambiguous, fast, and obvious in error
  messages.
- If you really need a pattern, use `Stable` first then a
  post-condition check on the screenshot.

For Glue, this is the right call. A `wait_for_text(s)` tool that an
LLM can invoke is reliable; a `wait_for_regex(p)` tool isn't.

## Combining waits

agent-tui doesn't compose conditions internally — there's no `and` or
`or`. The skill recommends a sequence:

```text
1. press Tab
2. wait --stable           # screen settled
3. wait "Submit" --assert  # post-condition holds
```

This composes cleanly because each step is independent and produces a
fresh screenshot. The agent (LLM) is the composition layer, not the
tool. Worth keeping that boundary in any Glue equivalent.

## Where this lives in agent-tui

| Concern                | File                                                                       |
| ---------------------- | -------------------------------------------------------------------------- |
| Condition types        | `cli/crates/agent-tui-domain/src/domain/types.rs` (`WaitConditionType`)    |
| Parsing + check logic  | `cli/crates/agent-tui-usecases/src/usecases/wait_condition.rs`             |
| Wait loop              | `cli/crates/agent-tui-usecases/src/usecases/wait.rs`                       |
