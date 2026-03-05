---
name: agentic-research
description: Use when the user needs to research multiple systems, products, or technologies in parallel and synthesize findings into actionable recommendations. Triggers on competitive analysis, technology comparison, market research, "research X vs Y", architectural research across multiple systems, or any investigation requiring structured multi-source analysis.
---

# Agentic Research Workflow

A structured workflow for researching multiple systems in parallel and synthesizing findings into actionable output. Based on the research brief pattern — define objectives, dispatch parallel agents, gather structured reports, synthesize across systems.

## When to Use This

- Comparing multiple products, tools, or technologies
- Competitive analysis ("how do others solve this problem?")
- Architecture research before building something new
- Investigating a domain you're unfamiliar with
- Any task where you need to research 3+ systems and draw conclusions

## Decision Tree

```
Research task received → How many systems?
│
├─ 1 system (deep dive)
│  └─ Single agent, use "Research Techniques" below, skip synthesis
│
├─ 2 systems (comparison)
│  └─ Write brief → 2 parallel agents → comparative synthesis
│
├─ 3+ systems (survey)
│  └─ Write brief → N parallel agents → full synthesis with feature matrix
│
└─ Unknown / exploratory ("how do others solve X?")
   └─ `web_search` to identify systems first → then treat as 3+ system survey
```

```
Per-system research → What sources are available?
│
├─ Has public API docs / OpenAPI spec?
│  └─ Start here — API shapes reveal the data model directly
│     Use `web_fetch` on docs URLs, look for entity names and relationships
│
├─ Has help center / knowledge base?
│  └─ Second priority — "How to set up X" articles reveal workflows
│     Use `web_fetch` on help center pages, follow links 2-3 levels deep
│
├─ Has open-source code / SDK?
│  └─ Check GitHub — types, schemas, and entity definitions are gold
│     Use `bash` with `gh repo view` / `gh api` to explore
│
├─ Marketing site only?
│  └─ Use `web_search` for reviews (G2, Capterra), blog posts, comparisons
│     These often contain more detail than the marketing site itself
│
└─ Very little public info?
   └─ Mark confidence 🔴, state what's unknown, spend less time here
      An honest "unknown" is more useful than a plausible guess
```

## Phase 1: Research Brief

Before touching any system, write a brief that defines:

### 1. Objective

One paragraph: what are we trying to learn, and why?

```markdown
## Objective

Research and document how [domain] systems handle [specific problem].
The goal is to understand [what patterns exist / how others solve this]
to inform [our own design / a decision / a recommendation].
```

### 2. Key Design Questions

3-9 specific questions that drive the research. These are NOT "tell me about X" — they're decision-forcing questions:

```markdown
### Key Design Questions

1. **[Specific design decision]**: How do different systems handle [X]?
   Is the approach [A-centric or B-centric]?
2. **[Trade-off]**: When [scenario], do systems choose [approach A] or
   [approach B]? What are the consequences?
3. **[Gap detection]**: What capabilities do users need that current
   systems don't provide?
```

Bad questions: "What is X?" / "Tell me about Y" (too vague, no decision to inform)
Good questions: "Is the data model person-centric or credential-centric?" (forces comparison)

### 3. Systems to Research

List all systems with URLs and categories:

```markdown
### Systems to Research

| System | URL | Category |
| --- | --- | --- |
| System A | https://... | Category 1 |
| System B | https://... | Category 1 |
| System C | https://... | Category 2 (adjacent) |
```

Include adjacent/analogous systems from related domains — they often have the best ideas.

### 4. What to Look For

Ordered by priority — what information matters most:

```markdown
### What to Look For (priority order)

1. **Data model** — Core entities, relationships, cardinality
2. **Terminology** — What words does each system use for the same concepts?
3. **Workflows** — Key user journeys, step by step
4. **Integration model** — APIs, webhooks, native integrations
5. **Strengths and limitations** — What works, what doesn't, what's missing
```

### 5. Per-System Report Template

Define the structure every report should follow:

```markdown
### Per-System Report Structure

1. System Overview (what, who, positioning)
2. Glossary (system term → generic concept → description)
3. Data Model (entity-relationship diagram + written description)
4. Key Workflows (as diagrams)
5. Strengths & Limitations
6. Sources (all URLs consulted)
```

### 6. Confidence Markers

Require confidence annotations on every section:

- 🟢 **High** — API docs, schema, or primary source available
- 🟡 **Medium** — Inferred from help docs, UI screenshots, or demos
- 🔴 **Low** — Guessed from marketing copy or reviews

"Data model: Not publicly documented. Inferred from UI screenshots and help articles." is more useful than a confident-sounding fabrication.

## Phase 2: Parallel Research Dispatch

Each system can be researched **independently and in parallel**. There are no dependencies between systems.

### Agent Dispatch Pattern

```
For each system in the research brief:
  Launch a sub-agent with:
    - The system's entry URL
    - The research brief's "What to Look For" section
    - The per-system report template
    - Instructions to use web search, web fetch, and any available tools
    - The confidence marking requirements
  Prefer `spawn_parallel_subagents` to dispatch all system agents together.
```

### Research Techniques (Per Agent)

Each agent should use these tools in priority order:

| Priority | Source Type | Tool | What to Extract |
| --- | --- | --- | --- |
| 1 | API docs / OpenAPI specs | `web_fetch` on docs URL | Entity names, field types, relationships, endpoint shapes |
| 2 | Help center / knowledge base | `web_fetch` on help articles, follow links 2-3 deep | Workflows ("How to set up X"), terminology, form fields |
| 3 | Open source code / SDKs | `bash` with `gh api` / `gh repo view` | Type definitions, schema files, entity structures |
| 4 | Third-party analysis | `web_search` for "[system] review", "[system] vs [competitor]" | Features, limitations, user pain points |
| 5 | Product pages | `web_fetch` on main site | Positioning, pricing, feature lists |
| 6 | Demo videos | `web_search` for "[system] demo" on YouTube | UI structure, workflows invisible in docs |
| 7 | Job postings | `web_search` for "[system] engineer" | Tech stack, internal terminology |

**Concrete patterns:**

```text
# Find API docs
web_search(query: "[system name] API documentation")
web_search(query: "[system name] OpenAPI swagger")

# Deep-read help center
web_fetch(url: "https://docs.example.com/getting-started")
# Then follow links found in the content

# Check GitHub for schemas/types
web_search(query: "[system name] github")
# If repo found:
bash(command: "gh api repos/org/repo/contents/src/types --jq '.[].name'")

# Find reviews with specific details
web_search(query: "[system name] review G2 Capterra 2025")
web_search(query: "[system name] vs [competitor] comparison")
```

### Per-System Report Output

Each agent produces a standalone report following the template. Reports should be:

- **Self-contained** — Readable without context from other reports
- **Evidence-linked** — Every claim links to a source URL
- **Confidence-marked** — Every section has a 🟢🟡🔴 marker
- **Honest about gaps** — "Unknown" > plausible guess

## Phase 3: Synthesis

After all individual reports are complete, synthesize across systems.

### Cross-System Comparison

For each Key Design Question from the brief:

```markdown
## Question 1: [The question]

| System | Approach | Details | Confidence |
| --- | --- | --- | --- |
| System A | Approach X | [specifics] | 🟢 |
| System B | Approach Y | [specifics] | 🟡 |
| System C | Approach X (variant) | [specifics] | 🟡 |

**Pattern**: Most systems use Approach X because [reason].
System B's Approach Y is interesting because [reason] but has the downside of [limitation].

**Recommendation**: [Specific recommendation with reasoning]
```

### Pattern Identification

Look across all reports for:

- **Convergence** — Where do most systems agree? This is likely the right approach.
- **Divergence** — Where do systems disagree? This is where interesting design decisions live.
- **Gaps** — What do users need that no system provides well? This is opportunity.
- **Terminology patterns** — What words does the industry use? Adopt the dominant vocabulary unless there's a good reason not to.

### Feature Matrix

```markdown
| Capability | System A | System B | System C |
| --- | --- | --- | --- |
| Feature 1 | ✅ Full support | ⚠️ Partial | ❌ Missing |
| Feature 2 | ✅ | ✅ | ✅ |
| Feature 3 | ❌ | ✅ Best in class | ⚠️ |
```

## Phase 4: Actionable Output

Research is only valuable if it produces decisions. The final output should include:

### Executive Summary (1-2 pages)

- Top 3-5 findings that should influence design decisions
- Feature matrix comparison table
- Recommended approach for each Key Design Question, with citations

### Detailed Recommendations

For each key decision:

```markdown
### Recommendation: [Decision]

**Adopt**: [Specific approach], as used by [System A] and [System C]
**Why**: [Reasoning based on evidence from research]
**Avoid**: [Alternative approach] because [evidence-based reasoning]
**Open question**: [What we still don't know and how to find out]
```

## Extensions (Optional, Based on Scope)

### Research → Data Model

When research informs a system you're building, extend findings into an entity-relationship sketch:

```markdown
## Proposed Data Model (informed by research)

Based on [System A]'s approach to [concept] and [System C]'s handling of [concept]:

[Mermaid erDiagram or written description]

Key decisions:
- [Entity X] is the central entity because [evidence from research]
- [Relationship Y] uses [pattern] based on [System B]'s approach
```

### Research → Spec Draft

```markdown
## Feature Spec: [Feature Name]

### Background
[Summary of research findings relevant to this feature]

### Requirements (informed by research)
- [Requirement derived from competitive analysis]
- [Requirement addressing gap identified in research]

### Design
[Design decisions justified by research findings]
```

### Research → Prototype

For validation before committing to full implementation:

```markdown
## Prototype Scope

Based on research, validate these hypotheses with a minimal prototype:
1. [Hypothesis derived from research] → Build: [minimal UI/API to test]
2. [Hypothesis] → Build: [minimal test]
```

## Quality Standards

A completed research project must have:

- [ ] Research brief with clear objectives and key design questions
- [ ] Individual reports for every system (no gaps, no skipped systems)
- [ ] Confidence markers on every section of every report
- [ ] Cross-system comparison answering every key design question
- [ ] Feature matrix with all systems and capabilities
- [ ] Specific, actionable recommendations (not just "it depends")
- [ ] Honest handling of unknowns ("we couldn't determine X" > guessing)
- [ ] All sources cited with URLs

## Anti-Patterns

| Anti-Pattern | Why It's Bad | Do Instead |
| --- | --- | --- |
| Starting research without a brief | You'll waste time on irrelevant details | Write the brief first, even if brief |
| Researching systems sequentially | 5x slower than parallel | Dispatch all agents at once |
| Over-researching one system | Depth without breadth | Equal effort per system, synthesis is where value lives |
| Fabricating when info is unavailable | Undermines trust in all findings | Mark confidence 🔴, state what's unknown, move on |
| "It depends" conclusions | Not actionable | Recommend a specific approach with reasoning |
| Skipping adjacent domains | Misses the best ideas | Always include 2-3 analogous systems from related industries |
