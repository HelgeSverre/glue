# Agentic Developer Tools: Opinionated Recommendations (February 2026)

> Based on detailed analysis of 289 tool reports. Every recommendation is backed by specific evidence from the tool profiles. Prices and capabilities reflect the state of the market as of February 12, 2026.

---

## 1. Overall Top 10

### 1. Claude Code (Anthropic)

The best agentic coding tool available today, period. Claude Opus 4.5/4.6 are the strongest coding models on the market (80.9% SWE-bench Verified for Opus 4.5). The terminal-native approach, 14-event hooks system, Agent Teams for parallel execution, deep git integration, and the Claude Agent SDK give it the richest feature surface. The CLAUDE.md convention is elegant and effective. The GitHub Action for @claude mentions in PRs is a genuine workflow transformation.

**Why #1**: Best models + deepest extensibility + most mature agent loop. $1.1B ARR proves developers agree.

**Caveat**: Claude-only model support is real vendor lock-in. Rate limits on Pro plans frustrate users. Cost at scale with Opus models is steep.

### 2. Cursor (Anysphere)

The best AI-native IDE experience. The VS Code fork approach means zero learning curve for the world's most popular editor. Deep codebase indexing via tree-sitter + Turbopuffer gives genuine repo-wide awareness. The Composer model (250 tok/s) is fast. Up to 8 parallel background agents on isolated branches is a differentiator. Multi-model support (Anthropic, OpenAI, Google, plus Cursor's own model) provides flexibility Claude Code lacks. The Graphite acquisition (December 2025) brings stacked PRs and AI code review into the Cursor ecosystem.

**Why #2**: Best IDE integration + multi-model support + background agents + Graphite for code review. $1B+ ARR, 1M+ daily active users, $29.3B valuation.

**Caveat**: Closed source. Inconsistent AI quality reported across sessions. Credit-based pricing confuses users. Stability complaints from frequent updates.

### 3. GitHub Copilot (Microsoft/GitHub)

The market leader by adoption (20M+ users, 4.7M paid subscribers, 42% market share). Broadest IDE support in the industry (VS Code, Visual Studio, JetBrains, Eclipse, Xcode, Vim/Neovim). The async Copilot Coding Agent (assign a GitHub issue, get a PR back) is a powerful workflow. 24+ models from five providers. The free tier (2,000 completions + 50 chat messages) is genuinely useful. Unmatched GitHub platform integration.

**Why #3**: Broadest reach + deepest GitHub integration + most generous free tier + enterprise maturity.

**Caveat**: Complex codebase struggles. Security concerns (25-29% of generated Python/JS code contained weaknesses in academic studies). Premium request economics get expensive with Opus-class models.

### 4. OpenCode (Anomaly Innovations)

The fastest-growing open-source coding agent. 103K GitHub stars, 2.5M monthly developers, MIT license. 75+ model providers, LSP integration with 30+ language servers (a genuine differentiator -- semantic code understanding, not just text matching), ACP support for IDE integration (VS Code, JetBrains, Zed, Neovim, Emacs), GitHub Actions agent, rich plugin system, and the ability to use existing GitHub Copilot, ChatGPT Plus, or Claude Pro subscriptions. The client/server architecture enables remote sessions and future persistent workspaces.

**Why #4**: Best model freedom in a CLI agent + LSP integration + existing subscription leverage + massive open-source community. From the SST team with proven open-source track record.

**Caveat**: Fast-shipping means bugs. Permissive defaults are dangerous for new users. Less polished than Claude Code for Anthropic models specifically. Only 8 months old.

### 5. Aider (Paul Gauthier)

The most proven open-source CLI coding agent. Broadest model support of any tool (virtually any LLM via LiteLLM). The Architect mode (two-model split) is genuinely innovative -- expensive model reasons, cheap model edits. Git-native workflow where every AI change is a proper commit with attribution. Tree-sitter repo map provides efficient whole-codebase awareness without indexing. Apache 2.0, zero vendor lock-in, 41K stars, 4.9M PyPI installs.

**Why #5**: Best model freedom + Git-native + Architect mode + truly free + proven at scale (15B tokens/week). Two years of maturity.

**Caveat**: Terminal-only UX. No MCP support. No semantic search. No built-in agent planning. Struggles with very large files.

### 6. Cline (Saoud Rizwan)

The best agentic VS Code extension. Plan/Act paradigm provides structured collaboration. Complete model freedom (any LLM). MCP extensibility allows unlimited tool integration. Browser automation built in. 57.8K GitHub stars, 5M+ VS Code installs, fastest-growing AI open-source project on GitHub (4,704% contributor growth). Apache 2.0.

**Why #6**: Best agentic extension for VS Code + model freedom + MCP + browser automation + open source.

**Caveat**: No inline completions (pair with Copilot). Variable costs ($50-100+/month for heavy users). No codebase indexing. Can get stuck in loops. Fork explosion (Roo Code, Kilo Code, CoolCline) fragments the community.

### 7. Windsurf / Devin (Cognition)

Windsurf's Cascade agent is a strong multi-file, multi-step coding experience with real-time contextual awareness. SWE-1.5 model is free and fast (950 tok/s). FedRAMP High certified -- the only AI coding assistant with that distinction. Now under Cognition ownership, the Devin integration promises plan-delegate-review workflows. $82M ARR, 350+ enterprise customers, Gartner Magic Quadrant Leader.

