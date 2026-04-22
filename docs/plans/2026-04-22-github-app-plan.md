# GitHub App for Glue — Research & Plan

Status: **proposed**
Date: 2026-04-22
Owner: unassigned

## Goal

Make Glue usable from GitHub in two complementary ways:

1. **GitHub Actions workflow primitive** — repositories can run Glue inside workflows for CI/CD, review, autofix, issue-to-PR, conflict resolution, and other automation.
2. **GitHub App interaction surface** — users can invoke Glue by **@mentioning** it in issue comments, PR comments, review comments, and optionally via labels / assignments / slash commands.

The desired UX is similar to Junie-on-GitHub:

- runs on the repository's own GitHub runners
- uses the repo checkout as the workspace
- can post progress and results back to GitHub
- can optionally push commits and open/update pull requests
- can be triggered from comments by mention

This plan covers product shape, architecture options, security constraints, MVP scope, and an implementation sequence.

---

## Inspiration and external baseline

The Junie docs show a pragmatic model that fits Glue well:

- a marketplace Action wraps the CLI
- the Action runs entirely on GitHub-hosted or self-hosted runners
- workflows trigger on `issue_comment`, `pull_request_review_comment`, `pull_request_review`, and `issues`
- the workflow gates execution by checking for an `@junie-agent` trigger phrase
- the Action receives API credentials and optional behavior flags
- the Action returns outputs like branch, commit SHA, PR URL, title, and summary

That model is attractive for Glue because it preserves an important property: **the actual code execution happens inside the repo's workflow runner, not inside Glue-operated infrastructure**. For a coding agent, that is the easiest security story and the lowest-friction enterprise story.

---

## Product shape: separate the GitHub App from the Action

The cleanest architecture is to treat these as **two products that work together**:

### 1) `glue-github-action`
A reusable GitHub Action that:

- installs or downloads Glue CLI
- maps GitHub event context into a prompt/task
- optionally configures auth and repo-scoped guidelines
- runs Glue non-interactively
- captures outputs
- optionally posts comments / creates commits / opens PRs

### 2) `Glue GitHub App`
A GitHub App that:

- can be installed on repos/orgs
- receives webhooks for comments, PRs, labels, assignments, and checks
- decides whether a given event should trigger Glue
- can either:
  - **dispatch a workflow in the target repo**, or
  - in a more advanced version, create check runs / comments directly and orchestrate jobs

### Why split them

Because the concerns are different:

- **Action** = execution packaging inside GitHub runners
- **App** = identity, permissions, webhook intake, routing, trigger semantics

Trying to make the App do the actual code execution would push Glue toward a hosted execution service. That is possible later, but it is the wrong MVP.

---

## Recommended architecture: App triggers workflows; Action runs Glue

### High-level flow

1. User writes a comment like `@glue fix this failing test` on an issue or PR.
2. GitHub sends a webhook to the Glue GitHub App.
3. The App validates:
   - event type is supported
   - app is mentioned or a supported slash command/label is present
   - installation/repo is allowed
   - actor is allowed by repo policy
4. The App calls the target repository's GitHub API using an installation token to trigger a workflow, ideally via `repository_dispatch` or `workflow_dispatch`.
5. That workflow checks out the repo and runs `glue-github-action`.
6. The Action invokes Glue CLI with a synthesized prompt and GitHub context.
7. Glue makes changes / produces a review / writes outputs.
8. The Action posts a status comment, inline review comments, commit(s), or opens/updates a PR.

### Why this is the right default

- Keeps execution on customer infrastructure.
- Uses GitHub's native workflow permissions model.
- Avoids the App needing clone/push/execution infrastructure.
- Lets repos customize workflows without changing the App.
- Matches existing successful patterns in Copilot Workspace / agentic Actions / Junie-like integrations.

---

## Deployment model options

## Option A — Action only, no GitHub App

Repositories add a workflow like:

- trigger on issue/PR comment events
- check `contains(comment.body, '@glue')`
- run `uses: glue-labs/glue-github-action@v1`

### Pros
- Fastest to ship
- No hosted App/backend needed
- Zero webhook server
- Entirely repo-controlled

