# Bundled Skills

This directory contains built-in skills bundled with Glue.

Discovery precedence (highest to lowest):

1. `.glue/skills` in the active workspace (`project`)
2. `skill_paths` entries from config (`custom`)
3. `~/.glue/skills` (`global`)
4. Bundled skills in this directory (`builtin`)

Each skill must live in `<name>/SKILL.md` and the frontmatter `name` must
match the directory name.

## Bundled skills

| Skill                              | Purpose                                                                           |
| ---------------------------------- | --------------------------------------------------------------------------------- |
| `agentic-research`                 | Parallel research across multiple systems with structured synthesis               |
| `architecture-reverse-engineering` | Inferring layers, boundaries, and architectural style from an existing codebase   |
| `browser-automation`               | Driving a real browser via Playwright/CDP for testing or scraping                 |
| `code-review`                      | Diff-based, severity-classified code review                                       |
| `skill-creator`                    | Authoring new glue skills — frontmatter rules, type classification, anti-patterns |

# todo: revamp these