**Why #7**: Best enterprise security posture (FedRAMP High) + free SWE-1.5 model + strong agentic IDE.

**Caveat**: Ownership turbulence (Google acqui-hired founders, Cognition acquired the rest). Lost original founding team. Integration of Devin and Windsurf cultures is unproven.

### 8. Gemini CLI (Google)

The best free CLI agent. 1M-token context window is the largest among mainstream agents. 1,000 requests/day free tier is unmatched. Fully open source (Apache 2.0, 94K GitHub stars). Native Google Search grounding. Intelligent model routing between Pro and Flash. GitHub Actions integration for PR review and issue triage.

**Why #8**: Most generous free tier + largest context window + open source + Google Search grounding.

**Caveat**: Gemini models only. Occasional task incompletion. Verbose for small tasks. Node.js dependency.

### 9. Goose (Block / Linux Foundation)

The best extensible open-source agent. Apache 2.0, now under Linux Foundation governance. 3,000+ MCP extensions. Recipes for shareable, schedulable workflows. 30+ model providers. Desktop app + CLI with shared configuration. Used by 60% of Block's 12,000 employees. Pioneered the AGENTS.md standard (adopted by 60K+ repos).

**Why #9**: Most extensible + Linux Foundation governance + recipes + AGENTS.md pioneer.

**Caveat**: Output quality varies dramatically by model choice. More setup required than commercial tools. Security concerns with untrusted recipes. No native IDE integration yet.

### 10. Roo Code / Kilo Code (the Cline fork family)

Roo Code and Kilo Code are both Apache 2.0 forks of Cline that have diverged significantly. Roo Code's multi-mode architecture (Code/Architect/Ask/Debug/Orchestrator/Custom) with per-mode model assignment and Boomerang task orchestration. Kilo Code goes further: multi-IDE (VS Code, JetBrains, CLI, Slack, cloud agents), 500+ models, managed cloud indexing, inline autocomplete, and Virtual Provider for rate-limit fallback. Kilo raised $8M seed with GitLab co-founder Sid Sijbrandij.

**Why #10**: Best workflow customization in the VS Code extension space. Kilo Code's multi-surface "Agentic Anywhere" strategy (VS Code, JetBrains, CLI, Slack) is the most ambitious of any open-source agent.

**Caveat**: Fork lineage creates "circular dependency" instability. High token consumption. Configuration complexity. Kilo Code is still young (March 2025 launch).

---

## 2. Best by Use Case

### Best for Solo Developers

**Primary: Claude Code** -- The terminal-native approach fits solo devs who want maximum power without context-switching. $20/month on Claude Pro gets you all models including Opus 4.6. The agent teams feature lets you parallelize work even as a single developer.

**Alternative 1: Cursor** ($20/month Pro) -- If you prefer an IDE-first workflow over terminal. The background agents let you work on one thing while the AI works on another.

**Alternative 2: OpenCode** ($0 + API costs or use existing subscriptions) -- If you want zero vendor lock-in with the richest open-source CLI experience. Use your existing Claude Pro or ChatGPT Plus subscription. LSP integration gives semantic code understanding no other open-source CLI offers.

### Best for Teams (5-20 devs)

**Primary: GitHub Copilot Business** ($19/seat/month) -- The broadest IDE support means every team member can use their preferred editor. The async coding agent (assign issue, get PR) fits team workflows naturally. Organization-wide custom instructions via `copilot-instructions.md`. IP indemnity for enterprise peace of mind.

**Alternative 1: Cursor Teams** ($40/user/month) -- If the team standardizes on VS Code/Cursor. Shared chats, centralized billing, RBAC, enforced Privacy Mode. BugBot for automated PR review ($40/month add-on). Now with Graphite for stacked PRs and merge queues.

**Alternative 2: Kilo Code Teams** ($15/user/month) -- If the team uses mixed IDEs (VS Code, JetBrains, CLI). Usage analytics, AI adoption scoring, shared modes, centralized billing. The Slack bot lets non-developers trigger coding tasks.

### Best for Enterprise (100+ devs)

**Primary: GitHub Copilot Enterprise** ($39/seat/month) -- SAML SSO, audit logs, SCIM provisioning, IP indemnity, self-hosted runners, content exclusions, organization-wide policies. Already adopted by 90% of Fortune 100. The coding agent runs in GitHub Actions (your infrastructure).

**Alternative 1: Windsurf Enterprise** ($60/user/month) -- FedRAMP High authorized, HIPAA BAA, SOC 2 Type II, self-hosted deployment options (Docker Compose or Helm). The only AI coding assistant with FedRAMP High -- critical for government and regulated industries.

**Alternative 2: GitLab Duo** ($29-99/user/month via Premium/Ultimate) -- If your org is on GitLab. AI embedded across the entire DevSecOps lifecycle with the Duo Agent Platform (GA January 2026). Specialized agents for planning, security analysis, and data queries. Self-hosted model support for data sovereignty. MCP client integration.

### Best Free / Open Source

**Primary: OpenCode** -- MIT license, 103K stars. Use with existing GitHub Copilot, ChatGPT Plus, or Claude Pro subscriptions for $0 additional cost. Or use OpenCode Zen (pay-as-you-go, no subscription). 75+ model providers including free tiers. LSP integration, MCP support, GitHub Actions agent. The most feature-complete open-source coding agent.