### Cons
- `@glue` is just text matching, not a real GitHub App mention
- no app identity, no installation flow
- cannot centralize policy or per-installation config
- UX is weaker: anyone can type the trigger phrase unless workflow adds guards

### Assessment
This is the fastest MVP and should likely ship first even if the long-term target is a GitHub App.

---

## Option B — GitHub App + Action, with App dispatching workflows

The App receives mentions and dispatches repo workflows.

### Pros
- Real `@glue` mention UX
- Native installation permissions model
- Central trigger routing and policy
- Better provenance and auditability
- Future path to richer GitHub integration (checks, review threads, config UI)

### Cons
- Requires hosted webhook service
- Requires installation token management and event handling
- More moving parts

### Assessment
This is the recommended target architecture.

---

## Option C — GitHub App runs Glue on Glue-managed infrastructure

The App clones repos and runs Glue in Glue-controlled workers.

### Pros
- Minimal setup in customer repos
- Can work without repository workflows
- Full Glue control over runtime and caching

### Cons
- Worst security/compliance story
- Requires full hosted execution platform
- Must securely clone private repos and manage secrets
- Much larger operational burden

### Assessment
Do not do this for V1.

---

## Core GitHub surfaces to support

## Trigger events

Recommended support matrix:

### V1
- `issue_comment.created`
- `pull_request_review_comment.created`
- `pull_request_review.submitted`
- `issues.opened` only when body/title includes mention
- optional: `issues.labeled`
- optional: `issues.assigned`

### V2
- `pull_request.opened` for auto-review
- `check_suite.completed` / `workflow_run.completed` for CI autofix loops
- `pull_request.synchronize` for re-review
- `discussion_comment.created` if discussions matter

## Invocation styles

Support these in order:

1. **@mention**: `@glue fix the lint failures`
2. **Slash command in a comment**: `/glue fix`
3. **Label trigger**: `glue`
4. **Assignment trigger**: assign the app bot/user

### Important GitHub nuance
Real **@mention** behavior is strongest when Glue is a real installed GitHub App/bot identity. Without the App, repositories can only emulate this with text matching.

---

## Recommended user experience

## PR comment invocation

Example:

`@glue address this review feedback and push a fix`

Expected behavior:
- App acknowledges with a reaction or comment
- workflow starts
- Glue checks out the PR head branch
- Glue applies changes
- Glue pushes commit(s) to the PR branch or to a new branch, based on policy
- Glue posts a completion comment with summary

## Issue invocation

Example:

`@glue implement this and open a PR`

Expected behavior:
- workflow creates a new working branch from default/base branch
- Glue implements the requested change
- Action opens a PR linked to the issue
- completion comment includes PR URL

## Review invocation

Example:

`@glue fix all actionable comments in this review`

Expected behavior:
- workflow gathers unresolved review comments / review body
- Glue edits code accordingly
- posts summary with commit SHA or PR link

## Automated review workflow

Example workflow:
- on `pull_request.opened` or label `glue-review`
- run Glue in read-only / no-write mode
- post review summary and possibly inline comments

This does not require mention-based invocation and should be a first-class Action use case.

---

## Action design

## Recommended deliverable
Publish a dedicated repository, likely:

- `glue-labs/glue-github-action`

Implementation form should be one of:

### Prefer: JavaScript action wrapping a released Glue binary
Why:
- easy to publish to marketplace
- straightforward inputs/outputs
- can download platform-specific Glue release artifact
- no Docker-only limitation
- works on GitHub-hosted runners across OSes

### Alternative: composite action
Works if setup logic remains simple, but JS gives more control for outputs, event parsing, retries, and API calls.

### Avoid for V1: Docker action
Too limiting for enterprise and slower/coupled to Linux.

## Action responsibilities

The Action should:

1. Install Glue CLI
2. Gather GitHub event context
3. Compute whether to skip
4. Build a prompt/task envelope
5. Run Glue headlessly
6. Expose outputs
7. Optionally post progress/result comments

## Suggested inputs

