---
name: architecture-reverse-engineering
description: Use when analyzing an existing codebase or product to infer how it is architected. Triggers on requests to reverse engineer software structure, map layers, identify bounded contexts, detect DDD, hexagonal architecture, ports-and-adapters, MVC, event-driven design, or explain how a developer tool is put together.
---

# Reverse Engineering Software Architecture

A practical method for inferring the architecture of an existing system from its code, runtime shape, configuration, and documentation. The goal is not to produce a buzzword label too early, but to build an evidence-backed model of how the system is decomposed, where decisions live, and what architectural style it actually follows.

This is especially useful for developer tools, where architecture is often implicit: CLI entrypoints, command registries, agent loops, plugin systems, shell abstractions, transport layers, and internal orchestration may exist without being documented as "clean architecture" or "DDD". Start from evidence, name the patterns later.

## When to Use

- A user asks "how is this system architected?"
- You need to map layers, subsystems, modules, or boundaries in an unfamiliar codebase
- You want to determine whether a system uses DDD, ports-and-adapters, clean architecture, MVC, CQRS, event-driven design, plugin architecture, or a custom hybrid
- You are onboarding into an existing repository and need a high-level structural model
- You need to explain how a devtool, CLI, agent, compiler, daemon, or internal platform is organized
- You need to produce architecture notes for future work, refactoring, migration, or documentation

## When Not to Use

- The task is just to explain one function or one file
- The user wants implementation changes rather than architectural understanding
- There is already authoritative architecture documentation and the job is only to summarize it

## Core Principle

Do not start by asking "is this hexagonal architecture?" Start by asking:

1. What are the main responsibilities?
2. Where are the boundaries?
3. Which modules depend on which?
4. Where does data enter and leave?
5. Where do core decisions live?
6. Which abstractions are stable versus incidental?

Architectural labels are outputs, not inputs.

## What to Produce

A good architecture reverse-engineering result usually includes:

1. **System purpose** — what the software does
2. **Top-level components** — major modules and their responsibilities
3. **Dependency direction** — who depends on whom
4. **Execution flow** — how control moves through the system
5. **Boundary types** — UI, CLI, API, persistence, network, filesystem, external services
6. **Architectural assessment** — which style(s) fit, with evidence
7. **Uncertainties** — what is inferred vs directly evidenced

## Workflow

## Step 1: Establish the Entry Points

Find how the system starts and how users interact with it.

Look for:

- CLI entrypoints: `main`, `bin/`, command registration, argument parsing
- Server entrypoints: `server`, `app`, router bootstrap, handlers
- UI entrypoints: `App`, routes, controllers, view models
- Library entrypoints: exported public API surface
- Background workers: job consumers, schedulers, queue processors

Questions to answer:

- What are the user-visible entrypoints?
- What bootstraps the application?
- Is there one main control loop or several?
- Is composition centralized or distributed?

For devtools specifically, also inspect:

- command dispatch
- plugin loading
- tool registries
- transport abstractions
- shell/runtime adapters
- config loading
- session/state management

## Step 2: Inventory the Top-Level Structure

List the top-level directories and modules before reading deeply.

Build a first-pass table like this:

| Path             | Likely Responsibility   | Confidence |
| ---------------- | ----------------------- | ---------- |
| `bin/`           | executable entrypoints  | High       |
| `lib/src/agent/` | agent orchestration     | Medium     |
| `lib/src/tools/` | tool implementations    | High       |
| `lib/src/web/`   | network/web integration | Medium     |

Do not over-interpret names yet. Directory names are clues, not proof.

## Step 3: Trace Composition and Dependency Direction

Find where the major pieces are wired together.

Look for:

- dependency injection setup
- constructors that accept interfaces/abstractions
- registries and factories
- application bootstrap code
- module initialization order
- import relationships

Questions:

- Is there a composition root?
- Are infrastructure concerns created at the edge and passed inward?
- Do domain-like modules depend on framework-specific code?
- Are abstractions used to invert dependencies, or are they just wrappers?

This step is the fastest way to distinguish layered architecture from ports-and-adapters rhetoric.

## Step 4: Identify Architectural Boundaries

Map the system into boundaries based on responsibility, not folder cosmetics.

Typical boundary types:

| Boundary       | What to Look For                                                   |
| -------------- | ------------------------------------------------------------------ |
| Presentation   | CLI commands, HTTP controllers, UI views, API handlers             |
| Application    | orchestration, use cases, command handlers, workflows              |
| Domain         | core rules, entities, value objects, invariants                    |
| Infrastructure | database, filesystem, shell, HTTP clients, SDK integrations        |
| Integration    | adapters to external systems, transports, protocol implementations |
| Platform       | logging, config, telemetry, auth plumbing                          |

For each candidate boundary, capture:

- main files/modules
- responsibility
- inward and outward dependencies
- whether the boundary is explicit or only implicit

## Step 5: Follow One End-to-End Slice

Pick one representative workflow and trace it through the system.

Examples:

- one CLI command from parse to output
- one HTTP request from route to persistence
- one agent action from prompt to tool execution
- one build action from input file to artifact

Document:

1. entrypoint
2. orchestration layer
3. business rule execution
4. external calls
5. response/output path

One traced slice tells you more than reading 50 random files.

## Step 6: Test Architectural Hypotheses

Only now assess candidate patterns.

### DDD Signals

Evidence that supports DDD:

- explicit domain entities/value objects/aggregates
- business invariants enforced in domain types
- bounded contexts with separate models
- ubiquitous language reflected in code names
- repositories as domain-facing persistence abstractions
- application services coordinating domain behavior

Evidence against DDD:

- "domain" folder that only contains DTOs
- core logic lives in controllers/services/adapters
- data model mirrors tables without business behavior
- no meaningful bounded contexts or domain language

### Ports and Adapters / Hexagonal Signals

Evidence that supports ports-and-adapters:

- clear inward dependency direction
- core logic depends on interfaces, not concrete I/O
- adapters implement ports for shell, DB, HTTP, filesystem, LLMs, etc.
- infrastructure selected at composition time
- use cases remain testable without framework boot

Evidence against it:

- interfaces exist but core imports concrete adapters anyway
- adapters and core are mutually entangled
- framework annotations/types leak everywhere
- "port" naming exists without dependency inversion

### Layered Architecture Signals

Evidence that supports layered architecture:

- presentation -> application -> domain -> infrastructure shape
- mostly downward dependencies
- service layer mediates access to lower layers
- clear separation between request handling and business rules

Evidence against it:

- lateral cross-layer access everywhere
- handlers reach directly into persistence and external APIs
- no stable middle layer

### Plugin / Extension Architecture Signals

Common in devtools.

Evidence:

- registries of commands/tools/providers
- dynamically discovered modules
- stable extension interfaces
- runtime loading based on config/capabilities
- feature modules independent except for a host contract

### Event-Driven / CQRS Signals

Evidence:

- command and query paths are intentionally separate
- event bus or message broker mediates collaboration
- write model and read model differ materially
- handlers subscribe to domain/integration events

Do not claim CQRS just because commands and queries both exist.

## Step 7: Name the Real Architecture

Use precise language. Most real systems are hybrids.

Good conclusions:

- "Primarily layered, with ports-and-adapters around shell and web integrations"
- "Not strong DDD; more of a modular application with orchestration-centric services"
- "Plugin-oriented devtool with a central agent loop and adapter boundaries for tools and browser automation"
- "Clean-architecture-inspired dependency direction, but domain logic is thin and not modeled as rich aggregates"

Bad conclusions:

- "This is hexagonal" because there is an `adapters/` folder
- "This is DDD" because there is a `domain/` directory
- "This is microservices" because there are multiple packages

## Evidence Collection Checklist

Collect evidence from multiple sources:

- directory structure
- imports and dependency direction
- constructors and interfaces
- bootstrap/composition code
- tests, especially unit tests around core logic
- config files
- docs/README/ADR files
- runtime invocation paths

Prioritize code over marketing words in docs.

## Recommended Output Format

Use this structure when reporting findings.