**Alternative 1: Gemini CLI** -- 1,000 free requests/day with Gemini 3 Pro (1M context window). Apache 2.0. Most developers will never need to pay. The free tier alone makes it a viable daily driver.

**Alternative 2: Aider** -- Apache 2.0, zero cost for the tool itself. Pair with Google Gemini 2.5 Pro Exp (free) or OpenRouter free tier for $0 total cost. Or use DeepSeek V3 for $1-5/month with strong results. The most battle-tested open-source option.

### Best for Beginners

**Primary: Cursor** -- Zero learning curve if you know VS Code (or any editor). Import your existing settings, extensions, and keybindings. Agent mode is intuitive: open the panel, describe what you want, review the diffs. Checkpoints provide safety nets. $0 free tier to start.

**Alternative 1: GitHub Copilot in VS Code** -- The most seamless "just works" experience. Install the extension, sign in, start typing. Inline completions appear automatically. Agent mode for more complex tasks. Free tier with 50 chat messages/month.

**Alternative 2: Windsurf** -- Reviewers consistently highlight Windsurf as more approachable than Cursor for newcomers. Cascade's real-time contextual awareness means less manual context management. Free SWE-1.5 model means beginners can experiment without worrying about costs.

### Best for Power Users

**Primary: Claude Code** -- 14 hook lifecycle events, MCP support, custom slash commands, skills, plugins, subagents, Agent SDK, headless mode for CI/CD. The deepest extensibility surface of any coding agent. Terminal-native fits power-user workflows. Pair with Claude Squad or tmux-based orchestrators for multi-agent workflows.

**Alternative 1: OpenCode** -- 30+ LSP servers, MCP (local + remote with OAuth), custom tools, plugins, custom agents, custom commands, skills, ACP for IDE integration. Permissive MIT license means you can fork and customize anything. Client/server architecture enables remote operation.

**Alternative 2: Amp** -- Deep mode with GPT-5.2 Codex for extended reasoning. Skills, MCP, Toolboxes, Checks. Thread editing with automatic revert. $10/day free grant is generous. From the Sourcegraph team who understand code intelligence deeply.

### Best CLI Agent

**Primary: Claude Code** -- The canonical terminal AI coding experience. Best models in the space. Deep git integration. Agent teams. Hooks system. Headless mode. The CLI is the primary surface, not an afterthought.

**Alternative 1: OpenCode** -- The strongest open-source alternative. 103K stars, MIT license. LSP integration is a genuine differentiator for semantic code understanding. ACP bridge to IDEs. Use with existing subscriptions for $0 extra.

**Alternative 2: Qwen Code** -- The best free CLI from the open-source model world. 1,000 free requests/day via OAuth. Apache 2.0. Qwen3-Coder-480B achieves 37.5% on SWE-bench (competitive with Claude Sonnet among open models). 256K native context, up to 1M with extrapolation.

### Best IDE Experience

**Primary: Cursor** -- Purpose-built AI-native IDE with the deepest integration. Codebase indexing, multi-model support, background agents, Composer model, inline completions (Supermaven acquisition), aggregated diff view, checkpoints. Now with Graphite for stacked PRs and merge queues.

**Alternative 1: JetBrains + Junie** -- If you are a JetBrains user, Junie leverages the IDE's deep code intelligence (semantic indexing, type resolution, refactoring tools) in ways no VS Code extension can match. The GitHub Action for CI/CD integration is a nice touch.

**Alternative 2: Zed** -- If performance matters most. Written in Rust, sub-millisecond responsiveness, 120fps rendering. Agent Client Protocol (ACP) lets you connect any external agent (OpenCode, Claude Code, etc.). Multibuffer editing for reviewing cross-file changes. Open source (GPL/AGPL). 50K+ stars. The editor to watch.

### Best Cloud/Browser Agent

**Primary: Replit Agent** -- Zero setup, instant deployment. Agent 3 runs up to 200 minutes autonomously with self-healing browser testing. Spawns specialized sub-agents (Stacks). Mobile preview via Expo. 30+ native integrations (Stripe, Figma, Notion, etc.). Best for going from idea to deployed app fastest.

**Alternative 1: Bolt.new** -- WebContainers technology (in-browser OS) is a genuine innovation. Fastest time-to-working-app for JavaScript/Node.js projects. Under 2 minutes from URL to running app. Figma import. Plan Mode reduces wasted tokens.

**Alternative 2: Google Jules** -- The best async cloud coding agent. Assign tasks via web UI, CLI, API, or GitHub issue labels. Jules works in a Google Cloud VM, delivers results as PRs. Critic agent reviews changes before presenting them. Suggested Tasks proactively scans repos. 15 free tasks/day. The "virtual teammate" approach is mature and well-integrated with GitHub.

### Best for Frontend/Web Development

**Primary: v0 (Vercel)** -- The composite model family achieves 93.87% error-free React/Next.js generation. Native Vercel deployment. Design Mode for visual editing. Figma import. Git-first workflow with branch-per-chat and PR creation. MCP extensibility. The king of React/Next.js generation.