### Trigger/config
- `trigger_phrase` default `@glue`
- `label_trigger`
- `assignee_trigger`
- `mode` (`comment`, `review`, `issue-to-pr`, `ci-fix`, `custom`)
- `prompt`
- `model`
- `working_directory`
- `base_branch`
- `create_new_branch_for_pr` bool
- `push_mode` (`none`, `pr-branch`, `new-branch`)
- `open_pull_request` bool
- `review_mode` (`summary`, `inline`, `summary+inline`)
- `silent_mode` bool
- `use_single_comment` bool
- `guidelines_filename` default maybe `AGENTS.github.md` or configurable override

### Auth
- `glue_api_key` or provider-specific keys
- `github_token` optional override, else use `${{ github.token }}`

### Safety/policy
- `allow_actor_association` list (`OWNER`, `MEMBER`, `COLLABORATOR`)
- `fork_policy` (`skip`, `read-only`, `require-approval`)
- `max_minutes`
- `approval_mode` if Glue supports noninteractive permission policy selection

## Suggested outputs
- `should_skip`
- `branch_name`
- `commit_sha`
- `pr_url`
- `result_title`
- `result_summary`
- `comment_url`
- `run_url`

---

## Glue CLI requirements for GitHub use

Glue already has a strong CLI core, but GitHub usage likely needs a thin GitHub-specific layer.

## Recommended new surface: noun namespace, not a one-off top-level verb

Per repo conventions, prefer something like:

- `glue github run`
- `glue github context`
- `glue github comment`
- `glue github review`

Rather than a one-off root verb.

## Minimal CLI features needed

### 1) Headless task execution entrypoint
The Action needs a stable non-interactive interface that can:

- accept a prompt
- read GitHub event payload / context from JSON
- run in a given working tree
- emit structured JSON outputs

Possible shape:

```bash
glue github run \
  --event-path "$GITHUB_EVENT_PATH" \
  --event-name "$GITHUB_EVENT_NAME" \
  --repo "$GITHUB_REPOSITORY" \
  --json \
  --prompt-file /tmp/glue-prompt.md
```

### 2) Structured output contract
Need machine-readable result schema, e.g.:

- title
- summary
- changed_files
- commit_sha
- branch_name
- pr_url
- inline_comments[]
- should_skip

### 3) GitHub-context prompt builder
Glue should understand common GitHub contexts:

- issue body/title/comments
- PR title/body/files changed
- review comments / review body
- failed checks summary

This can live in the Action initially, but long-term likely belongs in CLI/library code for testability.

### 4) Safe branch/commit helpers
GitHub workflows need repeatable branch naming and PR behavior.

Examples:
- `glue/<issue-number>-slug`
- `glue/pr-123/fix-review-comments`
- `glue/run-<run-id>`

This may be easier in the Action using git + GitHub API, but Glue may need conventions documented.

---

## GitHub App architecture

## Components

### 1) Webhook service
Small service that:
- receives GitHub webhooks
- verifies signature
- parses event payload
- determines whether invocation criteria match
- creates installation token
- dispatches target workflow
- optionally posts acknowledgment comments/status

Technology choice does not need to be Dart. A small TypeScript service is likely operationally simpler because Octokit and GitHub App tooling are mature there.

### 2) Installation config store
Need per-installation/repo config, likely including:
- enabled triggers
- allowed actors / orgs
- workflow filename or dispatch target
- default mode/prompt/model
- whether write operations are allowed
- fork policy

### 3) Dispatcher
Turns webhook events into one of:
- `repository_dispatch`
- `workflow_dispatch`

### 4) Optional callback/commenter
Posts a lightweight acknowledgment comment like:
- "Glue picked this up — starting workflow: <run link>"

This is optional for MVP because the Action can comment once it starts.

---

## Dispatch mechanism choice

## Prefer `repository_dispatch` for App -> repo trigger

Why:
- GitHub App can fire a custom event with a payload
- target workflow can be generic and event-driven
- easier to pass rich normalized payload than `workflow_dispatch` inputs

Example:
- App sends event type `glue.invoke`
- payload includes event kind, installation id, repo, issue/pr numbers, comment id, actor, extracted instruction, trigger metadata

Workflow example:

```yaml
on:
  repository_dispatch:
    types: [glue.invoke]
```

### Alternative: `workflow_dispatch`
Works, but inputs are more rigid and less ergonomic for rich event payloads.

### Recommendation
Use `repository_dispatch` for App-triggered flows, but also support direct event-triggered workflows for the Action-only mode.

