# How to Build Your Own AI Coding Agent -- Lessons from 43 Real-World Tools

> A practical playbook distilled from analyzing the system prompts, tool schemas, and architectures of 43 production coding agents -- including Claude Code, Cursor, Codex CLI, Gemini CLI, OpenHands, Manus, Devin, Crush, Serena, CrewAI, and 33 others.

---

## Table of Contents

1. [System Prompt Design](#1-system-prompt-design)
2. [Tool Definition Patterns](#2-tool-definition-patterns)
3. [Edit Format Selection](#3-edit-format-selection)
4. [Safety and Trust](#4-safety-and-trust)
5. [Multi-Agent Architecture](#5-multi-agent-architecture)
6. [Context Management](#6-context-management)
7. [User Customization](#7-user-customization)
8. [Mode Design](#8-mode-design)
9. [Common Mistakes](#9-common-mistakes)

---

## 1. System Prompt Design

### 1.1 The Universal Structure

Every competent coding agent prompt follows the same structural skeleton, regardless of whether it is 80 lines (Goose) or 1,450 lines (v0). The order matters because LLMs attend differently to different positions, and because KV-cache optimization (see Section 6) rewards stable prefixes.

```
1. Identity          -- Who the agent is
2. Capabilities      -- What it can do
3. Constraints       -- What it must never do
4. Tone/Style        -- How it communicates
5. Workflow          -- How it approaches tasks
6. Tool Usage Rules  -- How to call tools correctly
7. Safety Rules      -- Destructive action constraints
8. Domain Rules      -- Domain-specific guidelines (git, testing, etc.)
9. Dynamic Context   -- Environment info, user rules, memory (appended at runtime)
```

### 1.2 Identity: The Opening Statement

Every single one of the 43 tools opens with an identity statement. The pattern is:

```
You are [Name], [a/an] [superlative] [role]. [Attribution].
```

Examples from production:

- Claude Code: `"You are Claude Code, Anthropic's official CLI for Claude."`
- Crush: `"You are Crush, a powerful AI Assistant that runs in the CLI."`
- Codex CLI: `"You are a coding agent running in the Codex CLI, a terminal-based coding assistant."`
- Manus: `"You are Manus, an AI agent created by the Manus team."`
- SWE-agent: `"You are a helpful assistant."` (minimal -- intelligence lives in tooling)

**What works:** A concise identity that sets scope. The identity line is cheap (one sentence) and provides a frame for everything that follows. Open-source tools tend toward humble phrasing ("helpful assistant"); commercial products use bolder claims ("world's first agentic coding assistant" -- Windsurf). Neither is objectively better, but the identity must be consistent with the agent's actual capabilities.

**Anti-pattern:** Making claims the agent cannot back up. An agent with 5 tools should not claim to be "the world's most advanced AI developer."

### 1.3 Capabilities Block

After identity, enumerate what the agent can do. This serves two purposes: it sets user expectations and it primes the model to use those capabilities.

```
Your capabilities:
- Read, search, and modify files in the user's project
- Execute shell commands with user approval
- Search the web for documentation and reference material
- Manage tasks with a structured todo list
- Spawn sub-agents for parallel work
```

Manus provides one of the clearest examples:

```
System capabilities:
- Communicate with users through message tools
- Access a Linux sandbox environment with internet connection
- Use shell, text editor, browser, and other software
- Write and run code in Python and various programming languages
- Independently install required software packages and dependencies via shell
- Deploy websites or applications and provide public access
```

### 1.4 Constraints: The Critical Rules Block

This is the most important section. Models are more reliable when they have explicit, enumerated constraints. Crush demonstrates the best pattern with a dedicated `<critical_rules>` XML section containing 13 numbered rules. The XML tags help the model parse section boundaries.

**Template for critical constraints:**

```
<critical_rules>
These rules override everything else. Follow them strictly:

1. READ BEFORE EDITING: Never edit a file you haven't read in this conversation.
2. NEVER COMMIT unless the user explicitly asks.
3. NEVER PUSH to remote unless explicitly asked.
4. TEST AFTER CHANGES: Run tests after each modification.
5. BE CONCISE: Keep text output under 4 lines unless explaining complex changes.
6. USE EXACT MATCHES: Match text exactly including whitespace for edits.
7. NO URL GUESSING: Only use URLs from the user or local files.
8. SECURITY FIRST: Never introduce OWASP top-10 vulnerabilities.
9. TOOL CONSTRAINTS: Only use documented tools. Never attempt tools that don't exist.
10. NO SECRETS IN OUTPUT: Never expose credentials, API keys, or tokens.
</critical_rules>
```

**Why XML tags?** Claude Code, Crush, Cursor, Amazon Q, and Devin all use XML tags to delimit sections. XML provides clear section boundaries that models parse reliably. Other tools use markdown headers (`##`), which also works. The key is consistent section delimiters -- do not mix conventions.

### 1.5 Tone and Style

Three patterns dominate:

**Pattern A: Extreme brevity for CLI tools.**
Claude Code: "Short and concise." Crush: "Under 4 lines of text." OpenCode: "Fewer than 4 lines." Gemini CLI: "Fewer than 3 lines." This works because terminal output is consumed differently from IDE panels.

**Pattern B: Anti-sycophancy directives.**
This is a strong convergent trend across 6+ tools:

- Claude Code: `"Avoid using over-the-top validation or excessive praise."`
- Crush: `"No preamble ('Here's...', 'I'll...'). No postamble ('Let me know...', 'Hope this helps...')"`
- Augment Code: `"Don't start your response by saying a question or idea was good, great, fascinating..."`
- Roo Code: `"You are STRICTLY FORBIDDEN from starting your messages with 'Great', 'Certainly', 'Okay', 'Sure'"`

**Pattern C: Professional objectivity.**
Claude Code's formulation is the gold standard:

```
Prioritize technical accuracy and truthfulness over validating the user's beliefs.
Focus on facts and problem-solving, providing direct, objective technical info
without any unnecessary superlatives, praise, or emotional validation.
```

**Practical guidance:** If your agent runs in a CLI, enforce 2-4 line responses. Ban sycophantic openers. Ban emojis unless the user requests them. Ban time estimates (Claude Code explicitly forbids these). These rules produce dramatically better output than leaving style unspecified.

### 1.6 Annotated System Prompt Template

Here is a minimal but complete template you can use as a starting point. It incorporates the patterns that appear most frequently across all 43 tools:

```markdown
You are [AgentName], a coding assistant built by [Organization].

You help users with software engineering tasks: writing code, debugging, refactoring,
explaining code, running tests, and managing git workflows.

<critical_rules>

1. NEVER edit a file you haven't read in this conversation.
2. NEVER commit or push unless the user explicitly asks.
3. NEVER introduce security vulnerabilities (OWASP top-10).
4. NEVER expose credentials, API keys, or tokens in output.
5. NEVER guess URLs -- only use those from the user or local files.
6. ALWAYS run tests after making changes when a test suite exists.
7. ALWAYS prefer editing existing files over creating new ones.
8. ONLY use documented tools. Do not attempt tools that don't exist.
   </critical_rules>

<tone>
- Keep responses concise (under 4 lines for simple answers).
- No sycophantic openers ("Great question!", "Certainly!").
- No filler closers ("Let me know if you need anything else!").
- No time estimates. Focus on what needs to be done, not how long it takes.
- Use markdown formatting. Code blocks with language tags.
- Only use emojis if the user requests them.
</tone>

<workflow>
For every coding task:
1. Search the codebase to understand the current state.
2. Read relevant files before proposing changes.
3. Plan changes if the task requires multiple steps (use the todo tool).
4. Make changes using the appropriate edit tools.
5. Run tests to verify the changes work.
6. Provide a brief summary of what changed and why.
</workflow>

<tool_usage>

- Prefer specialized tools over shell commands for file operations.
- Call multiple independent tools in parallel when possible.
- Use the search/grep tool instead of running grep in a shell.
- Use the read tool instead of cat/head/tail in a shell.
- Use the edit tool instead of sed/awk in a shell.
  </tool_usage>

<environment>
Working directory: {{working_dir}}
Platform: {{platform}}
Date: {{today}}
Git repo: {{is_git_repo}}
</environment>

{{#if user_rules}}
<user_rules>
{{user_rules}}
</user_rules>
{{/if}}
```

---

## 2. Tool Definition Patterns

### 2.1 Schema Format Selection

The 43 tools use five distinct formats for defining tools. Your choice depends on which LLM you target and how complex your tools are.

| Format                                    | Used By                                                  | Best For                                              |
| ----------------------------------------- | -------------------------------------------------------- | ----------------------------------------------------- |
| **JSON Schema (OpenAI function calling)** | Gemini CLI, Codex CLI, OpenHands, Manus, Replit, Lovable | OpenAI/Anthropic API with native function calling     |
| **XML command tags**                      | Cline, Amazon Q, Devin, Junie, Sourcegraph Cody          | Models that parse XML well (Claude, older GPTs)       |
| **Inline text descriptions**              | Warp, Aider, gp-nvim                                     | Simple tools, models without function calling         |
| **Hybrid (JSON + inline docs)**           | Claude Code, Cursor                                      | When you need schema validation AND detailed guidance |
| **Python-syntax calls**                   | Google Jules                                             | Novel approach, only Jules uses it                    |

**Recommendation:** Use JSON Schema as your primary format. It is supported natively by OpenAI, Anthropic, Google, and most other providers. Add detailed descriptions and usage notes in the `description` field. If your model does not support native function calling, fall back to ReAct format (as CrewAI does) or XML tags.

### 2.2 Anatomy of a Good Tool Definition

Here is a template based on the patterns that produce the best results across all 43 tools:

```json
{
  "name": "edit_file",
  "description": "Performs exact string replacement in a file.\n\n## When to use\n- Modifying existing code in a file\n- Fixing bugs, adding features, refactoring\n\n## When NOT to use\n- Creating new files (use write_file instead)\n- Reading files (use read_file instead)\n\n## Requirements\n- You MUST read the file before editing it\n- The old_string must be unique in the file\n- The old_string must match EXACTLY, including whitespace\n\n## Common mistakes\n- Editing without reading first (will fail)\n- Approximate text matches (will fail)\n- Wrong indentation (will fail)",
  "parameters": {
    "type": "object",
    "properties": {
      "file_path": {
        "type": "string",
        "description": "Absolute path to the file to modify"
      },
      "old_string": {
        "type": "string",
        "description": "The exact text to find and replace. Must be unique in the file."
      },
      "new_string": {
        "type": "string",
        "description": "The replacement text. Must differ from old_string."
      },
      "replace_all": {
        "type": "boolean",
        "description": "If true, replace ALL occurrences. Default false.",
        "default": false
      }
    },
    "required": ["file_path", "old_string", "new_string"]
  }
}
```

**Key patterns from the best tool descriptions:**

1. **"When to use / When not to use" sections.** Amazon Q, Claude Code, and Augment Code all do this. It dramatically reduces tool misuse.

2. **Negative examples.** Tell the model what will fail:
   - Crush: `"Never attempt 'apply_patch' or 'apply_diff' -- they don't exist"`
   - Cursor: `"There is no apply_patch CLI available in terminal"`
   - Warp: `"NEVER use terminal commands to read files"`

3. **Prerequisite declarations.** Claude Code's Edit tool: `"You must use your Read tool at least once in the conversation before editing."` This is enforced at the tool level -- the tool returns an error if the precondition is not met.

4. **Detailed parameter descriptions.** Do not just type `"path": "string"`. Write `"Absolute path to the file. Must not be relative."` Every ambiguity in parameter descriptions becomes a failure mode in production.

### 2.3 Tool Description Length

Tool descriptions should be as long as they need to be. Claude Code's Bash tool description is 40+ lines. Its Read tool is 15+ lines. The Grep tool is 10+ lines. Short descriptions are fine for simple tools; complex tools need detailed guidance.

The general rule from analyzing all 43 tools: **simple tools (ls, glob) need 2-5 lines; complex tools (edit, bash, browser) need 15-40 lines.**

### 2.4 How Many Tools?

The average across all 43 tools is approximately 15. But the range is enormous:

- **Minimum useful set:** 5-6 tools (read, write/edit, search, shell, web) -- this is Warp's approach
- **Full-featured agent:** 15-20 tools -- Claude Code, Gemini CLI, Crush
- **Autonomous cloud agent:** 25-30 tools -- Devin, Manus, Windsurf

**Start with 6 core tools:** read_file, edit_file, write_file, search (grep), list_files (glob), run_shell. Add tools as you encounter gaps. Every tool you add increases the model's decision space and the chance of misuse -- add tools deliberately.

### 2.5 The Parallel Tool Calls Pattern

Six of the most mature tools (Cursor, Claude Code, Gemini CLI, Codex CLI, OpenCode, Lovable) all strongly emphasize parallel tool calls. Cursor has an entire `<maximize_parallel_tool_calls>` section. Lovable calls it a "cardinal rule."

Add this to your system prompt:

```
You can call multiple tools in a single response. If you intend to call multiple
tools and there are no dependencies between them, make all independent tool calls
in parallel. However, if one tool call depends on the result of another, call them
sequentially. Never use placeholders or guess missing parameters.
```

This single instruction can reduce task completion time by 30-50% for multi-file operations.

---

## 3. Edit Format Selection

This is the hardest unsolved problem in coding agents. After years of iteration across 43 tools, there is still no consensus. There are 12+ distinct approaches, and Aider alone supports 6 of them.

### 3.1 The Twelve Formats

| Format                           | Used By                         | Mechanism                                          |
| -------------------------------- | ------------------------------- | -------------------------------------------------- |
| **1. SEARCH/REPLACE blocks**     | Aider, Warp, Crush, avante-nvim | Find exact text, replace with new text             |
| **2. Unified diff**              | Aider, Mentat                   | Standard `--- a/file` / `+++ b/file` / `@@` format |
| **3. V4A patch**                 | Aider                           | Variant of unified diff optimized for Claude       |
| **4. apply_patch**               | Codex CLI, Cursor               | Custom diff-like format with hunk headers          |
| **5. str_replace_editor**        | OpenHands, Augment, Replit      | JSON tool with old/new string params               |
| **6. old_string/new_string**     | Claude Code, Amazon Q           | Same as #5 but with different parameter names      |
| **7. Whole file rewrite**        | Aider, Continue                 | Output the entire file with changes                |
| **8. ReplacementChunks**         | Windsurf                        | Proprietary chunk-based format                     |
| **9. Block parser**              | Mentat                          | `@@start`/`@@code`/`@@end` markers                 |
| **10. JSON parser**              | Mentat                          | Structured JSON edit operations                    |
| **11. Git merge markers**        | Jules                           | `<<<<<<< SEARCH` / `>>>>>>> REPLACE`               |
| **12. Symbol-level replacement** | Serena                          | `replace_symbol_body(name_path="MyClass/method")`  |

### 3.2 Decision Matrix

| Factor                     | Best Format(s)                                  | Rationale                                                          |
| -------------------------- | ----------------------------------------------- | ------------------------------------------------------------------ |
| **Simplest to implement**  | old_string/new_string (#6)                      | One tool, no parser needed, exact match validation                 |
| **Most reliable for LLMs** | old_string/new_string (#6), SEARCH/REPLACE (#1) | Exact string match is unambiguous; LLMs struggle with line numbers |
| **Best for large changes** | Whole file rewrite (#7), apply_patch (#4)       | Avoids the "unique match" problem for big refactors                |
| **Most token-efficient**   | Unified diff (#2), apply_patch (#4)             | Only transmits changed lines + context                             |
| **Best for refactoring**   | Symbol-level (#12)                              | Understands code structure; no text matching needed                |
| **Best for new files**     | Whole file write                                | No existing content to match against                               |

### 3.3 Practical Recommendation

**Start with old_string/new_string replacement** (format #6). This is what Claude Code, Amazon Q, and Crush use. It works because:

1. **It is unambiguous.** The model provides the exact text to find and the exact replacement. If the text is not found, the edit fails with a clear error.
2. **It enforces reading first.** You can require that the file was read before editing (Claude Code does this).
3. **It catches errors immediately.** If the model hallucinates content that is not in the file, the exact match fails.
4. **It is simple to implement.** You need one string search and one replacement.

The main failure mode is non-unique matches. When `old_string` appears multiple times in the file, the edit is ambiguous. Claude Code handles this by failing and asking for more context. Crush handles it by requiring 3-5 lines of surrounding context.

**Add whole file write as a second tool** for creating new files and for rare cases where the entire file needs replacement.

**If you need maximum token efficiency**, consider adding apply_patch (format #4) or unified diff as an advanced option. But start simple.

### 3.4 The Whitespace Problem

Every tool that uses exact matching has extensive whitespace guidance. Crush dedicates an entire `<whitespace_and_exact_matching>` section to this. The reason: LLMs frequently get whitespace wrong. Tabs vs. spaces, indentation depth, trailing whitespace, blank lines -- all are failure points.

**Mitigation strategies from production tools:**

1. Return line numbers with file reads (Claude Code uses `cat -n` format), so the model can see exact indentation
2. Require 3-5 lines of context around the edit target (Crush, Warp)
3. Fail loudly on non-matches with a clear error message (Claude Code, OpenHands)
4. Provide a "fuzzy match" fallback that shows the closest match when exact match fails

### 3.5 The Future: Symbol-Level Editing

Serena represents the most innovative approach. Instead of matching text, it operates on named symbols:

```
replace_symbol_body(
  name_path="MyClass/my_method",
  new_body="def my_method(self):\n    return 42"
)
```

This sidesteps the entire text-matching problem. The language server knows where `MyClass.my_method` is defined, so there is no ambiguity. The trade-off is complexity: you need a running LSP server for each supported language.

If you are building a serious coding agent, consider Serena's MCP integration -- it can add LSP-based editing to any agent that supports the Model Context Protocol.

---

## 4. Safety and Trust

### 4.1 The Three Safety Models

The 43 tools fall into three distinct safety philosophies:

| Model                        | Tools                                          | Mechanism                                             |
| ---------------------------- | ---------------------------------------------- | ----------------------------------------------------- |
| **Prompt constraints**       | Claude Code, Crush, Cursor, Augment, Codex CLI | Rules in the system prompt that the model must follow |
| **Runtime sandboxing**       | SWE-agent, Gemini CLI, Devin, Manus, Jules     | Docker containers, VMs, or OS-level sandboxing        |
| **User approval per action** | Cline, Roo Code, Kilo Code, codecompanion-nvim | Every tool call requires user confirmation            |

**In practice, use all three.** Prompt constraints are your first line of defense. Sandboxing catches what prompts miss. User approval provides a final safety net for destructive actions.

### 4.2 Git Safety Protocol

Claude Code has the most comprehensive git safety protocol of any tool examined. It is the template you should follow. Here are the 11 constraints, each addressing a real failure mode:

```
Git Safety Protocol:
1. NEVER update the git config
2. NEVER run destructive git commands (push --force, reset --hard, checkout .,
   restore ., clean -f, branch -D) unless the user explicitly requests them
3. NEVER skip hooks (--no-verify, --no-gpg-sign) unless explicitly asked
4. NEVER force-push to main/master -- warn the user if they request it
5. CRITICAL: Always create NEW commits rather than amending. When a pre-commit
   hook fails, the commit did NOT happen, so --amend would modify the PREVIOUS
   commit, potentially destroying work. After hook failure: fix, re-stage, NEW commit.
6. When staging files, prefer specific files over "git add -A" or "git add ."
   (prevents accidentally staging .env, credentials, large binaries)
7. NEVER commit unless the user explicitly asks
8. NEVER push unless the user explicitly asks
9. NEVER use interactive git flags (-i) -- they require TTY input
10. If there are no changes, do not create an empty commit
11. Use HEREDOC for commit messages to preserve formatting
```

Rule #5 (the amend-after-hook-failure footgun) is unique to Claude Code and addresses a subtle, real bug that no other tool catches. If your agent runs pre-commit hooks and one fails, the commit was never created. If the agent then retries with `--amend`, it modifies the _previous_ commit (which may be the user's work). Always create a new commit after fixing hook failures.

### 4.3 File Modification Safety

The "read before edit" rule appears in 12+ tools. Implementation:

```
1. Maintain a set of files that have been read in the current conversation.
2. When the edit tool is called, check if the target file is in the read set.
3. If not, return an error: "You must read this file before editing it."
4. After a successful edit, keep the file in the read set (no need to re-read).
5. If the file is modified externally (e.g., by a shell command), invalidate the entry.
```

Cursor adds a **staleness window**: "If you have not opened with read_file within your last five messages, read the file again before attempting to apply a patch." This prevents edits based on stale context.

### 4.4 Command Execution Safety

**Banned command lists.** Crush maintains an explicit blocklist: `curl, wget, ssh, sudo, vi, nano` and package managers. SWE-agent and avante-nvim do the same. The rationale: `curl` can exfiltrate data, `sudo` can escalate privileges, interactive editors hang the agent.

**Non-interactive mandate.** SWE-agent, Cline, Warp, and Devin all explicitly ban interactive commands (vi, nano, less, python REPL). Add to your prompt:

```
NEVER run interactive commands that require user input (vi, nano, less, more,
top, htop, python without -c, irb, node without -e). These will hang.
Always use --no-pager flags with git commands. Set PAGER=cat if needed.
```

**Command classification.** Amazon Q classifies every command as `readOnly`, `mutate`, or `destructive`. This is a good framework:

- `readOnly`: ls, cat, grep, git status, git log -- always safe
- `mutate`: file edits, git add, npm install -- need the read-before-edit check
- `destructive`: rm -rf, git push --force, DROP TABLE -- require explicit user approval

### 4.5 The Think-Before-Acting Pattern

Devin requires a `<think>` tag before git operations and mode transitions. Claude Code and avante-nvim have dedicated think/reasoning tools. Serena has `think_about_*` tools.

This pattern is useful for high-stakes operations. Add a "think" step to your tool flow:

```
Before any destructive or irreversible action:
1. Use the think tool to analyze the action's consequences
2. Verify the action matches what the user requested
3. Check that you have a recovery path if the action fails
4. Only then proceed with the action
```

### 4.6 Network Safety

```
Network Safety Rules:
- NEVER fabricate or guess URLs. Only use URLs from the user or from local files.
- Use a dedicated web_fetch tool (not curl in shell) to prevent shell injection.
- NEVER exfiltrate data: do not send file contents, secrets, or code to external URLs.
- For GitHub operations, use the gh CLI (not raw API calls with curl).
- Block access to credential files (.env, .aws/credentials, etc.) in web contexts.
```

Replit has a unique pattern worth adopting: an `ask_secrets` tool that lets the user provide API keys through a secure channel rather than having them appear in conversation history.

### 4.7 Logits Masking vs. Dynamic Tool Removal

Manus uses **logits masking** to constrain the action space during token decoding, rather than dynamically adding/removing tools from the prompt. This is more efficient (no prompt changes, better KV-cache hits) and more reliable (the model physically cannot select a masked-out tool). If you have control over the inference stack, this is the superior approach. If you are using a hosted API, remove tools from the function definition list instead.

---

## 5. Multi-Agent Architecture

### 5.1 When to Use Sub-Agents

Not every coding agent needs multiple agents. Of the 43 tools surveyed:

- 18 are single-agent (Warp, Aider, Windsurf, Lovable, etc.)
- 25 use some form of multi-agent or multi-mode design

**Use sub-agents when:**

- Tasks can be parallelized (e.g., editing different files simultaneously)
- Different capabilities require different tool sets (e.g., browser vs. code editor)
- Context windows are a constraint (sub-agents get fresh context)
- Different tasks benefit from different models (use a cheap model for search, an expensive model for editing)

**Stay single-agent when:**

- Your tasks are sequential and interdependent
- You want simplicity and debuggability
- Your context window is large enough for the typical task

### 5.2 The Four Multi-Agent Patterns

**Pattern 1: Sub-agent delegation (most common).**
Used by: Claude Code, Codex CLI, Gemini CLI, Crush, OpenCode, gptme.

The main agent spawns specialized sub-agents via a Task tool. Each sub-agent gets a focused prompt, a restricted tool set, and returns results to the parent.

```
Main Agent
  |-- Task("Search for authentication code") -> Explore Agent (read-only tools)
  |-- Task("Plan the implementation") -> Plan Agent (read-only tools)
  |-- Task("Run the test suite") -> Bash Agent (shell-only tools)
```

Claude Code's implementation:

```json
{
  "name": "Task",
  "parameters": {
    "description": "Short description (3-5 words)",
    "prompt": "The task for the agent to perform",
    "subagent_type": "Explore | Plan | Bash | general-purpose"
  }
}
```

**Pattern 2: Mode switching.**
Used by: Roo Code, Kilo Code, Continue, Kiro, avante-nvim.

Instead of spawning separate agents, the single agent switches between modes. Each mode has different tool access and behavioral rules.

```
Agent (Code mode) -- full tool access
Agent (Architect mode) -- read-only tools, focus on planning
Agent (Ask mode) -- no tools, conversational only
Agent (Debug mode) -- focus on diagnostics and test running
```

This is simpler than sub-agents because there is one context window and one conversation. It is better for tasks where the agent needs to carry context across phases.

**Pattern 3: Pipeline architecture.**
Used by: Plandex, Kiro, Replit Agent.

Distinct agent personas for each development phase. The output of one phase becomes the input of the next.

```
Phase 1: Requirements (Spec Agent) -> requirements.md
Phase 2: Design (Architect Agent) -> design.md
Phase 3: Implementation (Coder Agent) -> code changes
Phase 4: Verification (Tester Agent) -> test results
```

Plandex is the most elaborate: Context -> Planning -> Implementation -> Verification, with separate prompts for each phase and ~800 lines of total prompt across all phases.

**Pattern 4: Orchestrator with ledger.**
Used by: AutoGen (MagenticOne), Claude Flow.

A meta-agent maintains a structured ledger tracking facts, progress, and next-speaker selection. This is the most sophisticated pattern but also the most complex to implement.

AutoGen's MagenticOne ledger:

```json
{
  "facts": ["The repo uses TypeScript", "Tests are in __tests__/"],
  "verified_claims": ["Build passes with npm run build"],
  "unverified_claims": ["The auth module might use JWT"],
  "current_progress": "Explored the codebase, identified 3 files to modify",
  "next_speaker": "coder_agent",
  "next_speaker_rationale": "We have enough context to start implementation"
}
```

### 5.3 Sub-Agent Design Rules

From analyzing Claude Code, Codex CLI, and Gemini CLI sub-agents:

1. **Give each sub-agent a clear identity.** Claude Code's Explore agent: "You are a file search specialist." Not "You are a helpful assistant."

2. **Restrict tool access per sub-agent.** The Explore agent gets read-only tools. The Bash agent gets only the shell tool. The Plan agent can search but cannot edit. This prevents sub-agents from exceeding their scope.

3. **Declare read-only constraints explicitly.** Claude Code's sub-agent prompt:

```
=== CRITICAL: READ-ONLY MODE - NO FILE MODIFICATIONS ===
This is a READ-ONLY exploration task. You are STRICTLY PROHIBITED from:
- Creating new files
- Modifying existing files
- Deleting files
```

4. **Use cheaper/faster models for simple sub-agents.** Claude Code runs its Explore agent on Haiku (fast, cheap) while the main agent runs on Opus. This saves cost and reduces latency.

5. **Keep sub-agent prompts short.** Sub-agents have focused scope and should have focused prompts. Claude Code's Bash agent prompt is 10 lines. Its Explore agent is 25 lines. Compare to the main agent at 700+ lines.

### 5.4 Delegation Tools

Two patterns for delegation:

**spawn/close pattern** (Codex CLI):

```
spawn_agent(name="auth_agent", prompt="Implement JWT authentication")
// ... later ...
close_agent(name="auth_agent")
```

**Task tool pattern** (Claude Code, Crush, OpenCode):

```
Task(prompt="Search for all files related to authentication", subagent_type="Explore")
```

The Task pattern is simpler and works well for fire-and-forget subtasks. The spawn/close pattern gives more control over agent lifecycle and is better for long-running parallel work.

**CrewAI's delegation model** is worth studying if you build multi-agent teams. It provides two delegation tools:

- `delegate_work(task, agent, context)` -- hand off a task to another agent
- `ask_question(question, agent, context)` -- ask another agent for information

This peer-to-peer delegation is more flexible than the hierarchical parent/child model.

---

## 6. Context Management

### 6.1 The Prompt Assembly Pipeline

Modern agents do not use static system prompts. They assemble prompts dynamically from multiple sources. Claude Code uses ~15 composable functions. Gemini CLI has 10+ subsections controlled by feature flags. Serena uses Jinja2 templates with context and mode layers.

**A practical assembly pipeline:**

```
1. Static core prompt (identity, constraints, workflow) -- STABLE, cacheable
2. Tool definitions (JSON schemas)                      -- STABLE, cacheable
3. Environment context (OS, cwd, git status, date)      -- per-session
4. User rules (.agentrules, CLAUDE.md, etc.)            -- per-project
5. Memory (persistent learnings from past sessions)     -- per-project
6. Conversation history                                 -- per-turn
7. Dynamic context (search results, file contents)      -- per-turn
```

**Why order matters: KV-cache optimization.** Manus's engineering blog explains that cached tokens cost 0.30 USD/MTok vs 3.00 USD/MTok uncached -- a 10x difference. Stable content should come first (static prompt, tool definitions) so it can be cached across turns. Dynamic content should be appended at the end. This is why Claude Code, Gemini CLI, and Manus all put environment info and user rules at the end of the system prompt, not the beginning.

**Rule: Never change the prefix of your system prompt between turns.** Move all dynamic content to the end.

### 6.2 Environment Context Block

Every serious agent injects runtime environment information. The standard format (used by Claude Code, Crush, OpenCode, avante-nvim):

```xml
<env>
Working directory: /home/user/my-project
Platform: darwin (macOS)
OS version: Darwin 24.6.0
Date: 2026-02-13
Git repo: Yes
Git branch: feature/auth
Shell: /bin/zsh
</env>
```

This seems trivial but is surprisingly important. Without the date, the model uses its training cutoff date when searching for documentation. Without the platform, it suggests Linux commands on macOS. Without the git branch, it cannot reason about branching.

### 6.3 Context Window Management

Four strategies from production tools:

**Strategy 1: Automatic summarization.**
Claude Code: "The conversation has unlimited context through automatic summarization." Crush: auto-summarization at configurable thresholds. When the context window fills, older messages are summarized into a compressed format and the originals are discarded.

**Strategy 2: Context checkpointing / compaction.**
Codex CLI and Gemini CLI use "context checkpoints" -- structured XML snapshots that compress the conversation state:

```xml
<context_checkpoint>
  <files_modified>src/auth.ts, src/routes/login.ts</files_modified>
  <current_task>Implementing JWT token refresh</current_task>
  <key_findings>Auth module uses express-jwt middleware</key_findings>
</context_checkpoint>
```

**Strategy 3: Sub-agent offloading.**
Claude Code: "When doing file search, prefer to use the Task tool to reduce context usage." Sub-agents run in their own context window, and only their final result enters the parent's context. This is the most effective strategy for large codebases.

**Strategy 4: Token-efficient reading.**
Serena's core philosophy: "You avoid reading entire files unless absolutely necessary, instead relying on intelligent step-by-step acquisition of information." Using symbol-level reading (get overview first, then read specific function bodies) can reduce context usage by 5-10x compared to reading entire files.

### 6.4 Memory Systems

Seven of the 43 tools now have persistent memory. Here is Claude Code's memory guidelines (the most detailed):

```
## What to save:
- Stable patterns and conventions confirmed across multiple interactions
- Key architectural decisions, important file paths, project structure
- User preferences for workflow, tools, communication style
- Solutions to recurring problems and debugging insights

## What NOT to save:
- Session-specific context (current task details, in-progress work)
- Information that might be incomplete -- verify before saving
- Anything that duplicates existing project documentation
- Speculative or unverified conclusions from reading a single file
```

**Implementation approaches:**

- **File-based** (Claude Code: MEMORY.md, Gemini CLI: save_memory, Serena: write_memory) -- simple, inspectable, user-editable
- **Tool-based** (Windsurf: create_memory, Cursor: update_memory) -- integrated into the tool flow
- **Filesystem-as-memory** (Manus) -- store observations as files, restore via paths
- **Agent-based** (Codex CLI: Memory Writing Agent) -- a separate agent extracts learnings

**Recommendation:** Start with a simple MEMORY.md file that is loaded into the system prompt. Cap it at 200 lines (as Claude Code does). Let the agent write to it with the standard file tools. This gives you persistence, inspectability, and user editability with zero additional infrastructure.

### 6.5 The Todo/Task Tracking Pattern

Task tracking tools have independently appeared in 8+ tools within months of each other: Cursor, Claude Code, Gemini CLI, Codex CLI, OpenHands, Augment Code, avante-nvim, Manus.

The pattern: a structured todo list that the agent maintains throughout the conversation. This serves three purposes:

1. **Planning:** Forces the agent to decompose tasks before starting
2. **Tracking:** Prevents the agent from forgetting steps in long tasks
3. **Visibility:** Shows the user what the agent is doing and how far along it is

Manus takes an interesting variant: instead of a tool, it writes `todo.md` files and recites them to keep objectives in its recent attention span. This "recitation mechanism" mitigates the "lost-in-the-middle" problem where models lose track of their goals during long tasks.

---

## 7. User Customization

### 7.1 The Rules File Ecosystem

The ecosystem has fragmented across 20+ different customization file formats. Here are the major ones and who reads them:

| File                              | Primary Tool    | Also Read By                                |
| --------------------------------- | --------------- | ------------------------------------------- |
| `CLAUDE.md`                       | Claude Code     | codecompanion-nvim, Claude Flow             |
| `.cursorrules`                    | Cursor          | Cline, OpenHands, codecompanion-nvim        |
| `AGENTS.md`                       | Codex CLI       | Goose, OpenHands, Jules, codecompanion-nvim |
| `GEMINI.md`                       | Gemini CLI      | --                                          |
| `.clinerules`                     | Cline           | codecompanion-nvim                          |
| `.windsurfrules`                  | Windsurf        | Cline                                       |
| `.github/copilot-instructions.md` | GitHub Copilot  | --                                          |
| `.kiro/steering/*.md`             | Kiro            | --                                          |
| `.junie/guidelines.md`            | JetBrains Junie | JetBrains Air                               |

**Practical recommendation:** Support at least `CLAUDE.md` and `AGENTS.md` (the two with the strongest organizational backing from Anthropic and OpenAI respectively). Read `.cursorrules` if present (it has the largest installed base). Use a hierarchical model where more specific files override more general ones.

### 7.2 Hierarchical Rules

Claude Code, Gemini CLI, and Codex CLI all use hierarchical rules with directory scoping:

```
~/.config/agent/rules.md        -- Global (applies everywhere)
  > project/AGENT.md            -- Project-level (overrides global)
    > project/src/AGENT.md      -- Directory-scoped (overrides project)
```

**Codex CLI's scoping model (adopted by Jules):**

- AGENTS.md files at any directory level
- The scope of an AGENTS.md file is the entire directory tree rooted at the folder containing it
- More deeply nested files take precedence over less deeply nested files
- Direct user instructions override all AGENTS.md files

**Implementation:**

```python
def load_rules(working_dir: str) -> str:
    rules = []
    # Walk from home to working_dir, collecting rules
    for path in paths_from_home_to_cwd(working_dir):
        for filename in ["AGENT.md", "CLAUDE.md", "AGENTS.md", ".cursorrules"]:
            filepath = os.path.join(path, filename)
            if os.path.exists(filepath):
                rules.append(read_file(filepath))
    # More specific rules come later and take precedence
    return "\n\n".join(rules)
```

### 7.3 What Users Put in Rules Files

From analyzing real-world CLAUDE.md and .cursorrules files, users typically specify:

- **Code style:** "Use 2-space indentation", "Prefer functional style", "Always use TypeScript strict mode"
- **Testing commands:** "Run tests with `npm test`", "Use pytest with -v flag"
- **Architecture notes:** "The API layer is in src/api/, business logic in src/domain/"
- **Workflow preferences:** "Always run lint after editing", "Never auto-commit", "Use conventional commits"
- **Project-specific knowledge:** "We use Supabase for auth", "The database is PostgreSQL"

### 7.4 Skills and Loadable Instructions

A newer pattern from Continue, Gemini CLI, Crush, and Claude Code: user-defined "skills" that can be loaded on demand.

**Continue's model:** Skills are markdown documents stored in `.continue/skills/` that the agent can request when relevant. Skills have four attachment types:

- **Always:** Loaded into every conversation
- **Auto-Attached:** Loaded when a glob pattern matches (e.g., `*.tsx` triggers the React skill)
- **Agent Requested:** The agent can ask to load a skill by description
- **Manual:** User explicitly loads via command

This is more efficient than putting everything in a rules file, because skills are loaded only when relevant rather than consuming context in every conversation.

---

## 8. Mode Design

### 8.1 The Three Universal Modes

Nearly every multi-mode agent converges on the same three modes:

| Mode              | Purpose                          | Tool Access           | Used By                                                |
| ----------------- | -------------------------------- | --------------------- | ------------------------------------------------------ |
| **Chat/Ask**      | Conversational Q&A               | No tools or read-only | Cline, Continue, Kiro, Junie, Goose                    |
| **Plan**          | Design and plan before executing | Read-only tools       | Cline, Continue, Gemini CLI, Claude Code, Goose, Devin |
| **Agent/Code/Do** | Full execution with all tools    | All tools             | Every tool                                             |

**Why Plan mode matters:** Plan mode lets the user review the agent's approach before it starts making changes. It is read-only: the agent can search, read files, and explore, but cannot edit or execute. This builds trust and catches misunderstandings early.

Implementation:

```python
MODES = {
    "chat": {
        "tools": [],  # No tools, or very limited
        "prompt_addition": "You are in chat mode. Answer questions conversationally. Do not use tools."
    },
    "plan": {
        "tools": ["read_file", "search", "glob", "list_files"],  # Read-only
        "prompt_addition": "You are in plan mode. Explore the codebase and design a plan. Do NOT modify any files."
    },
    "agent": {
        "tools": ALL_TOOLS,
        "prompt_addition": ""  # Default mode, no additions needed
    }
}
```

### 8.2 Advanced Mode Patterns

**Roo Code's 5-mode system** (the most copied pattern in the ecosystem):

- **Code:** Full access, implements features
- **Architect:** Read-only, designs architecture
- **Ask:** No tools, answers questions
- **Debug:** Focused on diagnostics and testing
- **Orchestrator:** Breaks work into subtasks and delegates

**Kiro's intent classifier:** Instead of the user choosing a mode, Kiro runs a classifier prompt that returns confidence scores:

```json
{ "do": 0.8, "spec": 0.1, "chat": 0.1 }
```

The highest-confidence mode is selected automatically. This removes the cognitive burden from the user.

**Gemini CLI's Directive vs. Inquiry distinction:** The only tool that explicitly differentiates "do this" from "tell me about this" at the prompt level. Directives trigger the Research -> Strategy -> Execution lifecycle. Inquiries get a direct answer.

### 8.3 Mode Transitions

Two approaches:

**User-initiated (most common):** The user explicitly switches modes via a command (`/plan`, `/chat`, `/agent`). This is Cline, Continue, and Goose's approach.

**Agent-initiated (emerging):** The agent can switch its own mode. Roo Code has a `switch_mode` tool. Kiro uses automatic classification. Devin transitions from planning to execution mode after gathering enough information.

**Recommendation:** Start with user-initiated mode switching. Add automatic mode detection later if you find users frequently forget to switch modes.

---

## 9. Common Mistakes

These anti-patterns are visible across the 43 tools, either as mistakes that were corrected over time or as patterns that produce poor results.

### 9.1 Not Enforcing Read-Before-Edit

The single most impactful rule across all tools. Without it, agents will hallucinate file contents and produce edits that don't match reality. Every tool that added this rule saw immediate improvement in edit success rates.

**Fix:** Maintain a set of files read in the conversation. Fail the edit tool if the file has not been read.

### 9.2 Allowing Unbounded Shell Execution

Without timeouts and banned command lists, agents will:

- Start interactive programs that hang forever (vi, python REPL)
- Run commands that produce infinite output
- Execute `sudo` commands that escalate privileges
- Run `curl` to send data to external services

**Fix:** Set a default timeout (2 minutes is standard). Ban interactive commands. Ban `sudo` unless explicitly enabled. Pipe all output through `head` or truncate after N characters (Claude Code truncates at 30,000 characters).

### 9.3 Guessing URLs

Multiple tools (Claude Code, Crush) explicitly ban URL guessing. Without this rule, agents will fabricate plausible-looking URLs to documentation that does not exist, API endpoints that do not work, and libraries that were never published.

**Fix:** Add to your system prompt: `"NEVER generate or guess URLs. Only use URLs from the user or from local files."`

### 9.4 Over-Engineering and Scope Creep

Claude Code addresses this explicitly:

```
Avoid over-engineering. Only make changes that are directly requested or clearly necessary.
Don't add features, refactor code, or make "improvements" beyond what was asked.
A bug fix doesn't need surrounding code cleaned up.
A simple feature doesn't need extra configurability.
Don't add docstrings, comments, or type annotations to code you didn't change.
```

This is one of the most common complaints about AI coding agents: they "help" by reorganizing code, adding unnecessary abstractions, or "improving" things the user did not ask about.

**Fix:** Be explicit in your prompt: only change what was requested. Do not add comments, types, or docstrings to unchanged code. Do not refactor adjacent code unless asked. Three similar lines of code are better than a premature abstraction.

### 9.5 Not Testing After Changes

Crush, Claude Code, and Codex CLI all mandate running tests after modifications. Without this, agents will make changes that break existing functionality and not notice.

**Fix:** Add to your workflow: "After making changes, run the project's test suite. If tests fail, fix the failures before proceeding."

### 9.6 Creating Files Instead of Editing

Claude Code repeats this multiple times: "ALWAYS prefer editing existing files to creating new ones. NEVER write new files unless explicitly required." Without this rule, agents will create duplicate files, new utility modules for one-time use, and README files nobody asked for.

**Fix:** Make your edit tool the default. The write tool should only be used for genuinely new files. Add a prompt rule banning proactive creation of documentation files.

### 9.7 Sycophantic Output

As discussed in Section 1.5, multiple tools have independently converged on banning sycophantic language. Without anti-sycophancy rules, every response starts with "Great question!" or "That's a fantastic idea!" This wastes tokens and erodes trust.

**Fix:** Ban openers like "Great", "Certainly", "Sure", "Of course". Ban closers like "Let me know if you need anything else" and "Hope this helps." Focus output on the actual task.

### 9.8 Ignoring Existing Patterns

A common failure: the agent introduces a completely different coding style, naming convention, or architecture pattern than what exists in the codebase. Codex CLI addresses this: "Keep changes consistent with the style of the existing codebase."

**Fix:** Add to your workflow: "Before making changes, examine similar existing code to understand the project's patterns, naming conventions, and architectural style. Follow them."

### 9.9 Monolithic System Prompts

SWE-agent achieves competitive benchmark scores with a one-sentence system prompt. Goose manages with ~80 lines. LangGraph provides zero default prompts. Meanwhile, some tools have bloated prompts full of redundant instructions.

The lesson: prompt length does not correlate with capability. What matters is:

1. Clear constraints (10 good rules beat 50 vague ones)
2. Good tool definitions (most intelligence can live in tool descriptions)
3. Runtime context (environment info, user rules, memory)
4. Effective tool implementation (a good edit tool with a bad prompt beats a bad edit tool with a good prompt)

**Fix:** Start with a 100-line prompt. Add rules only when you observe specific failure modes. Every line in your prompt should address a real problem you have seen.

### 9.10 Not Handling the Amend-After-Hook-Failure Case

This is Claude Code's unique insight, and it is worth repeating because it is so subtle. If your agent runs git commits and the project has pre-commit hooks:

1. Agent runs `git commit -m "fix bug"`
2. Pre-commit hook fails (linting error, formatting issue)
3. The commit was NEVER CREATED
4. Agent fixes the issue and runs `git commit --amend -m "fix bug"`
5. `--amend` modifies the PREVIOUS commit (the user's last commit, not the failed one)
6. The user's work is now corrupted

**Fix:** After any hook failure, always create a NEW commit. Never use `--amend` after a failed commit.

---

## Quick Reference: The Minimum Viable Agent

If you want to build a working coding agent with the minimum viable feature set, here is what you need:

| Component         | Recommendation                                                               |
| ----------------- | ---------------------------------------------------------------------------- |
| **System prompt** | ~100 lines covering identity, constraints, workflow, tool usage              |
| **Tools**         | 6 core: read_file, edit_file, write_file, search, glob, run_shell            |
| **Edit format**   | old_string/new_string exact replacement                                      |
| **Safety**        | Read-before-edit, shell timeout, banned commands, git commit only on request |
| **Context**       | Environment block (OS, cwd, date, git status), user rules file support       |
| **Modes**         | Plan mode (read-only tools) + Agent mode (all tools)                         |

This gets you 80% of the way to a production agent. The remaining 20% -- sub-agents, persistent memory, skills, symbol-level editing, KV-cache optimization -- can be added incrementally as you encounter real-world limitations.

---

## Further Reading

- **Manus context engineering blog**: The best public writeup on KV-cache optimization and action space management for agents. https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus
- **Serena lessons learned**: Practical insights on symbol-level editing and why LLMs struggle with line numbers. https://github.com/oraios/serena/blob/main/lessons_learned.md
- **Aider edit format benchmarks**: Systematic comparison of edit format accuracy across models. https://aider.chat/docs/leaderboards/
- **Claude Code system prompt**: The most comprehensive single-agent prompt in production. Analyze it end-to-end.
- **CrewAI prompt assembly**: The cleanest multi-agent prompt system with i18n support. https://github.com/crewAIInc/crewAI