**Alternative 1: Bolt.new** -- WebContainers create instant development environments for any JavaScript framework (React, Vue, Svelte, Astro). Full-stack in one surface. Excellent for rapid prototyping.

**Alternative 2: Lovable** -- Generates clean React/TypeScript with shadcn/ui. Deep Supabase integration (auth, DB, storage, real-time). Visual Editor for Figma-like style adjustments. 20x faster claim is credible for standard web app patterns. Best for non-technical founders building MVPs.

### Best for Backend/Systems Development

**Primary: Claude Code** -- Claude models excel at complex multi-step reasoning required for backend architecture. Language-agnostic (Python, Go, Rust, Java, C++, etc.). Terminal-native fits backend dev workflows. Agent teams for parallel work on different services.

**Alternative 1: Amazon Q Developer / Kiro** -- Best for AWS infrastructure. CloudFormation, CDK, Terraform generation. Java/.NET modernization (/transform). Security scanning with automated remediation. 25+ language support. Kiro's spec-driven development provides the traceability enterprises need.

**Alternative 2: OpenCode** -- LSP integration with 30+ language servers gives semantic understanding of backend codebases (Go, Rust, Python, Java, C/C++). Model-agnostic means you can pick the best model for your language. GitHub Actions agent for CI/CD.

### Best for Full-Stack Projects

**Primary: Cursor** -- The IDE-first approach handles frontend and backend equally well. Deep codebase indexing means it understands the full stack. Multi-model support lets you pick the best model per task. Background agents can work on frontend while you work on backend.

**Alternative 1: Claude Code** -- If you prefer terminal workflows. Equally capable across the full stack. Agent teams can parallelize frontend and backend work.

**Alternative 2: Firebase Studio** -- If you want a zero-setup cloud IDE with integrated deployment. Google's all-in-one: VS Code-based editor + Gemini AI + App Prototyping agent + built-in web preview + Android emulator + direct Firebase/Cloud Run deployment. Free, generous workspace limits. Best for Google Cloud-native teams.

### Best for Legacy Codebases

**Primary: Sourcegraph Cody (Enterprise)** -- Built on Sourcegraph's code graph, which indexes entire codebases including cross-repository dependencies. Multi-repo awareness across thousands of repositories. Batch Changes for large-scale refactoring. Designed for enterprise-scale legacy code.

**Alternative 1: Augment Code** -- The Context Engine semantically indexes entire codebases (400K+ files) with millisecond-level sync. 70.6% SWE-bench accuracy with Context Engine. Available as standalone MCP server for use with Claude Code or Cursor.

**Alternative 2: Devin** -- Excels at legacy code tasks: Java version migrations (14x faster than humans), COBOL handling (5M lines), framework upgrades, monorepo conversions. 67% PR merge rate. $20/month Core plan.

### Best for Rapid Prototyping

**Primary: Bolt.new** -- Under 2 minutes from URL to running app. Zero local setup. WebContainers technology creates instant dev environments. Figma import. One-click deployment.

**Alternative 1: Lovable** -- Complete full-stack apps from a single prompt (React + Supabase + Tailwind + shadcn/ui). 100,000+ new projects daily. Visual Editor for quick styling adjustments.

**Alternative 2: Dyad** -- The local-first alternative. Open source (Apache 2.0), runs entirely on your machine, no sign-up required. Model-agnostic (cloud or local via Ollama). 19K stars. Best for developers who want Bolt/Lovable-style app generation with full privacy.

### Best for Code Review and Quality

**Primary: CodeRabbit** -- The most specialized code review tool. Automatic PR reviews with 40+ built-in linters and SAST tools. AI-powered noise filtering surfaces only actionable findings. Free Pro tier for open-source projects. 2M+ repos, 13M+ PRs processed.

**Alternative 1: Greptile** -- Graph-based codebase indexing provides context-aware reviews beyond surface-level linting. Custom rules in plain English. Learning system improves from engineer feedback. Used by Brex, Substack, PostHog. Now part of Cursor (acquired December 2025). $30/dev/month.

**Alternative 2: Claude Code (via GitHub Action)** -- `@claude review this PR for security issues` in any PR comment. The GitHub Action provides autonomous review with the strongest coding models available.

### Best Value for Money

**Primary: OpenCode + existing subscriptions** -- Free (MIT license). Log in with your existing GitHub Copilot, ChatGPT Plus, or Claude Pro subscription. 75+ model providers, LSP integration, MCP, GitHub agent. Effectively $0 additional cost if you already pay for any major AI subscription.

**Alternative 1: Gemini CLI** -- Free. 1,000 requests/day with Gemini 3 Pro. 1M token context. Open source. For most individual developers, this is genuinely free forever.

**Alternative 2: Aider + DeepSeek V3** ($1-5/month total) -- Apache 2.0 tool + rock-bottom API costs. DeepSeek V3 delivers competitive quality at a fraction of Anthropic/OpenAI pricing. The Architect mode with cheap editor model optimizes cost further.

### Best for Infrastructure / DevOps

**Primary: Pulumi Neo** -- Natural language infrastructure management across 160+ cloud providers. Human-in-the-loop approvals with configurable autonomy. Cost optimization and compliance checking built in. MCP integration for IDE-based workflows. 18x faster provisioning reported.

**Alternative 1: Amazon Q Developer / Kiro** -- Best for AWS-native shops. CloudFormation, CDK, Terraform generation. Security scanning. Java/.NET modernization.

