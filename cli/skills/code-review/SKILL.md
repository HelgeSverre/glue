---
name: code-review
description: Use when reviewing code changes — PRs, diffs, pre-commit review, or self-review before merging. Triggers on requests to review code, check for bugs, audit security, or assess code quality. Also use before completing any significant implementation to catch issues.
---

# Systematic Code Review

## Principles

1. **Diff-based**: Always start from `git diff`, never by reading whole files cold
2. **Surgical scope**: Review only what changed — don't critique pre-existing code unless it's now broken
3. **Severity-classified**: Every finding gets a severity so the author knows what to fix first
4. **Evidence-based**: Every finding includes the specific file, line, and what's wrong — never vague

## Trigger: When to Use This Skill

- User asks to review a PR, diff, or set of changes
- Self-review before committing significant work
- Pre-merge verification of a feature branch
- Security audit of changed code

## Step 1: Get the Diff

Always start by understanding what actually changed.

```bash
# For uncommitted changes
git diff                    # Unstaged changes
git diff --cached           # Staged changes
git diff HEAD               # Both staged and unstaged

# For a PR / branch
git diff main...HEAD        # Changes on this branch since diverging from main
git log main..HEAD --oneline  # Commits on this branch

# For a GitHub PR (preferred when reviewing PRs)
gh pr diff <number>         # View PR diff
gh pr view <number>         # PR description and metadata
gh pr checks <number>       # CI status

# For a specific commit
git show <sha>              # Single commit diff
```

**Read the diff output.** Do not start reviewing by reading entire files. The diff tells you what changed — that's what you're reviewing.

## Step 2: Understand Context

For each changed file, read enough surrounding context to understand what the change does:

```bash
# Read the file around changed lines
# (use Read tool with the specific file)
```