---

## Security model

This is the hard part and should drive scope.

## Principles

1. **Run code on the repository's runner, not Glue servers.**
2. **Treat comment-triggered write access as high risk.**
3. **Assume untrusted input in comments, issues, and PRs.**
4. **Never give write-capable secrets to workflows triggered by untrusted fork content without explicit safeguards.**

## Main risks

### 1) Prompt injection from issue/PR/comment content
Users can say anything in comments, including instructions to exfiltrate secrets or rewrite workflow files.

Mitigations:
- use explicit system/task framing for GitHub runs
- default to least privilege
- support read-only/review-only modes
- optionally require human approval before write operations
- allow orgs to provide GitHub-specific guidelines/policy file

### 2) Forked PR privilege escalation
A comment on a PR from a fork can trigger privileged workflows if not handled carefully.

Mitigations:
- default `fork_policy=skip`
- if supporting forks, only allow read-only review mode
- never checkout untrusted fork code with write token + secrets in the same workflow unless there is a deliberate approval design
- avoid `pull_request_target` for write-capable execution on untrusted code unless the design is extremely constrained

### 3) Bot abuse / spam / cost amplification
Anyone who can comment could repeatedly trigger Glue.

Mitigations:
- actor allowlist by association (`OWNER`, `MEMBER`, `COLLABORATOR`)
- rate limiting per issue/PR/repo/user
- dedupe on identical comment IDs / delivery IDs
- concurrency control in workflows

### 4) Excessive repo permissions
Glue does not always need all write scopes.

Mitigations:
- document minimal permissions per workflow mode
- review-only mode: `contents: read`, `pull-requests: write` maybe `issues: write`
- fix mode: add `contents: write`
- issue-to-pr mode: add `contents: write`, `pull-requests: write`

## Permissions guidance

### Review-only workflow
- `contents: read`
- `pull-requests: write`
- `issues: write` if posting issue comments

### Fix / commit workflow
- `contents: write`
- `pull-requests: write`
- `issues: write`

### Optional checks integration
- `checks: write`

---

## Handling comments and mentions correctly

## Trigger parsing
The App should normalize invocation from:
- issue comments
- PR review comments
- review body comments
- issue title/body

Needed parser outputs:
- `triggered: bool`
- `kind: mention | slash | label | assignment`
- `instruction_text`
- `target_type: issue | pr | review | comment`
- `target_number`
- `comment_id` if any

## Suggested parsing rules

### Mention
- support `@glue` or actual bot login once registered
- strip the mention token from the remaining instruction
- if nothing remains, use a mode-specific default prompt like "Review this PR" or "Implement this issue"

### Slash command
Examples:
- `/glue review`
- `/glue fix`
- `/glue continue`

Useful even with App mentions because slash commands are easier to parse and less dependent on account naming.

### Labels / assignment
Map labels/assignment to predefined modes rather than free-form instructions.

---

## Prompt and context synthesis

The GitHub integration should not just pass raw comment text. It should build a structured task envelope.

## Recommended envelope contents

- repository: owner/name
- event kind
- base/head refs
- issue or PR title/body
- triggering comment body
- relevant review comments
- changed files summary for PRs
- failed checks summary if applicable
- explicit policy block:
  - whether writes are allowed
  - whether opening PRs is allowed
  - whether inline comments are allowed
  - actor trust level

This can be represented either as markdown with clear sections or structured XML/JSON injected into the prompt.

## Why this matters
It reduces ambiguity and keeps Glue from overfitting to a single free-form comment without understanding surrounding GitHub context.

---

## Posting results back to GitHub

## V1 result surfaces

### 1) Single summary comment
Always useful. Include:
- title
- short summary
- branch / commit / PR URL if created
- maybe touched files

### 2) PR creation/update
For issue-to-PR or fix tasks.

### 3) Commit push to current PR branch
For trusted same-repo PRs only.

## V2 result surfaces

### 4) Inline review comments
High value for review mode, but trickier because mapping model findings to exact lines in a changing diff is nontrivial.

### 5) Check runs
Could provide cleaner UX than comments for status/progress and review summaries.