**Alternative 2: Docker AI (Gordon)** -- Built into Docker Desktop, zero setup. Deep Docker context awareness. MCP integration with 100+ servers. The go-to for container-specific AI assistance.

### Best for Multi-Agent Orchestration

**Primary: Claude Squad** -- The most practical multi-agent orchestrator. Uses tmux for session isolation and git worktrees for code isolation. Supports Claude Code, Aider, OpenCode, Codex, Gemini, Amp. Auto-accept mode for trusted workflows. Go binary, lightweight, works today.

**Alternative 1: Claude Code Agent Teams** -- First-party multi-agent support built into Claude Code. Parallel execution with shared context. No additional tool needed.

**Alternative 2: OpenHands** -- The leading open-source cloud agent platform. 65K stars, MIT license. CodeAct architecture with sandboxed Docker execution. 53% SWE-bench Verified. Best for teams building custom multi-agent workflows.

### Best for Specific Languages

| Language                  | Best Tool                     | Why                                                                        |
| ------------------------- | ----------------------------- | -------------------------------------------------------------------------- |
| **Python**                | Claude Code or Aider          | Claude excels at Python; Aider's Git-native workflow suits Python projects |
| **TypeScript/JavaScript** | Cursor or v0                  | Cursor's indexing handles TS well; v0 is unmatched for React/Next.js       |
| **Go**                    | Claude Code or OpenCode       | Claude models handle Go well; OpenCode has Go LSP built in                 |
| **Rust**                  | Claude Code or OpenCode       | Both handle Rust; OpenCode's Rust LSP gives semantic understanding         |
| **Java**                  | JetBrains + Junie or Amazon Q | JetBrains' deep Java intelligence; Amazon Q's /transform for modernization |
| **C/C++**                 | Claude Code or OpenCode       | OpenCode's clangd LSP integration gives C/C++ semantic awareness           |
| **Ruby/Rails**            | Cursor or Aider               | Good framework understanding across the stack                              |
| **Swift/iOS**             | Copilot for Xcode or Cursor   | Copilot is the only major tool with Xcode integration                      |

---

## 3. Decision Flowchart

```
START: What is your primary workflow?
|
+-- Terminal / CLI
|   |
|   +-- "Is budget a concern?"
|   |   |
|   |   +-- Yes, need free: Gemini CLI (free, 1K requests/day)
|   |   |                    or Qwen Code (free, 1K requests/day)
|   |   |
|   |   +-- Yes, but have existing sub: OpenCode ($0 with Copilot/ChatGPT/Claude sub)
|   |   |
|   |   +-- No: Claude Code ($20-200/mo depending on plan)
|   |
|   +-- "Do you need model freedom?"
|       |
|       +-- Yes, and want LSP/MCP: OpenCode (75+ providers, MIT)
|       |
|       +-- Yes, Git-native workflow: Aider (any model via LiteLLM)
|       |
|       +-- No, Claude is fine: Claude Code
|       |
|       +-- No, GPT is fine: OpenAI Codex CLI
|
+-- VS Code
|   |
|   +-- "Do you want a separate IDE or an extension?"
|   |   |
|   |   +-- Separate AI-native IDE: Cursor ($0-200/mo)
|   |   |
|   |   +-- Extension in existing VS Code:
|   |       |
|   |       +-- "Is budget a concern?"
|   |       |   |
|   |       |   +-- Yes: GitHub Copilot Free or Cline + free models
|   |       |   |
|   |       |   +-- No: Cline or Roo Code + Claude API
|   |       |
|   |       +-- "Do you want multi-IDE support?"
|   |       |   |
|   |       |   +-- Yes (VS Code + JetBrains + CLI + Slack):
|   |       |   |   Kilo Code ($0 tool + API costs)
|   |       |   |
|   |       |   +-- No, VS Code only: Cline or Roo Code
|   |       |
|   |       +-- "Do you want inline completions?"
|   |           |
|   |           +-- Yes: GitHub Copilot (completions) + Cline (agentic tasks)
|   |           |        or Kilo Code (has both inline and agentic)
|   |           |
|   |           +-- No, agentic tasks only: Cline or Roo Code
|   |
|   +-- "Do you need self-hosting?"
|       |
|       +-- Yes: Cline/Roo Code + local models via Ollama,
|       |   or Tabby for self-hosted completions
|       |
|       +-- No: Any of the above
|
+-- JetBrains (IntelliJ, PyCharm, WebStorm, etc.)
|   |
|   +-- JetBrains Junie (built-in, $10-60/mo)
|   |   Best: leverages deep IDE intelligence
|   |
|   +-- GitHub Copilot for JetBrains (agent mode GA)
|   |   Best: if already using Copilot across the org
|   |
|   +-- Kilo Code for JetBrains (open source, 500+ models)
|   |   Best: if you want model freedom in JetBrains
|   |
|   +-- Continue (open source, model-agnostic)
|       Best: if you want YAML-first configuration
|
+-- Neovim / Vim
|   |
|   +-- OpenCode (ACP integration for Neovim natively)
|   |
|   +-- Claude Code (terminal-native, works alongside any editor)
|   |
|   +-- Aider (terminal-native)
|   |
|   +-- avante.nvim or codecompanion.nvim (Neovim plugins)
|   |
|   +-- Zed (if willing to switch editors -- ACP brings any agent)
|
+-- Browser only (no local setup)
|   |
|   +-- "What are you building?"
|       |
|       +-- Prototype / MVP: Bolt.new or Lovable
|       |
|       +-- React/Next.js specifically: v0 (Vercel)
|       |
|       +-- Full-stack app with deployment: Replit Agent
|       |
|       +-- Local-first app builder with privacy: Dyad
|       |
|       +-- Delegating async tasks to an AI engineer: Google Jules
|       |
|       +-- Complex multi-step autonomous tasks: Devin or Manus
|
+-- GitLab users
|   |
|   +-- GitLab Duo ($29-99/user/mo via Premium/Ultimate)
|       Agent Platform, specialized agents, full SDLC integration
|
+-- "Do you need self-hosting?"
|   |
|   +-- Self-hosted completions: Tabby (Apache 2.0, self-hosted)
|   |
|   +-- Self-hosted agent: OpenHands (MIT, Docker-based)
|   |
|   +-- Self-hosted IDE agent: Cline + Ollama (fully local)
|   |
|   +-- Enterprise self-hosted: Windsurf Enterprise or
|   |   Sourcegraph Cody Enterprise
|   |
|   +-- Self-hosted with GitLab: GitLab Duo Self-Hosted
|
+-- "Do you need to support a large legacy codebase?"
|   |
|   +-- Yes, 100K+ files across repos: Sourcegraph Cody Enterprise
|   |
|   +-- Yes, with deep semantic indexing: Augment Code
|   |
|   +-- Migration/modernization tasks: Devin or Amazon Q /transform
|
+-- "Do you need AI-powered infrastructure?"
    |
    +-- Multi-cloud IaC: Pulumi Neo (160+ providers)
    |
    +-- AWS-specific: Amazon Q Developer / Kiro
    |
    +-- Docker/containers: Docker AI (Gordon)
    |
    +-- Sandboxed code execution: E2B (de facto standard) or Daytona (90ms startup)
```