```markdown
# Architecture Reverse-Engineering Report

## 1. System Purpose

What the software does and who uses it.

## 2. Top-Level Components

| Component  | Responsibility                      | Evidence                                |
| ---------- | ----------------------------------- | --------------------------------------- |
| CLI        | user entrypoint and command parsing | `bin/tool.dart`, `lib/src/commands/...` |
| Agent core | orchestration loop                  | `lib/src/agent/...`                     |

## 3. Dependency Direction

- Presentation depends on application orchestration
- Tool implementations depend on shared tool contracts
- Browser/web integrations sit at the edge

## 4. Representative Execution Flow

Describe one end-to-end slice.

## 5. Architectural Assessment

### Strong evidence

- ...

### Weak/inconclusive evidence

- ...

### Best-fit characterization

- ...

## 6. Boundaries and Layers

| Boundary       | Included Modules | Notes |
| -------------- | ---------------- | ----- |
| Presentation   | ...              | ...   |
| Application    | ...              | ...   |
| Infrastructure | ...              | ...   |

## 7. Risks / Tensions

Where the architecture is inconsistent or leaking.

## 8. Open Questions

What could not be confirmed from available evidence.
```

## Quick Reference: Pattern Recognition

| Pattern             | Positive Signals                                                      | False Positives                            |
| ------------------- | --------------------------------------------------------------------- | ------------------------------------------ |
| DDD                 | rich domain model, bounded contexts, ubiquitous language              | `domain/` folder with DTOs                 |
| Ports & Adapters    | interfaces at core boundary, adapters at edge, inward dependency flow | wrappers named ports without inversion     |
| Layered             | stable presentation/app/domain/infra separation                       | folders named by layer but heavily crossed |
| Plugin Architecture | registries, extension contracts, runtime discovery                    | just many modules                          |
| Event-Driven        | explicit events, subscribers, asynchronous collaboration              | callbacks or observer helpers only         |
| CQRS                | separate write/read models and handlers                               | methods named command/query only           |

## Common Mistakes

| Mistake                                 | Why It Fails                                 | Fix                                          |
| --------------------------------------- | -------------------------------------------- | -------------------------------------------- |
| Starting with labels                    | Forces evidence to fit a preferred pattern   | Start with responsibilities and dependencies |
| Over-trusting folder names              | Names are often aspirational                 | Verify through imports and execution flow    |
| Ignoring runtime composition            | Architecture is often defined in wiring code | Find the composition root early              |
| Reading files randomly                  | Produces trivia, not structure               | Trace entrypoints and one end-to-end slice   |
| Confusing abstraction with architecture | Interfaces alone prove little                | Check actual dependency direction            |
| Declaring one pure style                | Most systems are mixed                       | Describe primary style plus exceptions       |

## Worked Example: Developer Tool / Terminal Agent

Suppose a repo has this shape:

```text
bin/glue.dart
lib/src/app/
lib/src/agent/
lib/src/tools/
lib/src/web/
lib/src/terminal/
lib/src/skills/
lib/src/llm/
```

A good reverse-engineering pass would proceed like this:

1. **Entrypoint**: `bin/glue.dart` starts the app.
2. **Composition**: app/bootstrap code wires together terminal UI, agent core, tool registry, web helpers, and skill loader.
3. **Top-level boundaries**:
   - `terminal/`: presentation/runtime I/O boundary
   - `app/`: application state and event coordination
   - `agent/`: orchestration loop for model/tool interaction
   - `tools/`, `web/`, `skills/`: infrastructure and integration edges
   - `llm/`: provider integration boundary
4. **Representative slice**:
   - user enters prompt in terminal
   - app forwards request to agent core
   - agent decides to call a tool
   - tool layer invokes filesystem/web/browser/shell capabilities
   - result returns to agent, then back to terminal rendering
5. **Architectural read**:
   - this is **not strongly DDD** unless there is a rich business domain model with explicit invariants
   - it is better described as a **modular, layered devtool** with an **orchestration-centric core**
   - if tool, browser, and shell interactions are hidden behind stable contracts selected at the edge, there are **ports-and-adapters traits**
   - if commands/tools/providers are registered dynamically, there is also a **plugin-style extension pattern**

Example conclusion:

> The system is primarily a modular layered developer tool with a central orchestration core. External capabilities such as shell execution, web access, browser control, and skill loading sit at the edges. It shows ports-and-adapters characteristics where integrations are abstracted behind tool and provider contracts, but it is not a pure hexagonal architecture because orchestration concerns dominate and the domain model is thin.

## Final Checklist

- [ ] Identified real entrypoints
- [ ] Mapped top-level modules and responsibilities
- [ ] Verified dependency direction from code, not names
- [ ] Traced at least one end-to-end slice
- [ ] Evaluated multiple candidate patterns with evidence for and against
- [ ] Produced a hybrid architecture description if appropriate
- [ ] Marked uncertainties explicitly