Ask yourself:
- What is this change trying to accomplish?
- Does every changed line trace to that goal? (Karpathy's "surgical changes" test)
- Are there lines that changed but shouldn't have (formatting, unrelated refactors)?

## Step 3: Review in Priority Order

Review concerns in this order. Stop and report critical issues immediately — don't continue to style nits if there's a security vulnerability.

### Priority 1: Security

| Check | What to Look For |
| --- | --- |
| Injection | SQL strings built with concatenation/interpolation, unsanitized HTML rendering, command injection via `exec`/`eval`/`subprocess` with user input |
| Auth/authz | Missing authentication checks on endpoints, broken authorization (user A can access user B's data), hardcoded credentials or API keys |
| Secrets | `.env` files, API keys, passwords, tokens in committed code — check new files AND diffs |
| Data exposure | Stack traces returned to users, verbose error messages with internal details, PII in logs |
| SSRF/redirect | User-controlled URLs used in server-side requests, open redirects |

### Priority 2: Correctness

| Check | What to Look For |
| --- | --- |
| Logic errors | Off-by-one, wrong comparison operator, inverted conditions, short-circuit evaluation bugs |
| Null/undefined | Accessing properties on potentially null values without checks |
| Race conditions | Shared mutable state without synchronization, TOCTOU bugs, concurrent map access (Go) |
| Error handling | Swallowed errors (`catch {}` with no action), errors that should propagate but don't, missing error returns |
| Edge cases | Empty arrays/strings, zero values, negative numbers, Unicode, very large inputs |
| Type safety | Implicit type coercion bugs (JS `==` vs `===`), unchecked type assertions (Go/TS) |

### Priority 3: Performance

Only flag if the change introduces a **measurable** concern:

| Check | What to Look For |
| --- | --- |
| N+1 queries | Database query inside a loop — should be batched |
| Missing indexes | New queries on columns without indexes |
| Memory leaks | Event listeners not cleaned up, growing caches without eviction, unclosed resources |
| Unnecessary work | Computing the same thing repeatedly, loading more data than needed |
| Blocking operations | Synchronous I/O on async paths, long-running operations on the main thread |

### Priority 4: Maintainability

Lower priority — these should not block merging:

| Check | What to Look For |
| --- | --- |
| Naming | Misleading names (function named `getUser` that also deletes), abbreviations that aren't obvious |
| Complexity | Functions doing too many things, deeply nested conditionals that could be early returns |
| Duplication | Same logic copy-pasted (but only if it's in the new code — don't flag pre-existing duplication) |
| Tests | New functionality without tests, tests that don't actually assert anything meaningful |

## Step 4: Verify Claims

When the diff includes version numbers, API usage, or deprecation-related changes:

- **Web search** to verify the claimed API exists in the stated version
- **Check changelogs** for deprecation claims
- **Verify dependency compatibility** for version bumps

Do not trust comments like "// deprecated in v3" without verification.

## Step 5: Report Findings

### Severity Levels

| Severity | Meaning | Action |
| --- | --- | --- |
| **CRITICAL** | Security vulnerability, data loss risk, crash in production | Must fix before merge |
| **HIGH** | Bug that will cause incorrect behavior, missing error handling for likely cases | Should fix before merge |
| **MEDIUM** | Performance issue, missing edge case handling, test gap | Fix soon, can merge with follow-up |
| **LOW** | Style nit, naming suggestion, minor improvement | Optional, author's discretion |

### Output Format

Report each finding as:

```
### [SEVERITY] Title

**File:** `path/to/file.ts:42`
**Category:** Security | Correctness | Performance | Maintainability

**Issue:** What's wrong, specifically. Include the problematic code.

**Why it matters:** What could go wrong if this isn't fixed.

**Suggestion:**
\`\`\`
// Concrete fix, not just "consider improving this"
\`\`\`
```

### Summary Table

End with a summary:

```
| # | Severity | File | Issue |
|---|----------|------|-------|
| 1 | CRITICAL | auth.ts:23 | SQL injection in user lookup |
| 2 | HIGH | api.ts:89 | Missing null check on response |
| 3 | LOW | utils.ts:12 | Misleading function name |
```

### Verdict

End every review with one of:

- **Approve** — No critical/high issues, ready to merge
- **Request changes** — Critical or high issues must be addressed
- **Comment** — Suggestions only, author decides

### Submitting Review on GitHub PRs

```bash
# Approve
gh pr review <number> --approve --body "LGTM. [summary of what you verified]"

# Request changes
gh pr review <number> --request-changes --body "$(cat <<'EOF'
## Review Findings

[your findings table here]

## Required Changes
- [ ] Fix [critical issue]
- [ ] Address [high issue]
EOF
)"

# Comment only (for suggestions/nits)
gh pr review <number> --comment --body "[your findings]"
```

## Self-Review Mode

When reviewing your own code before committing:

1. Run `git diff --cached` (or `git diff HEAD` for all changes)
2. Apply the same priority order above
3. Be especially strict on:
   - Did I change anything I didn't need to? (surgical changes test)
   - Did I introduce any security issues?
   - Did I handle errors properly?
   - Would a reviewer understand why every line changed?
4. Fix issues before committing — don't leave known problems for reviewers

## Anti-Patterns in Code Review

Things to avoid when reviewing:

| Anti-Pattern | Why It's Bad |
| --- | --- |
| "LGTM" with no substance | Rubber-stamping helps nobody |
| Reviewing style before correctness | Find the bug first, nit the naming later |
| Blocking on style preferences | If it works and is readable, let it go |
| Reviewing pre-existing code | Only review what changed in this diff |
| "I would have done it differently" | Different isn't wrong — only flag actual issues |
| Vague feedback ("this seems wrong") | Be specific: what's wrong, why, and how to fix it |

## Verification

Before finalizing a review:

- [ ] Started from the diff, not from reading whole files
- [ ] Every finding has a specific file, line number, and concrete suggestion
- [ ] Severity is assigned to every finding
- [ ] Security concerns were checked first
- [ ] No findings about pre-existing code that wasn't changed in this diff
- [ ] Summary table and verdict included