---

## 4. Tools to Watch

### 1. OpenCode (Anomaly Innovations)

Already in the Top 10, but the trajectory demands attention. 103K stars and 2.5M monthly developers in eight months. The SST team's execution speed is remarkable. LSP integration, ACP for editors, existing subscription leverage, and an MIT license make it the most serious open-source challenger to Claude Code. If the "Black" subscription tier materializes and they fix permissive-default safety issues, OpenCode could move up significantly.

### 2. Amp (ex-Sourcegraph)

Spun out from Sourcegraph with co-founders Quinn Slack and Beyang Liu. "No token limits" philosophy with $10 daily free grant. Three modes (Smart/Rush/Deep) with frontier models. Sub-agents for parallel work. Deep mode with GPT-5.2 Codex for extended reasoning is a differentiator. Thread editing with automatic revert is clever. Backed by Craft, Redpoint, Sequoia. Early but moving fast.

### 3. Kiro (AWS)

Spec-driven development is a genuinely novel approach: natural language -> EARS requirements -> technical design -> implementation tasks. The autonomous cloud agent (preview) coordinates specialized sub-agents. AWS backing ensures longevity. Could become the enterprise standard if the spec-driven workflow proves out.

### 4. Zed

The fastest editor in existence (Rust, sub-millisecond, 120fps). Created the Agent Client Protocol (ACP) standard -- any agent works in any editor. 50K+ GitHub stars. From the creators of Atom and Tree-sitter. If ACP gains broad adoption (OpenCode already supports it), Zed becomes the universal agent host.

### 5. Google Jules

The most mature async cloud coding agent. Plan-first transparency, critic agent self-review, Suggested Tasks proactive scanning, persistent per-repo memory, CLI, API, and GitHub Action. 15 free tasks/day. Strong at well-scoped tasks. The "assign and forget" model genuinely multiplies productivity for routine work.

### 6. Kilo Code

Multi-IDE (VS Code, JetBrains, CLI, Slack, cloud agents), 500+ models, managed cloud indexing, inline autocomplete, Virtual Provider, Skills marketplace, $8M seed. The "Agentic Anywhere" strategy is the most ambitious of any open-source agent. GitLab co-founder Sid Sijbrandij as co-founder brings credibility.

### 7. Augment Code

The Context Engine is the real product -- semantic indexing of entire codebases (400K+ files) with millisecond sync. Now available as a standalone MCP server, meaning you can use it with Claude Code or Cursor. 30-80% quality improvements when paired with external models. ISO 42001 certified. Could become the "codebase intelligence layer" that other tools plug into.

### 8. Serena (Oraios AI)

LSP-as-MCP-server is a smart architectural bet. Provides semantic code understanding (go-to-definition, find-references, rename) to any MCP-compatible agent. 30+ languages. 20K GitHub stars. Reduces token waste by retrieving only relevant symbols rather than entire files. The "give any LLM IDE-like understanding" pitch is compelling.

### 9. Daytona

Pivoted from dev environments to agent-native compute. 90ms sandbox creation (faster than E2B), forking and snapshotting for tree-search agent strategies, Apache 2.0, self-hostable. $24M Series A. If agent frameworks increasingly need sandboxed execution (they will), Daytona and E2B are the infrastructure layer.

