# Design: Agent Skills Support (agentskills.io)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

## Overview

Add support for the [agentskills.io](https://agentskills.io/specification) standard to Glue CLI.
Skills are directories containing a `SKILL.md` file with YAML frontmatter (name, description)
and markdown instructions. The agent discovers skills at startup, injects metadata into the
system prompt, and activates skills on demand via a `skill` tool.

## Skill Discovery (mirrors Claude Code)

Scan these directories for subdirectories containing `SKILL.md`:

1. **Project-local:** `.glue/skills/` in the current working directory
2. **Global user:** `~/.glue/skills/`
3. **Extra paths:** from `skills.paths` in `~/.glue/config.yaml` or `GLUE_SKILLS_PATHS` env var

Each skill directory must contain a `SKILL.md` (preferred) or `skill.md` (fallback).
Only YAML frontmatter is parsed at discovery time — the body is loaded on activation.

Name collisions: first match wins (project-local beats global beats extra paths).
Invalid/unparseable skills are skipped with a warning logged.

## SKILL.md Parsing

Split on `---` delimiters. Parse YAML frontmatter for:

| Field           | Required | Validation                                                             |
| --------------- | -------- | ---------------------------------------------------------------------- |
| `name`          | Yes      | 1–64 chars, lowercase alphanum + hyphens, no `--`, must match dir name |
| `description`   | Yes      | 1–1024 chars                                                           |
| `license`       | No       | Free-form string                                                       |
| `compatibility` | No       | 1–500 chars                                                            |
| `allowed-tools` | No       | Space-delimited tool patterns (stored but not enforced in v1)          |
| `metadata`      | No       | Arbitrary `Map<String, String>`                                        |

## System Prompt Injection

`Prompts.build()` accepts a `List<SkillMeta>` and appends an `<available_skills>` XML block:

```xml
<available_skills>
<skill>
<name>code-review</name>
<description>Perform a formal code review...</description>
<location>~/.glue/skills/code-review/SKILL.md</location>
</skill>
</available_skills>
```

Plus a short instruction telling the LLM to use the `skill` tool to activate skills.

## Skill Tool

A single `skill` tool registered alongside existing tools:

```
name: skill
description: Load a skill's instructions into context. Call with no arguments to list available skills.
parameters:
  - name: name (optional) — skill name to activate
```

- **No args:** returns formatted list of all discovered skills (name + description + source)
- **With name:** reads the full SKILL.md body and returns it as the tool result

The tool result persists in conversation history — no system prompt mutation needed.
Auto-approved (read-only, local files only).

## `/skills` Slash Command — Two-Pane Browser

A new `/skills` command opens a `SplitPanelModal`:

```
┌─ SKILLS ────────────────────────────────────────────────────────────┐
│                                                                     │
│  SKILL                    │  DETAILS                                │
│  ─────────────────────    │  ──────────────────────────────────     │
│  ● code-review    global  │  code-review                           │
│    frontend-design global │                                         │
│    tdd             global │  Description                            │
│    api-patterns  project  │  Perform a formal code review...        │
│    db-migrations project  │                                         │
│                           │  Source     ~/.glue/skills/code-review/ │
│                           │  License    Apache-2.0                  │
│                           │                                         │
│                           │  ↑↓ navigate  Enter activate  Esc close│
└─────────────────────────────────────────────────────────────────────┘
```

**Left pane:** scrollable, selectable list. Each item shows skill name + source tag
(`global`, `project`, or path for extra dirs). Selected item highlighted with reverse video.

**Right pane:** detail view for the selected skill. Shows name (bold), description
(word-wrapped), source path, license, compatibility, metadata k/v pairs. Updates
as user navigates left pane.

**Controls:** ↑↓ navigate, Enter activates (injects skill body as system message
or prints confirmation), Esc closes.

### UI Implementation

New `SplitPanelModal` class (`lib/src/ui/split_panel_modal.dart`) — does NOT extend
`PanelModal` but reuses the same rendering helpers (`renderBorder`, `applyBarrier`,
`ansiTruncate`, `visibleLength`).

Key differences from `PanelModal`:

- Two independent content regions within the border
- Left pane has its own scroll state; right pane is top-anchored
- Selection highlight only on left pane
- Right pane content is derived via a callback: `List<String> Function(int selectedIndex, int rightWidth)`
- Vertical divider (dim `│`) between panes

## Data Model

```dart
// lib/src/skills/skill_parser.dart

class SkillMeta {
  final String name;
  final String description;
  final String? license;
  final String? compatibility;
  final String? allowedTools;
  final Map<String, String> metadata;
  final String skillDir;     // directory containing SKILL.md
  final String skillMdPath;  // full path to SKILL.md
  final SkillSource source;  // global, project, or custom
}

enum SkillSource { project, global, custom }
```

## Registry

```dart
// lib/src/skills/skill_registry.dart

class SkillRegistry {
  final List<SkillMeta> _skills;

  factory SkillRegistry.discover({
    required String cwd,
    List<String> extraPaths = const [],
  });

  List<SkillMeta> list();
  SkillMeta? findByName(String name);
  String loadBody(String name);  // reads SKILL.md body on demand
}
```

## New Files

| File                                   | Purpose                                              |
| -------------------------------------- | ---------------------------------------------------- |
| `lib/src/skills/skill_parser.dart`     | `SkillMeta`, frontmatter parsing + validation        |
| `lib/src/skills/skill_registry.dart`   | Discovery from configured dirs, lookup, body loading |
| `lib/src/skills/skill_tool.dart`       | `SkillTool extends Tool`                             |
| `lib/src/ui/split_panel_modal.dart`    | Two-pane panel modal for `/skills` browser           |
| `test/skills/skill_parser_test.dart`   | Parsing + validation tests                           |
| `test/skills/skill_registry_test.dart` | Discovery + lookup tests                             |
| `test/skills/skill_tool_test.dart`     | Tool behavior tests                                  |
| `test/ui/split_panel_modal_test.dart`  | Panel rendering + navigation tests                   |

## Modified Files

| File                              | Change                                                     |
| --------------------------------- | ---------------------------------------------------------- |
| `lib/src/config/glue_config.dart` | Add `List<String> skillPaths` field                        |
| `lib/src/agent/prompts.dart`      | Accept skills list, append `<available_skills>` XML        |
| `lib/src/app.dart`                | Instantiate registry, register tool, add `/skills` command |
| `lib/src/storage/glue_home.dart`  | Add `skillsDir` getter                                     |
| `lib/glue.dart`                   | Export new public types                                    |

## Config

```yaml
# ~/.glue/config.yaml
skills:
  paths:
    - ~/shared-skills
    - /opt/team-skills
```

Or via env: `GLUE_SKILLS_PATHS=~/shared-skills;/opt/team-skills`

Default scan paths (always active, no config needed):

- `.glue/skills/` (project-local, relative to cwd)
- `~/.glue/skills/` (global)

## Out of Scope (v1)

- `allowed-tools` enforcement (stored but ignored)
- Hot-reload / file watching for skill changes
- Skill composition / dependencies
- Plugin system (skills from npm/pub packages)
- Parent directory walk (monorepo nested skills)
- Token budget enforcement for skill descriptions
- `--add-dir` flag support