### Recommendation
V1 should optimize for **summary comments + branch/commit/PR outputs**. Inline comments can wait.

---

## Repo configuration model

Need a repository-level config file so behavior is not hardcoded in workflow YAML alone.

Suggested options:

- `.glue/github.yaml`
- `.glue/github.yml`

Possible fields:

```yaml
version: 1
triggers:
  mention: true
  slash: true
  labels: [glue]
  actor_associations: [OWNER, MEMBER, COLLABORATOR]
policy:
  allow_push_to_pr_branch: true
  allow_new_prs: true
  fork_policy: skip
  default_mode: comment
prompting:
  guidelines_file: AGENTS.github.md
  review_prompt: |
    Focus on correctness, security, and regression risk.
workflows:
  dispatch_event_type: glue.invoke
```

The App can read this via contents API or leave it to the workflow/Action.

### Recommendation
For MVP, keep config in workflow inputs first. Add `.glue/github.yaml` once real usage patterns emerge.

---

## Recommended implementation sequence

## Phase 0 — Research and design lock

Deliverables:
- this plan
- explicit decision on MVP architecture
- threat model notes

### Recommendation
Lock in:
- **MVP-1:** Action-only with direct workflow triggers and text-based `@glue` matching
- **MVP-2:** GitHub App that dispatches `repository_dispatch` to the same Action-backed workflow

This de-risks the App by first proving the runner-side execution model.

---

## Phase 1 — Ship `glue-github-action` without a GitHub App

### Scope
- create marketplace-ready Action repo
- support direct workflows triggered by native GitHub events
- support text-based `@glue` matching in comments/issues/reviews
- run Glue headlessly
- output result metadata
- optionally create summary comment / commit / PR

### Required work

#### A. Define a stable headless execution contract in Glue CLI
Need a reliable noninteractive interface for GitHub usage.

Likely work in `cli/`:
- add `glue github run` command family
- add structured JSON result output
- add event/context ingestion from `GITHUB_EVENT_PATH`

#### B. Build Action wrapper
In separate repo:
- install/download Glue release
- parse workflow inputs
- invoke `glue github run`
- set outputs
- optionally call GitHub API for comments/PRs

#### C. Publish workflow cookbook
Examples:
- comment-triggered fix
- issue-to-PR
- automated PR review
- CI failure fixer

### Example user workflow

```yaml
name: Glue
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  pull_request_review:
    types: [submitted]

jobs:
  glue:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@glue')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@glue')) ||
      (github.event_name == 'pull_request_review' && contains(github.event.review.body, '@glue'))
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
    steps:
      - uses: actions/checkout@v4
      - uses: glue-labs/glue-github-action@v1
        with:
          glue_api_key: ${{ secrets.GLUE_API_KEY }}
```

### Exit criteria
- Action can be used in any repo without the App
- comment-triggered execution works
- issue-to-PR workflow works on trusted repos
- review-only mode works

---

## Phase 2 — Add GitHub App as trigger/router

### Scope
- register GitHub App
- build webhook service
- support real app mentions
- dispatch `repository_dispatch` to target repos

### Required work

#### A. Create App manifest and permissions
Likely permissions:
- Repository contents: read
- Pull requests: read/write
- Issues: read/write
- Metadata: read
- Actions: read/write? maybe not needed depending on dispatch mechanism
- Checks: optional later

Events:
- issue_comment
- pull_request_review_comment
- pull_request_review
- issues
- maybe pull_request

#### B. Build webhook receiver
Responsibilities:
- signature verification
- idempotency on delivery ID
- trigger parsing
- actor trust checks
- dispatch

#### C. Define dispatch payload schema
Example:

```json
{
  "event_type": "glue.invoke",
  "client_payload": {
    "version": 1,
    "source_event": "issue_comment",
    "installation_id": 123,
    "repository": "owner/repo",
    "issue_number": 42,
    "comment_id": 555,
    "trigger": {
      "kind": "mention",
      "raw": "@glue fix this",
      "instruction": "fix this"
    },
    "actor": {
      "login": "alice",
      "association": "MEMBER"
    }
  }
}
```

#### D. Provide a standard workflow template
Repos install App + add workflow listening to `repository_dispatch`.