### 10. Qwen Code (Alibaba)

The best open-model CLI agent. Qwen3-Coder-480B-A35B achieves 37.5% on SWE-bench. 1,000 free requests/day via OAuth. Apache 2.0. Multi-provider support. 18.4K stars. The combination of a competitive open model and an open CLI makes this the strongest non-Western alternative.

---

## 5. Tools to Avoid

### Devin -- for tasks beyond its sweet spot

Devin is excellent for well-scoped, repetitive tasks (migrations, security fixes, test coverage). But the marketing as "the world's first AI software engineer" set expectations that reality cannot meet. Answer.AI's independent test found only 3 successes out of 20 tasks (15%). It can pursue impossible solutions for hours, burning ACUs with no value. **Use it for what it is good at (junior dev on well-defined tickets), not as a senior engineer replacement.**

### Manus -- for production software development

Manus (now Meta-owned, $2-3B acquisition) is strong for research, data analysis, and web scraping. But for production software development, it falls short: no Git-native workflow, no branch/PR/review integration, export-oriented rather than collaborative. Credit system depletes quickly on complex tasks (the $39 plan covers 4-5 complex tasks). Server reliability issues persist. **Use for research and analysis; avoid for coding.**

### Lovable -- if you need anything beyond React/Supabase

The opinionated tech stack (React + Supabase + Tailwind only) is a hard lock-in. No Vue, Angular, Svelte, Django, Rails, or alternative backend. No native mobile app generation. Complex business logic confuses the AI. Message limits constrain iteration on lower plans. **Excellent for React/Supabase MVPs; avoid for anything else.**

### Bolt.new -- for production applications

Bolt excels at prototypes but the "fix-and-break cycle" is well-documented: fixing one issue introduces new ones, consuming tokens rapidly. Users report spending over $1,000 on token reloads primarily to debug issues the agent itself introduced. Limited to JavaScript/Node.js (no Python, Go, Rust backends). No formal code review workflow. **Use for prototyping only; migrate to a real development environment before production.**

### Supermaven -- acquired and absorbed

Supermaven was acquired by Cursor in November 2024 and its technology was integrated into Cursor's Tab completions. The standalone product is effectively dead. **Use Cursor instead.**

### Plandex -- effectively discontinued

Plandex had genuinely innovative ideas (diff sandbox, plan branching, model packs). But the founder shut down Plandex Cloud in November 2025, accepted a position at Promptfoo, and explicitly stated that Claude Code "executed masterfully on the original vision." The self-hosted version still works but receives no updates. **Interesting to study for its architecture, but do not adopt for new projects.**

### ChatDev / BabyAGI / MetaGPT / SmolDeveloper / GPT-Pilot

Research projects and demos from 2023-2024 that have not kept pace. Rarely updated, limited real-world utility, approaches superseded by more mature implementations. **Interesting to study, not practical to use in 2026.**

### CoolCline and other minor Cline forks

CoolCline (~60 stars) and similar tiny Cline forks offer marginal feature aggregation but lack the community, maintenance, and momentum of Cline itself, Roo Code, or Kilo Code. The fork proliferation creates confusion without adding real value. **Stick with Cline, Roo Code, or Kilo Code.**

### Tools with data privacy red flags

**Trae (ByteDance)**: Despite being free and capable (6M+ users), ByteDance's data practices and regulatory environment create real privacy risks. An independent security analysis found potential data transmission to Chinese-controlled servers. Multiple governments have restricted ByteDance products. **If you handle sensitive code, avoid Trae or at minimum self-host with network monitoring.**

---

## 6. The Stack Recommendation

For a developer who wants the optimal setup in 2026:

### Primary IDE Agent: Cursor ($20/month Pro)

The AI-native IDE that does not require you to leave your editor. Import your VS Code setup on day one. Use Agent mode for multi-file tasks, Tab for inline completions, @codebase for whole-repo questions. Background agents for async work. Multi-model support means you can switch between Claude, GPT, and Gemini based on the task. Graphite integration for stacked PRs and merge queues.

_Alternative if you are terminal-first_: Skip the IDE agent entirely and use Claude Code as your primary.

### CLI Agent for Terminal Work: Claude Code ($20/month Pro or API)

When you need to work in the terminal -- git operations, system-level tasks, CI/CD integration, or just prefer the command line. Claude Opus 4.6 is the strongest coding model available. CLAUDE.md provides project-level context. Headless mode for automation. The GitHub Action for @claude in PRs bridges the terminal-to-GitHub workflow.

_Budget alternative_: OpenCode (free, use with existing subscriptions) or Gemini CLI (free, 1,000 requests/day) or Aider + DeepSeek V3 ($1-5/month).

### Cloud Agent for Async Tasks: Google Jules ($0-20/month)

The most mature async coding agent. Assign tasks via web UI, CLI, API, or GitHub issue labels. Jules works in a cloud VM, runs tests, and delivers results as pull requests. Critic agent self-reviews before presenting. Suggested Tasks proactively scans repos. 15 free tasks/day on the free tier covers most individual needs.

_Alternative_: GitHub Copilot Coding Agent (included in $10/month Pro) for simpler issue-to-PR workflows.

### Framework for Custom Agents: Claude Agent SDK (Python/TypeScript)

