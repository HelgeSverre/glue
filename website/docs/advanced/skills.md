# Skills

Skills are reusable prompt templates that guide the agent through specific workflows. They let you codify repeatable processes — code reviews, migrations, scaffolding — so the agent follows a consistent approach every time.

## Skill Types

Glue supports two types of skills:

- **Global skills** — stored in `~/.glue/skills/`, available in every session
- **Project skills** — stored in `.glue/skills/`, scoped to the current project

Project skills take precedence over global skills with the same name.

## Skill Structure

Each skill is a directory containing a `SKILL.md` file with frontmatter metadata and body instructions:

```
.glue/skills/
  my-skill/
    SKILL.md
```

## SKILL.md Format

The `SKILL.md` file uses YAML frontmatter for metadata, followed by markdown instructions:

```markdown
---
name: my-skill
description: Describe what this skill does
---

Instructions for the agent when this skill is activated...
```

The frontmatter defines the skill's name and description (plus optional `license`, `compatibility`, and arbitrary `metadata`). The agent uses the `description` to decide when the skill is relevant. The body contains the actual prompt instructions the agent follows when the skill is activated.

## Using Skills

- Use the `/skills` command to browse available skills in the current session
- The agent can activate skills via the `skill` tool when a task matches a skill's description

::: tip
Start with project skills for repo-specific workflows. Move them to `~/.glue/skills/` once they prove useful across multiple projects.
:::

## See also

- [SkillRegistry](/api/skills/skill-registry)
- [SkillParser](/api/skills/skill-parser)
- [SkillTool](/api/skills/skill-tool)
