---
name: skill-creator
description: Use when authoring or editing a glue skill — designing frontmatter, writing the body, classifying skill type, or judging whether a draft is ready. Triggers on creating new skills under cli/skills/ (builtin) or ~/.glue/skills/ (user), and when the user asks to turn a doc, methodology, or CLI reference into a glue skill.
---

# Skill Creator

A guide for writing glue skills that future agent runs will actually find and apply correctly. The two highest-leverage choices are:

1. **Classify the skill type** before writing — Reference, Technique, Pattern, and Discipline skills each have a different rigor bar.
2. **Write the description as triggering conditions only** — never summarize the workflow, or agents will follow the description and skip the body.

The rest of this skill is structure and anti-patterns built around those two choices.

## What a glue skill is

A skill is a directory under one of the discovery roots, containing a `SKILL.md` with YAML frontmatter and a markdown body. The agent invokes a skill via the `skill` tool; the body is injected into the conversation as a synthetic tool result.

**Discovery precedence** (first match wins, see `cli/skills/README.md`):

1. `.glue/skills/<name>/` in the workspace — `project`
2. `skill_paths` entries from config — `custom`
3. `~/.glue/skills/<name>/` — `global`
4. Bundled skills in `cli/skills/<name>/` — `builtin`

**Frontmatter constraints** (enforced by `cli/lib/src/skills/skill_parser.dart`):

| Field           | Required | Rule                                                                                                    |
| --------------- | -------- | ------------------------------------------------------------------------------------------------------- |
| `name`          | yes      | 1–64 chars, lowercase alphanumeric + hyphens, no consecutive hyphens, **must equal the directory name** |
| `description`   | yes      | non-empty, ≤ 1024 characters                                                                            |
| `license`       | no       | string                                                                                                  |
| `compatibility` | no       | string, ≤ 500 characters                                                                                |
| `metadata`      | no       | flat key→string map                                                                                     |
| `allowed-tools` | no       | accepted by the parser but not yet consumed                                                             |

Unknown fields are rejected. Validation is strict — a malformed frontmatter blocks the skill from loading.

## Pick the skill type first

Different types need different treatment. Mis-classifying a skill is the most common reason a skill ships as a thin wrapper around its description.

| Type           | One-line test                                                               | Rigor bar                                                               |
| -------------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| **Reference**  | "Does it document an API, CLI, or config surface?"                          | Get the facts right; cite a refresh path; staleness is the failure mode |
| **Technique**  | "Does it teach a method to apply?"                                          | One excellent worked example beats five mediocre ones                   |
| **Pattern**    | "Does it teach a way of thinking?"                                          | Show recognition cues _and_ a counter-example of when not to apply      |
| **Discipline** | "Does it enforce a rule the agent will be tempted to break under pressure?" | Pressure-test with subagents — see `testing-with-subagents.md`          |

Reference skills do not need the TDD-style pressure testing that discipline skills do. Discipline skills do not need the heavy code surface that reference skills do. Naming the type up front prevents you from importing the wrong amount of ceremony.

## Write the description (the load-bearing section)

The description appears in the agent's system prompt as part of `<available_skills>`. It is what the agent reads to decide whether to load this skill on a given turn. It is not a summary of what the skill teaches.

**The rule:** description = triggering conditions, not workflow.

This rule is empirical, not stylistic. Skills whose descriptions summarize their workflow have been observed to cause agents to follow the description and skip the body — including skipping flowchart steps that the description compressed away. Descriptions written as pure triggers force the agent to read the body to learn what to do.

**Format:**

- Start with **"Use when…"** then concrete triggers — symptoms, error messages, command names, file types, user phrasings.
- Third person. The description is injected into a system prompt, not spoken to the user.
- Include synonyms agents might search by (errors _and_ the friendly name; "flaky" _and_ "race condition").
- ≤ 1024 chars (parser limit), but aim much lower; long descriptions are noise in the system prompt.

```yaml
# Bad — summarizes workflow; agent follows the description and skips the body
description: Use this skill to write a code review by getting the diff, reading context, and classifying findings by severity.

# Bad — vague, no triggers
description: For code review.

# Good — pure triggers, no workflow leaked
description: Use when reviewing code changes — PRs, diffs, pre-commit review, or self-review before merging. Triggers on requests to review code, check for bugs, audit security, or assess code quality.
```

If you find yourself writing "this skill does X, Y, Z" in the description, stop and rewrite it as "Use when …".

## Body structure

A SKILL.md body should follow roughly this shape, with sections trimmed for the skill type:

