# Deep Comparison: User Customization Formats Across AI Coding Tools

> Analysis date: 2026-02-13
> Covers 20+ tools with user-facing customization file formats
> Sources: extracted system prompts, open-source codebases, community extractions

---

## 1. Format Inventory

Every known customization file format, organized by tool.

| Tool                   | File(s)                                                                                 | Syntax                                       | Location(s)                                                     | Backing Org                      |
| ---------------------- | --------------------------------------------------------------------------------------- | -------------------------------------------- | --------------------------------------------------------------- | -------------------------------- |
| **Claude Code**        | `CLAUDE.md`                                                                             | Markdown (free-form)                         | `./CLAUDE.md`, `./.claude/CLAUDE.md`, `~/.claude/CLAUDE.md`     | Anthropic                        |
| **Codex CLI**          | `AGENTS.md`                                                                             | Markdown (free-form)                         | Any directory (hierarchical: root to leaf)                      | OpenAI                           |
| **Gemini CLI**         | `GEMINI.md`                                                                             | Markdown (free-form)                         | `~/.gemini/GEMINI.md`, extensions, project root, subdirectories | Google                           |
| **Cursor**             | `.cursorrules`                                                                          | Markdown (free-form)                         | Project root                                                    | Cursor/Anysphere                 |
| **Windsurf**           | `.windsurfrules`                                                                        | Markdown (free-form)                         | Project root                                                    | Codeium/OpenAI                   |
| **Cline**              | `.clinerules`                                                                           | Markdown (free-form)                         | Project root                                                    | Cline (open source)              |
| **Roo Code**           | `.roomodes`, `.roo/rules*`                                                              | JSON (modes), Markdown (rules)               | Project root (`.roomodes`), `.roo/` directory                   | Roo Code (open source)           |
| **Kilo Code**          | `.kilocodemodes`, `.kilocode/system-prompt-{mode}`                                      | JSON (modes), Markdown (prompts)             | Project root, `.kilocode/` directory                            | Kilo Code (open source)          |
| **GitHub Copilot**     | `.github/copilot-instructions.md`, `.github/agents/*.md`, `.github/prompts/*.prompt.md` | Markdown + YAML frontmatter                  | `.github/` directory                                            | GitHub/Microsoft                 |
| **Amazon Q**           | `.amazonq/rules/*.md`, `~/.aws/amazonq/prompts/`                                        | Markdown (free-form)                         | Project `.amazonq/`, user `~/.aws/`                             | AWS                              |
| **Kiro**               | `.kiro/steering/*.md`                                                                   | Markdown + YAML frontmatter                  | `.kiro/steering/` directory                                     | AWS                              |
| **Continue**           | `.continue/rules/*.md`                                                                  | Markdown + metadata (globs, attachment type) | `.continue/rules/` directory                                    | Continue (open source)           |
| **Goose**              | `.goosehints`, `AGENTS.md`                                                              | Markdown (free-form)                         | Project root                                                    | Block                            |
| **Warp**               | `WARP.md`                                                                               | Markdown (free-form)                         | Project root                                                    | Warp                             |
| **OpenCode**           | `OpenCode.md`                                                                           | Markdown (free-form)                         | Project root                                                    | OpenCode (open source)           |
| **JetBrains Junie**    | `.junie/guidelines.md`                                                                  | Markdown (free-form)                         | `.junie/` directory                                             | JetBrains                        |
| **avante-nvim**        | `.avanterules`                                                                          | Jinja2 templates                             | Project root                                                    | avante-nvim (open source)        |
| **gptme**              | `gptme.toml`                                                                            | TOML                                         | Project root, `~/.config/gptme/`                                | gptme (open source)              |
| **Serena**             | `serena.yml`, per-project config                                                        | YAML                                         | Project root                                                    | Serena (open source)             |
| **codecompanion-nvim** | (reads others) `.cursorrules`, `.clinerules`, `CLAUDE.md`, `AGENTS.md`                  | Markdown (free-form)                         | Project root                                                    | codecompanion-nvim (open source) |
| **OpenHands**          | `.openhands/microagents/`, `.cursorrules`, `AGENTS.md`                                  | Markdown, TOML                               | Project root                                                    | OpenHands (open source)          |
| **Augment Code**       | User rules (settings-based)                                                             | Free-form text                               | IDE settings                                                    | Augment                          |