When you need to build custom agent workflows -- CI/CD automation, custom code review pipelines, batch processing, internal tools. The same engine as Claude Code, available programmatically. Supports hooks, subagents, MCP, permissions, and session management.

_Alternative_: OpenAI Agents SDK + Codex as MCP server for GPT-model-based workflows. Or the Vercel AI SDK for web-based agent applications.

### Supporting Tools

| Role                          | Tool                                                                                                                | Cost                                                       |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| **Code review**               | CodeRabbit (free for open source, $24/seat/month Pro)                                                               | Automated PR reviews with 40+ linters                      |
| **Stacked PRs / merge queue** | Graphite (now part of Cursor)                                                                                       | $40/user/month Teams, or free basic stacking               |
| **MCP servers**               | Playwright MCP (browser testing), GitHub MCP (repo operations), Serena (LSP-based code intelligence), database MCPs | Free (open source)                                         |
| **Codebase intelligence**     | Augment Code Context Engine (MCP server)                                                                            | Enhances any MCP-compatible agent's codebase understanding |
| **Spec-driven context**       | Tessl (10K+ library tiles for correct API usage)                                                                    | Enhances agent reliability via MCP                         |
| **Design-to-code**            | v0 ($20/month) for React/Next.js UI generation                                                                      | Best-in-class error-free rate                              |
| **Self-hosted completions**   | Tabby (free, Apache 2.0)                                                                                            | For air-gapped or privacy-sensitive environments           |
| **Sandboxed execution**       | E2B (standard) or Daytona (fastest startup)                                                                         | For custom agent workflows needing isolated code execution |
| **Multi-agent orchestration** | Claude Squad (free, AGPL-3.0)                                                                                       | Manage parallel agents with tmux + git worktrees           |
| **Terminal with AI**          | Warp ($0-20/month)                                                                                                  | AI-native terminal with agent mode and MCP gallery         |
| **Infrastructure**            | Pulumi Neo (free preview)                                                                                           | Natural language infrastructure management                 |
| **Project instructions**      | CLAUDE.md + AGENTS.md + .cursorrules                                                                                | Free -- version control these with your repo               |

### Total Monthly Cost

| Configuration                                                                     | Monthly Cost |
| --------------------------------------------------------------------------------- | ------------ |
| **Budget** (OpenCode + existing sub + Gemini CLI + Jules Free)                    | $0-5         |
| **Solo developer** (Cursor Pro + Claude Code Pro + Jules Free)                    | $40          |
| **Power user** (Cursor Pro + Claude Code Max 5x + Jules Pro + CodeRabbit)         | $174         |
| **Team of 5** (Cursor Teams + Copilot Business + CodeRabbit Pro + Graphite Teams) | ~$835/month  |

---

## 7. The Market Landscape in Three Paragraphs

The agentic coding tools market has exploded from a niche curiosity to a $10B+ category in under two years. The top tier is now established: Claude Code and Cursor dominate the premium segment, GitHub Copilot owns enterprise distribution, and OpenCode has emerged as the open-source breakout. The "vibe coding" trend (using AI to generate entire applications from natural language) spawned tools like Bolt.new, Lovable, v0, and Replit Agent, but the limitations of prompt-and-pray development are becoming clear -- serious projects still need structured agent workflows with human review.

The most important architectural shift is the convergence on MCP (Model Context Protocol) as the standard for extending agent capabilities, and ACP (Agent Client Protocol) for editor integration. Tools that adopted MCP early (Claude Code, Cline, Roo Code, Kilo Code, OpenCode, Goose) have richer ecosystems. Tools that ignored it (Aider, Devin, Lovable) are increasingly isolated. Meanwhile, the infrastructure layer is maturing: E2B and Daytona provide sandboxed execution, Serena provides LSP-as-MCP, Augment Code provides semantic indexing-as-MCP, and Tessl provides library context-as-MCP. The "agent stack" is becoming composable.

Consolidation is accelerating. Cursor acquired Supermaven and Graphite. Google acqui-hired Windsurf's founders. Cognition bought the rest of Windsurf. Meta bought Manus for $2-3B. Sourcegraph spun out Amp. Plandex's founder walked away. Smaller tools are being absorbed or abandoned. The survivors will be tools with either (a) massive open-source communities (OpenCode, Aider, Cline), (b) deep platform integration (Copilot, GitLab Duo, JetBrains Junie), or (c) clear differentiation (Augment Code for context, Serena for LSP, E2B for sandboxing). Everything in the middle is at risk.

---

## Methodology

These recommendations are based on analysis of 289 tool reports covering:

- Official documentation, pricing pages, and changelogs
- GitHub repositories (stars, contributors, release cadence)
- Independent benchmarks (SWE-bench Verified, Aider Polyglot Leaderboard, Terminal-Bench)
- Third-party reviews (TechCrunch, InfoWorld, The Register, Ars Technica, VentureBeat)
- Community sentiment (Reddit, Hacker News, Discord)
- Enterprise adoption data (ARR, customer logos, compliance certifications)
- Hands-on evaluation notes where available
- Acquisition and funding activity through February 2026

Every tool was evaluated on: agentic capabilities, model support, extensibility (especially MCP/ACP), pricing, open-source status, IDE integration, git workflow, enterprise readiness, community health, and trajectory.

---

_Last updated: February 12, 2026_