1. **One-paragraph overview.** What this is, the core principle, why it matters in 2–3 sentences.
2. **When to use** (technique/pattern/discipline). Bullets of concrete situations. Include "when _not_ to use" for pattern skills.
3. **The actual content.** Steps for techniques, decision rules for patterns, frontmatter and field tables for references.
4. **Quick reference.** Table or short bullets for scanning. Especially valuable for reference skills.
5. **Common mistakes.** What goes wrong when applying the skill. Pair each with the fix.
6. **One excellent worked example.** Concrete, complete, runnable if it's code. Pick one language for code examples — porting to multiple languages dilutes quality and adds maintenance load.

A glue skill should normally land between 150 and 450 lines. Look at `cli/skills/code-review/SKILL.md` (~230 lines) and `cli/skills/agentic-research/SKILL.md` (~350 lines) as in-house references for tone and density.

## Self-contained vs. supporting files

Default to keeping everything inline. Split a sibling file out only when:

- A reference section exceeds ~100 lines (API tables, exhaustive flag lists).
- You are shipping a reusable template, script, or test harness.
- A discipline skill needs a deeper testing methodology — see `testing-with-subagents.md` in this skill for the in-house pattern.

When linking siblings, use the **relative path** in markdown:

```markdown
See `testing-with-subagents.md` for the pressure-testing methodology.
```

The `bundled_skills_test.dart` suite verifies that every relative markdown link in a builtin resolves on disk, so broken sibling references will fail CI.

## Anti-patterns

| Anti-pattern                                                    | Why it hurts                                                                                                 |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Description that summarizes the workflow                        | Agents follow the description and skip the body                                                              |
| Narrative storytelling ("In session 2026-04-25 we discovered…") | Anchors the skill to a specific incident; not reusable                                                       |
| Multi-language ports of the same example                        | Mediocre quality across all of them, plus maintenance burden                                                 |
| Generic step labels (`step1`, `helper2`, `pattern3`)            | Labels should carry semantic meaning; reading them in isolation should make sense                            |
| Force-loading other skills via `@path` syntax                   | Burns context unconditionally; reference by skill name and let the agent decide to load                      |
| Flowcharts where a table would do                               | Flowcharts are for non-obvious _decisions_. Linear steps go in numbered lists; reference data goes in tables |
| Long, vague descriptions                                        | The description is in every system prompt; treat it like an API surface, not a marketing blurb               |

## Discipline skills: validate under pressure

If the skill enforces a rule the agent will be tempted to break (TDD, "always run tests before claiming done", "never skip frontmatter validation"), validate it the same way you'd validate any rule — with adversarial scenarios. The methodology lives in `testing-with-subagents.md` (RED-GREEN-REFACTOR adapted for skills, dispatched via the `spawn_subagent` tool).

Reference, technique, and pattern skills don't need this. Don't import the ceremony if the skill type doesn't warrant it.

## Worked example: turning a CLI reference into a Reference skill

The `mcporter` skill in `~/.claude/skills/mcporter/SKILL.md` was authored from `https://github.com/steipete/mcporter/blob/main/docs/cli-reference.md` using exactly this skill. The mechanics were:

1. **Classify the type.** Official CLI docs → Reference skill. No pressure testing needed.
2. **Fetch the source verbatim.** `gh api repos/steipete/mcporter/contents/docs/cli-reference.md --jq '.content' | base64 -d`. Record the refresh command in the skill itself so future agents can re-pull on staleness.
3. **Write the description as triggers only.** "Use when working with the mcporter CLI — `mcporter list`, `mcporter call`, `mcporter generate-cli`, `mcporter emit-ts`, ad-hoc MCP endpoints…" Concrete subcommand names act as keywords for discovery.
4. **Preserve the upstream structure.** Per-subcommand sections with flags inline. Add a Quick Reference table at the end.
5. **Add a Gotchas section.** Pull from README and changelog notes — things that aren't in the CLI help text but bite users (auth promotion, ad-hoc persistence, version-specific coercion behavior).
6. **Skip everything that didn't apply.** No worked example beyond the upstream code blocks; no pressure scenarios; no rationalization tables. Reference skills earn their keep by being correct, current, and findable.

Total elapsed authoring time was minutes, not hours, because the type classification cut out the discipline-skill ceremony.

## Checklist before declaring a skill done

- [ ] Frontmatter parses (`parseSkillFrontmatter` accepts it without error).
- [ ] `name` matches the directory name.
- [ ] Description is "Use when…" triggering conditions, no workflow summary.
- [ ] Skill type chosen and the body matches that type's rigor bar.
- [ ] Concrete keywords throughout the body for retrieval (errors, symptoms, tool names, synonyms).
- [ ] One excellent worked example, not multiple mediocre ports.
- [ ] No `@path/to/other-skill.md` cross-references; reference by name only.
- [ ] If a sibling file is referenced, the relative path resolves on disk (CI checks this).
- [ ] If it's a discipline skill, you ran a baseline scenario with `spawn_subagent` before writing — see `testing-with-subagents.md`.
- [ ] Builtin tests pass: `dart test cli/test/skills/bundled_skills_test.dart`.