### Naming Convention Taxonomy

Three naming schools have emerged:

1. **`TOOLNAME.md` (SHOUTING_CASE)** -- `CLAUDE.md`, `GEMINI.md`, `AGENTS.md`, `WARP.md`, `OpenCode.md`. These are prominently visible in project root directories. They follow the `README.md` convention of being discoverable project-level metadata.

2. **`.toolrules` (dotfile)** -- `.cursorrules`, `.windsurfrules`, `.clinerules`, `.avanterules`, `.goosehints`. Hidden by default in file listings. Follows the Unix convention of per-tool configuration (`.gitignore`, `.eslintrc`).

3. **`.tool/` directory** -- `.github/copilot-instructions.md`, `.amazonq/rules/`, `.kiro/steering/`, `.continue/rules/`, `.junie/guidelines.md`, `.roo/rules*`, `.kilocode/`. Namespaced configuration directories. The most structured approach, allowing multiple files and separation of concerns.

---

## 2. Feature Matrix

| Feature                     | CLAUDE.md                        | AGENTS.md                  | GEMINI.md                                 | .cursorrules       | .windsurfrules     | .github/copilot-\*                     | .amazonq/rules/           | .kiro/steering/                         | .continue/rules            | .roo/ + .roomodes                  | .kilocode/                   | .avanterules                  |
| --------------------------- | -------------------------------- | -------------------------- | ----------------------------------------- | ------------------ | ------------------ | -------------------------------------- | ------------------------- | --------------------------------------- | -------------------------- | ---------------------------------- | ---------------------------- | ----------------------------- |
| **Hierarchy support**       | 3-tier (user, project, .claude/) | Unlimited (any dir depth)  | 4-tier (global, extension, root, subdirs) | Single file        | Single file        | 3-tier (instructions, agents, prompts) | 2-tier (global, project)  | Multi-file additive                     | Multi-file with types      | Per-mode                           | Per-mode + global            | Template inheritance          |
| **Mode-specific rules**     | No                               | No                         | No                                        | No                 | No                 | Yes (agents)                           | No                        | No (cross-mode)                         | Yes (attachment types)     | Yes (per-mode custom instructions) | Yes (system-prompt-{mode})   | Yes ({% block %})             |
| **Glob/path scoping**       | No                               | Yes (directory tree)       | Yes (subdirectory scope)                  | No                 | No                 | No                                     | No                        | Yes (fileMatch patterns)                | Yes (globs per rule)       | Yes (fileRegex per tool group)     | Yes (fileRegex)              | No                            |
| **Agent-specific rules**    | No                               | No                         | No                                        | No                 | No                 | Yes (.github/agents/\*.md)             | No                        | No                                      | Yes (Agent Requested type) | No                                 | No                           | No                            |
| **Prompt templates**        | No                               | No                         | No                                        | No                 | No                 | Yes ({{variable}} in .prompt.md)       | No                        | Yes (#[[file:path]])                    | No                         | No                                 | Yes (variable interpolation) | Yes (Jinja2 full)             |
| **Conditional logic**       | No                               | No                         | No                                        | No                 | No                 | No                                     | No                        | Yes (frontmatter: inclusion, fileMatch) | Yes (4 attachment types)   | No                                 | No                           | Yes ({% if %}, {% extends %}) |
| **Inheritance**             | Project overrides global         | Deeper overrides shallower | More specific overrides general           | N/A                | N/A                | Agents layer on top of instructions    | Implicit + explicit merge | Additive (all loaded)                   | By attachment type         | Mode inherits global               | File can replace or extend   | Template {% extends %}        |
| **Multi-file support**      | No (single per tier)             | Yes (one per directory)    | Yes (one per scope)                       | No                 | No                 | Yes (multiple agents, prompts)         | Yes (multiple .md files)  | Yes (any number of .md)                 | Yes (any number)           | Yes (.roo/rules\*)                 | Yes (per-mode files)         | No                            |
| **Structured format**       | Free-form Markdown               | Free-form Markdown         | Free-form Markdown                        | Free-form Markdown | Free-form Markdown | Markdown + YAML frontmatter            | Free-form Markdown        | Markdown + YAML frontmatter             | Markdown + metadata        | JSON (modes) + Markdown (rules)    | Markdown (prompts)           | Jinja2 templates              |
| **Tool access control**     | No                               | No                         | No                                        | No                 | No                 | Yes (tools list in agent frontmatter)  | No                        | No                                      | No                         | Yes (tool groups per mode)         | Yes (tool groups per mode)   | No                            |
| **File reference includes** | No                               | No                         | No                                        | No                 | No                 | No                                     | No                        | Yes (#[[file:path]])                    | No                         | No                                 | No                           | Yes ({% include %})           |

---

## 3. Injection Mechanism

How each format gets incorporated into the LLM's context.

### 3.1 Injection Position and Method

| Tool               | Injection Position                                    | Verbatim or Processed             | Wrapping                                                                                                                                              |
| ------------------ | ----------------------------------------------------- | --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Claude Code**    | End of system prompt (Section 17 of ~19)              | Verbatim                          | `## CLAUDE.md\n{contents}` header                                                                                                                     |
| **Codex CLI**      | System-level context, after base prompt               | Verbatim                          | Detailed preamble explaining scope rules: "Each AGENTS.md governs the entire directory that contains it and every child directory beneath that point" |
| **Gemini CLI**     | System prompt, after operational guidelines           | Verbatim                          | `<loaded_context>{content}</loaded_context>` XML tags with explicit precedence documentation                                                          |
| **Cursor**         | Within system prompt body                             | Verbatim                          | `<custom_instructions>{content}</custom_instructions>` XML tags                                                                                       |
| **Windsurf**       | System prompt (exact position unclear)                | Verbatim (presumed)               | Likely within `<user_information>` tags                                                                                                               |
| **Cline**          | Appended to environment details in first user message | Verbatim                          | Included alongside `.cursorrules` and `.windsurfrules` content                                                                                        |
| **Roo Code**       | "USER'S CUSTOM INSTRUCTIONS" section at prompt end    | Verbatim                          | Labeled section after system prompt body                                                                                                              |
| **GitHub Copilot** | After base system prompt; agents layer on top         | Verbatim                          | Instructions appended to system prompt; agents as additional system context                                                                           |
| **Amazon Q**       | System prompt context                                 | Verbatim                          | `<implicitInstruction>` XML tags for org rules; project rules added to context                                                                        |
| **Kiro**           | System prompt, after base prompt                      | Verbatim with conditional loading | Front-matter controls when each file is included                                                                                                      |
| **Continue**       | System prompt composition                             | Verbatim                          | Rules injected based on attachment type (Always, Auto-Attached, Agent Requested, Manual)                                                              |
| **avante-nvim**    | Replaces system prompt template                       | Rendered (Jinja2)                 | Template output becomes the system prompt                                                                                                             |

### 3.2 Precedence Rules

The tools that support hierarchy all implement some form of "more specific wins":

**Claude Code**: `~/.claude/CLAUDE.md` (global defaults) < `./CLAUDE.md` (project-level) < `./.claude/CLAUDE.md` (project-specific override). All three are included in the prompt; the model is expected to respect the closer scope.

**Codex CLI / AGENTS.md**: Root `AGENTS.md` < nested `AGENTS.md` in child directories. Deeper files override shallower ones for files in their scope. System/user prompts override everything.

**Gemini CLI**: Global (`~/.gemini/`) < Extensions < Workspace Root < Sub-directories. Explicitly documented: "Sub-directories > Workspace Root > Extensions > Global." Also states that contextual instructions override operational defaults but CANNOT override core safety mandates.

**Kiro**: Additive model -- all matching steering files are loaded. No explicit override semantics. Conditional inclusion via `fileMatch` patterns means different files activate in different contexts.

**Continue**: Four attachment types determine when rules are loaded:

1. **Always** -- injected into every conversation
2. **Auto-Attached** -- injected when files matching a glob pattern are in context
3. **Agent Requested** -- the agent can request loading them via `RequestRule` tool
4. **Manual** -- user explicitly provides them

### 3.3 Critical Detail: Safety Override Protection

Both **Gemini CLI** and **Amazon Q** explicitly state that user customization files cannot override core safety mandates. Gemini CLI: "Contextual instructions override default operational behaviors defined in the system prompt. However, they cannot override Core Mandates regarding safety, security, and agent integrity." Amazon Q: implicit instructions are "de-prioritized if they conflict with direct user instructions."

**Claude Code** does not explicitly state this boundary in the CLAUDE.md injection but enforces it through the base system prompt's security policy constant, which appears both before and after the CLAUDE.md content.

No other tool documents this safety boundary.

---

## 4. Cross-Tool Compatibility

### 4.1 Who Reads Whose Files

```
                    .cursorrules  .clinerules  CLAUDE.md  AGENTS.md  .windsurfrules
                    ───────────   ──────────   ────────   ─────────  ──────────────
Cursor              PRIMARY       -            -          -          -
Windsurf            -             -            -          -          PRIMARY
Cline               reads         PRIMARY      -          -          reads
Roo Code            -             -            -          -          -
codecompanion-nvim  reads         reads        reads      reads      -
OpenHands           reads         -            -          reads      -
Goose               -             -            -          reads      -
Jules               -             -            -          reads      -
Claude Flow         -             -            reads      -          -
```

### 4.2 The Rosetta Stone: codecompanion-nvim

codecompanion-nvim is the most ecumenical tool, reading four different customization formats. Its rules system is defined as:

> "Project-level instruction files (`.cursorrules`, `.clinerules`, `CLAUDE.md`, `AGENTS.md`, etc.)"

This is the closest thing the ecosystem has to a universal reader. It demonstrates that all of these formats are syntactically compatible (they are all Markdown) and differ only in naming convention and injection semantics.

### 4.3 The Two Camps

The ecosystem is bifurcating into two camps with organizational backing:

**Camp Anthropic: `CLAUDE.md`**

- Native: Claude Code
- Also reads: Claude Flow, codecompanion-nvim
- Strengths: Hierarchical (3-tier), auto-memory companion (MEMORY.md), large installed base
- Organizational backing: Anthropic

**Camp OpenAI: `AGENTS.md`**

- Native: Codex CLI
- Also reads: Goose (Block), Jules (Google), OpenHands, codecompanion-nvim
- Strengths: Directory-scoped (unlimited nesting), multi-tool adoption, cross-company support
- Organizational backing: OpenAI, Google, Block

**Camp Google: `GEMINI.md`**

- Native: Gemini CLI
- Strengths: Most sophisticated hierarchy (4-tier), explicit precedence documentation
- Weakness: No cross-tool adoption yet

**Camp GitHub: `.github/copilot-instructions.md`**

- Native: GitHub Copilot
- Strengths: Most structured format (agents + prompts + instructions), YAML frontmatter, tool access control
- Weakness: Locked to `.github/` namespace, limited cross-tool adoption

The `.cursorrules` format, while read by the most tools (Cline, OpenHands, codecompanion-nvim), has the weakest feature set (single file, no hierarchy, no scoping). Its broad adoption is a legacy of Cursor's early market share, not technical merit.

---

## 5. Best Practices

Patterns that emerge from studying effective customization files across tools.

### 5.1 Content Patterns That Work

**1. Project architecture overview first.**
Every effective rules file starts with what the project IS -- its tech stack, directory structure, and key conventions. This grounds the agent's understanding before any behavioral rules.

```markdown
# Project Overview

- TypeScript monorepo using pnpm workspaces
- packages/core/ contains the business logic
- packages/api/ is the Express REST API
- packages/web/ is the Next.js frontend
- All packages share tsconfig.base.json
```

**2. Build/test/lint commands explicitly.**
Agents cannot guess project-specific commands. The single most impactful customization is telling the agent exactly how to build, test, and lint.

```markdown
# Commands

- Build: `pnpm build`
- Test: `pnpm test` (uses Vitest)
- Lint: `pnpm lint` (ESLint + Prettier)
- Type check: `pnpm typecheck`
```

**3. Behavioral rules stated as imperatives.**
The most effective rules use direct imperative language, not suggestions.

```markdown
# Rules

- Always use named exports, never default exports
- Never use `any` type; use `unknown` for truly unknown types
- Write tests for every new function in the adjacent .test.ts file
- Use zod for all external data validation
```

**4. Anti-patterns explicitly called out.**
Tools respond well to explicit "do NOT" instructions.

```markdown
# Anti-patterns

- Do NOT add console.log for debugging; use the project's logger
- Do NOT create new utility files; add to existing utils/
- Do NOT use relative imports crossing package boundaries; use workspace aliases
```

**5. Keep it under 200 lines.**
Claude Code explicitly truncates MEMORY.md at 200 lines. Other tools do not document limits, but context window pressure makes conciseness critical. The best rules files are 50-150 lines of high-signal content.

### 5.2 Anti-Patterns to Avoid

**1. Duplicating tool behavior.** Do not instruct the agent to "read files before editing" -- the tool's system prompt already says this. Rules files should contain project-specific information, not generic coding advice.

**2. Overly prescriptive step-by-step workflows.** The agent already has a workflow. Adding a second, conflicting workflow creates confusion. State desired outcomes, not processes.

**3. Including sensitive information.** Rules files are committed to version control. Never put API keys, credentials, or internal URLs in them.

**4. Version-specific instructions that rot.** "We use React 18" will eventually be wrong. Prefer "Check package.json for the current React version" over hardcoded version numbers.

---

## 6. Convergence Analysis

### 6.1 What Has Already Converged

**Syntax: Markdown wins.** Every customization format uses Markdown (or Markdown with YAML frontmatter). No tool uses JSON, YAML, or TOML as the primary rules format. This is settled.

**Verbatim injection.** Every tool injects rules content verbatim into the prompt. No tool summarizes, paraphrases, or compresses rules content (though Gemini CLI documents that it takes "absolute precedence" over defaults). This is also settled.

**Project-root location.** Every format lives at or near the project root. The disagreement is only about exact naming and whether to use a subdirectory.

### 6.2 What Is Diverging

**Hierarchy depth.** Ranges from zero (Cursor, Windsurf: single file) through three tiers (Claude Code) to unlimited depth (Codex CLI's per-directory AGENTS.md). No consensus.

**Conditional inclusion.** Three incompatible approaches exist:

- Kiro's YAML frontmatter (`inclusion: fileMatch`, `fileMatchPattern: README*`)
- Continue's attachment types (Always, Auto-Attached, Agent Requested, Manual)
- Codex CLI's implicit directory-tree scoping

**Mode-specific customization.** Only three tools support it (Roo Code, Kilo Code, Continue), and each does it differently (JSON mode config, file naming convention, attachment types).

**Structured metadata.** GitHub Copilot and Kiro use YAML frontmatter for tool lists, descriptions, and conditions. Everyone else uses free-form Markdown with no machine-readable metadata.

### 6.3 What a Universal Format Would Look Like

Based on the strongest features from each tool, a hypothetical universal format would combine:

```markdown
---
# YAML frontmatter (from Copilot + Kiro)
name: "TypeScript Standards"
scope: "always" # always | file-match | agent-requested | manual
fileMatch: "**/*.ts" # from Kiro's fileMatchPattern
tools: ["read_file", "edit_file"] # from Copilot agents
mode: "code" # from Roo Code/Kilo Code per-mode rules
includes:
  - "./api-spec.yaml" # from Kiro's #[[file:path]]
---

# TypeScript Standards (from AGENTS.md / CLAUDE.md free-form body)

## Project Context

- Monorepo using pnpm workspaces
- Strict TypeScript with no `any`

## Rules

- Use named exports exclusively
- Validate all external inputs with zod
- Tests go in adjacent .test.ts files

## Anti-patterns

- No default exports
- No console.log (use project logger)
```

Key design decisions for such a format:

1. **Markdown body with optional YAML frontmatter** -- backwards-compatible with every existing format
2. **`scope` field** -- unifies Continue's attachment types, Kiro's inclusion modes, and AGENTS.md's directory scoping
3. **`fileMatch` field** -- glob-based conditional activation (from Kiro and Continue)
4. **`mode` field** -- per-mode customization (from Roo Code and Kilo Code)
5. **`tools` field** -- agent-specific tool access (from GitHub Copilot)
6. **`includes` field** -- file reference includes (from Kiro's `#[[file:path]]`)
7. **Directory-tree scoping** -- files placed deeper in the tree override shallower ones (from AGENTS.md and GEMINI.md)

### 6.4 Likelihood of Standardization

Low in the near term. The customization file is a competitive moat -- it creates switching costs. Anthropic has no incentive to read `.cursorrules`, and Cursor has no incentive to read `CLAUDE.md`. The convergence that IS happening is driven by:

1. **Open-source tools** acting as bridges (codecompanion-nvim reads four formats)
2. **AGENTS.md** gaining cross-company adoption (OpenAI, Google, Block)
3. **Market pressure** from developers who use multiple tools on the same project

The most likely outcome is a two-format equilibrium: `CLAUDE.md` (Anthropic ecosystem) and `AGENTS.md` (OpenAI/Google ecosystem), with cross-readers filling the gap.

---

## 7. Detailed Format Profiles

### 7.1 CLAUDE.md (Claude Code)

**Hierarchy:**

```
~/.claude/CLAUDE.md          # User-level defaults (all projects)
./CLAUDE.md                  # Project-level rules
./.claude/CLAUDE.md          # Project-specific alternative
```

**Injection:** Appears as `## CLAUDE.md\n{contents}` at the end of the system prompt (Section 17 of ~19 sections). Injected verbatim. When empty, the model sees: "Your CLAUDE.md is currently empty. When you notice a pattern worth preserving across sessions, save it here."

**Companion system:** Auto-memory via `MEMORY.md` -- a separate persistent file that the agent can write to itself, capped at 200 lines. This creates a human-authored (CLAUDE.md) + machine-authored (MEMORY.md) pair.

**Precedence note:** The system prompt states that CLAUDE.md takes contextual priority but the security policy constant appears both before and after it, creating a safety sandwich.

**Strengths:** Simple, discoverable, auto-memory companion, large installed base.
**Weaknesses:** No conditional inclusion, no glob scoping, no mode-specific rules, no structured metadata.

### 7.2 AGENTS.md (Codex CLI)

**Hierarchy:**

```
/AGENTS.md                   # Root-level (broadest scope)
~/AGENTS.md                  # Home directory
/path/to/project/AGENTS.md  # Project-level
/path/to/project/src/AGENTS.md         # Package-level
/path/to/project/src/module/AGENTS.md  # Module-level
```

**Injection:** Each AGENTS.md "governs the entire directory that contains it and every child directory beneath that point." When modifying a file, the agent must comply with every AGENTS.md whose scope covers that file. Deeper files override shallower ones. System/developer/user prompts override all.

**Design philosophy:** Modeled on the `.gitignore` pattern -- place configuration at the level of the tree where it matters, and it cascades downward.

**Memory system:** Codex CLI has a dedicated Memory Writing Agent that extracts learnings from agent rollouts and persists them. This is more sophisticated than Claude Code's MEMORY.md -- it has a separate agent that curates memories with a "signal gate" ("Will a future agent plausibly act better because of what I write here?").

**Strengths:** Unlimited hierarchy depth, directory-scoped precision, cross-tool adoption (Google Jules, Goose, OpenHands, codecompanion-nvim).
**Weaknesses:** No conditional inclusion, no structured metadata, requires understanding of directory-tree scoping mental model.

### 7.3 GEMINI.md (Gemini CLI)

**Hierarchy:**

```
~/.gemini/GEMINI.md          # Global user preferences
[extensions]/GEMINI.md       # Extension-provided knowledge
./GEMINI.md                  # Workspace root (supersedes global)
./subdir/GEMINI.md           # Subdirectory (supersedes root)
```

**Injection:** Wrapped in `<loaded_context>{content}</loaded_context>` XML tags with explicit precedence documentation. The system prompt includes a full "Context Precedence" section and "Conflict Resolution" rules.

**Unique feature:** Gemini CLI is the only tool that explicitly documents what user rules CAN and CANNOT override. Rules can override "default operational behaviors" but CANNOT override "Core Mandates regarding safety, security, and agent integrity."

**Strengths:** Most sophisticated hierarchy (4-tier), explicit precedence documentation, safety boundary documentation.
**Weaknesses:** No cross-tool adoption, no conditional inclusion, no structured metadata.

### 7.4 .cursorrules (Cursor)

**Hierarchy:** Single file at project root. No hierarchy.

**Injection:** Wrapped in `<custom_instructions>{content}</custom_instructions>` XML tags within the system prompt body. In Chat mode, it appears after a note: "Please also follow these instructions in all of your responses if relevant to my query."

**Strengths:** Simplest format, widest cross-tool reading (Cline, OpenHands, codecompanion-nvim all read it).
**Weaknesses:** No hierarchy, no scoping, no conditional inclusion, no structured metadata. The simplest and least capable format in the ecosystem.

### 7.5 .kiro/steering/ (Kiro)

**Hierarchy:** Multiple .md files in `.kiro/steering/`, loaded additively.

**Conditional inclusion via YAML frontmatter:**

```markdown
---
inclusion: fileMatch
fileMatchPattern: "*.test.ts"
---

# Testing Standards

When writing tests, always...
```

Three inclusion modes:

- **Default (always):** No frontmatter needed; included in every interaction
- **fileMatch:** Included when a file matching `fileMatchPattern` is in context
- **manual:** Included when the user explicitly references it via `#` context key

**File references:** Steering files can include `#[[file:relative_path]]` to pull in additional files (e.g., OpenAPI specs, GraphQL schemas).

**Agent-writable:** The system prompt states "You can add or update steering rules when prompted by the users, you will need to edit the files in `.kiro/steering`" -- making steering files a living, agent-maintained resource.

**Strengths:** Conditional inclusion, file references, per-concern organization (security.md, testing.md, style.md), agent-writable.
**Weaknesses:** No hierarchy beyond the project level, no mode-specific rules, AWS ecosystem only.

### 7.6 .github/copilot-instructions.md + agents + prompts (GitHub Copilot)

**Three-tier system:**

1. **Custom Instructions** (`.github/copilot-instructions.md`) -- Always active. Defines "how to behave always."

2. **Custom Agents** (`.github/agents/*.md`) -- Task-specific. Each file defines an agent with YAML frontmatter specifying name, description, and available tools. Agents appear in the VS Code chat UI picker.

```yaml
---
name: "Security Reviewer"
description: "Reviews code for security vulnerabilities"
tools:
  - name: "search_codebase"
  - name: "read_file"
---
```

3. **Prompt Files** (`.github/prompts/*.prompt.md`) -- On-demand templates with `{{variable}}` placeholders. Invoked explicitly by the user.

**Strengths:** Most structured format, tool access control per agent, reusable prompt templates, YAML frontmatter.
**Weaknesses:** Locked to `.github/` namespace (conflicts with GitHub's existing config directory semantics), limited cross-tool adoption.

### 7.7 .continue/rules (Continue)

**Four attachment types:**

- **Always:** Injected into every conversation
- **Auto-Attached:** Injected when files matching a glob pattern are in context
- **Agent Requested:** The agent can request loading via `RequestRule` tool
- **Manual:** User explicitly provides them

**Companion system:** Skills -- loadable Markdown documents that provide detailed instructions for specific tasks, read via `ReadSkill` tool.

**Strengths:** Most granular control over when rules activate, glob-based conditional inclusion, agent-initiated rule loading.
**Weaknesses:** Requires understanding four different attachment types, limited cross-tool adoption.

### 7.8 .roomodes + .roo/rules (Roo Code)

**Custom modes via `.roomodes`:**

```json
{
  "slug": "api-reviewer",
  "name": "API Reviewer",
  "roleDefinition": "You are Roo, an API design expert...",
  "customInstructions": "Focus on REST conventions...",
  "groups": ["read", ["edit", { "fileRegex": "\\.md$" }]]
}
```

**Per-mode rules:** Custom instructions can be specified per mode in the `.roomodes` JSON or via `.roo/rules*` Markdown files.

**Tool group restrictions:** Each mode gets access to specific tool groups (read, edit, command, browser, mcp), with optional file regex restrictions on the edit group.

**Strengths:** Per-mode customization, tool access control with file restrictions, Orchestrator mode for multi-mode workflows.
**Weaknesses:** JSON syntax for mode definitions (more complex than Markdown), limited cross-tool adoption.

### 7.9 .avanterules (avante-nvim)

**Jinja2 template system with inheritance:**

```jinja2
{% extends "base" %}

{% block identity %}
You are a TypeScript specialist...
{% endblock %}

{% block rules %}
- Use strict TypeScript
- Prefer functional patterns
{% endblock %}
```

**Mode-specific customization:** Each mode (Agentic, Editing, Suggesting, Legacy) extends the base template, allowing per-mode overrides through Jinja2 block inheritance.

**GPT-4.1 variant:** Auto-selected based on model detection (`_gpt4-1-agentic.avanterules`).

**Strengths:** Full template language (conditionals, loops, inheritance, includes), per-mode customization, model-specific variants.
**Weaknesses:** Requires Jinja2 knowledge, overkill for simple rules, limited cross-tool adoption.

---

## 8. Recommendation

### If Starting a New Project Today

**Write two files:**

1. **`CLAUDE.md`** at the project root. This covers:
   - Claude Code (native)
   - Claude Flow (reads it)
   - codecompanion-nvim (reads it)
   - Any future Anthropic ecosystem tools

2. **`AGENTS.md`** at the project root. This covers:
   - Codex CLI (native)
   - Google Jules (reads it)
   - Goose (reads it)
   - OpenHands (reads it)
   - codecompanion-nvim (reads it)

**Make the content identical** (or near-identical). Both files are free-form Markdown. There is no technical reason they need to differ. The only overhead is maintaining two files with the same content.

For projects that also use Cursor, add a **`.cursorrules`** symlink or copy. The cost is trivially low, and the cross-tool reading surface is large (Cline, OpenHands, codecompanion-nvim).

### If Using a Specific Tool Extensively

**Cursor users:** `.cursorrules` is your only option, but keep it simple -- Cursor wraps it in `<custom_instructions>` tags and you get no hierarchy or scoping.

**Windsurf users:** `.windsurfrules` is your only option, same constraints as `.cursorrules`.

**Roo Code / Kilo Code users:** Invest in `.roomodes` and `.roo/rules*` (or `.kilocodemodes` / `.kilocode/`). These are the only formats that give you per-mode customization and tool access control. The JSON+Markdown combination is more complex but significantly more powerful.

**Kiro users:** Use `.kiro/steering/` with per-concern files. This is the most sophisticated conditional inclusion system, and the `#[[file:path]]` include syntax is uniquely powerful for projects with OpenAPI/GraphQL specifications.

**GitHub Copilot users:** Use the full three-tier system (`.github/copilot-instructions.md` + `.github/agents/*.md` + `.github/prompts/*.prompt.md`). The agent definition format with tool access control is the most structured option available.

**Continue users:** Leverage the four attachment types, especially Auto-Attached for language-specific rules and Agent Requested for complex procedures.

### The Pragmatic Multi-Tool Strategy

```
project-root/
  CLAUDE.md              # For Claude Code, Claude Flow, codecompanion
  AGENTS.md              # For Codex CLI, Jules, Goose, OpenHands, codecompanion
  .cursorrules           # For Cursor, Cline, OpenHands, codecompanion
  .github/
    copilot-instructions.md  # For GitHub Copilot
  .kiro/
    steering/
      standards.md           # For Kiro
```

Content in all top-level files should be substantively the same. The maintenance cost of keeping 3-4 Markdown files in sync is far lower than the cost of an agent working without project context because you did not create its expected rules file.

### The Long View

Watch `AGENTS.md`. It has the broadest cross-tool adoption (5 tools across 4 companies), the most powerful feature (unlimited directory-tree scoping), and the strongest organizational backing (OpenAI + Google). If any format emerges as a de facto standard, it will likely be this one.

Watch Kiro's steering format. Its conditional inclusion and file reference features solve real problems that none of the other formats address. If AWS pushes this format into broader adoption, its frontmatter-based conditional system could become the basis for a more capable standard.

The most likely endgame is not one format winning, but a tool like codecompanion-nvim's approach spreading: a universal reader that consumes whatever customization file it finds. The format war ends not when one format wins, but when every tool reads all of them.
