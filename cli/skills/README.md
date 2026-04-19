# Bundled Skills

This directory contains built-in skills bundled with Glue.

Discovery precedence (highest to lowest):
1. `.glue/skills` in the active workspace (`project`)
2. `skill_paths` entries from config (`custom`)
3. `~/.glue/skills` (`global`)
4. Bundled skills in this directory (`builtin`)

Each skill must live in `<name>/SKILL.md` and the frontmatter `name` must
match the directory name.


# todo: revamp these