### Exit criteria
- real App mention starts the repo workflow
- same Action does the execution
- workflow receives normalized payload from App

---

## Phase 3 — Harden security and expand modes

### Scope
- fork-safe policies
- check-run integration
- CI failure autofix
- better progress UX
- optional inline review comments

### Work items
- add actor trust policy
- add concurrency/dedup/rate limits
- support `workflow_run` or checks-based triggers
- add read-only fork mode
- add optional approval gate before writes

---

## Proposed MVP boundaries

## In scope for MVP-1
- Action-only
- direct workflow invocation on comments/issues/reviews
- text-based `@glue` trigger phrase
- summary comment output
- branch/commit/PR outputs
- issue-to-PR and PR-fix flows

## Out of scope for MVP-1
- real GitHub App
- inline review comment MCP-like precision
- hosted execution
- fork-write support
- complex per-installation config UI

## In scope for MVP-2
- GitHub App webhook service
- real mention-based trigger
- `repository_dispatch`
- installation-level routing/config

## Out of scope for MVP-2
- running code outside Actions
- full SaaS control plane

---

## Specific recommendations for Glue repo changes

## 1) Add a plan before surface expansion
This document is that plan and aligns with repo guidance for non-trivial command families.

## 2) Add a new CLI noun namespace: `glue github ...`
Recommended initial commands:
- `glue github run` — execute a GitHub-scoped task headlessly
- `glue github context` — print normalized GitHub context as JSON for debugging

Do not add slash commands for this; this is a non-interactive/scriptable surface.

## 3) Keep GitHub-specific API logic mostly out of the TUI app
This work belongs in:
- `cli/lib/src/commands/`
- a new `cli/lib/src/github/` module for event normalization / prompt synthesis / outputs

Suggested new internal area:
- `cli/lib/src/github/`
  - `event_parser.dart`
  - `context_builder.dart`
  - `prompt_builder.dart`
  - `result.dart`
  - `github_run_command.dart`

## 4) Prefer Action repo + App repo outside this monorepo
This repo should hold the CLI functionality and docs.
Separate repos are cleaner for:
- GitHub Action marketplace packaging
- GitHub App service deployment
- release cadence differences

---

## Open questions

1. **Should the App/backend be implemented in Dart or TypeScript?**
   Recommendation: TypeScript for App/backend; Dart for CLI only.

2. **Should summary comments be posted by the Action or by Glue CLI itself?**
   Recommendation: Action posts them. Keep CLI provider-agnostic and emit structured results.

3. **Should branch/PR management live in CLI or Action?**
   Recommendation: mostly Action/workflow, unless repeated logic becomes painful.

4. **Do we want real inline review comments in V1?**
   Recommendation: no.

5. **What should the trigger handle be?**
   `@glue` is ideal if available; actual GitHub App bot naming may constrain final UX.

6. **How should fork PRs be treated?**
   Recommendation: skip by default; maybe allow read-only review later.

7. **Do we want Glue-specific GitHub guidelines file naming?**
   Maybe support override like `AGENTS.github.md`, but avoid premature proliferation.

---

## Concrete next steps

1. **Approve architecture**
   - Decide Action-only MVP first, App second.

2. **Create implementation spec for CLI changes**
   - define `glue github run` inputs/outputs
   - define normalized GitHub context schema

3. **Prototype Action in separate repo**
   - JS action downloading Glue release
   - one cookbook workflow for comment-triggered PR fixes

4. **Test on same-repo PRs and issue-to-PR flow**
   - verify permissions and branch behavior

5. **Write security guidance**
   - especially around forks and `pull_request_target`

6. **Only then build the GitHub App**
   - webhook receiver
   - repository dispatch
   - install docs

---

## Recommended final decision

If the question is "how could we create Glue as a GitHub App for Actions workflows and @mentions?", the recommended answer is:

- **Do not start with a hosted execution GitHub App.**
- **Start with a reusable GitHub Action that runs Glue on repo runners.**
- **Then add a lightweight GitHub App whose main job is routing @mentions into `repository_dispatch` events that invoke that same Action-backed workflow.**

That gives Glue:
- a simple security story
- a good enterprise story
- a fast path to value
- a real future GitHub App UX
- minimal duplication between workflow and comment-triggered use cases
