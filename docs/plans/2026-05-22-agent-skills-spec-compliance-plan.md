# Agent Skills Spec Compliance Review And Improvement Plan

> Scope: Review Glue's current Agent Skills support against the Agent Skills
> specification and client implementation guidance at <https://agentskills.io/>.
> This is a planning artifact only; it does not implement the changes.

## Current Support

Glue already implements the essential three-part Agent Skills flow:

- Discovery through `SkillRegistry.discover()` in
  `packages/glue_harness/lib/src/skills/skill_registry.dart`.
- Metadata disclosure through `Prompts.build()` in
  `packages/glue_harness/lib/src/agent/prompts.dart`.
- Lazy activation through the `skill` tool and `/skills` UI in
  `packages/glue_harness/lib/src/skills/skill_tool.dart` and
  `cli/lib/src/commands/slash/skills.dart`.

The implemented format covers the required `name` and `description` fields and
the optional `license`, `compatibility`, and `metadata` fields. It also accepts
`allowed-tools` as a recognized frontmatter key, but the parsed value is not
stored or surfaced today.

## Spec Baseline

The upstream Agent Skills docs define the portable unit as a directory with an
exactly named `SKILL.md` file, YAML frontmatter, markdown instructions, and
optional bundled resources.

The client guidance emphasizes progressive disclosure:

1. Catalog: load `name` and `description` at session start.
2. Instructions: load the full `SKILL.md` body when activated.
3. Resources: load referenced `scripts/`, `references/`, and `assets/` files
   only when needed.

Important implementation guidance from the upstream docs:

- Scan project and user scopes, including client-native paths and the
  cross-client `.agents/skills/` convention.
- Look for subdirectories containing exactly `SKILL.md`.
- Use deterministic collision precedence, with project-level skills overriding
  user-level skills, and log warnings for shadowed skills.
- Consider trust gating for project-level skills.
- Validate frontmatter, but prefer diagnostics and lenient loading for cosmetic
  issues where possible.
- Include enough catalog information for activation and relative resource path
  resolution.
- Dedicated activation tools may strip frontmatter, but should wrap output
  clearly and can enumerate bundled resources without eagerly reading them.
- Preserve activated skill content through context management and avoid duplicate
  activations in a session.

## Gaps And Inconsistencies

### 1. Standard Interoperability Paths Are Missing

Glue currently scans:

- `.glue/skills`
- configured extra paths
- `~/.glue/skills`
- bundled paths

It does not scan the cross-client `.agents/skills/` convention at either project
or user scope. That means a valid skill installed for another compliant client is
invisible to Glue unless the user manually mirrors or configures the path.

It also does not scan `.claude/skills/`, which the upstream client guidance calls
out as a pragmatic compatibility path for existing skills.

### 2. Discovery Precedence Is Underdocumented And Internally Inconsistent

`skill_registry.dart` says precedence is `project > custom extra paths
(including bundled) > global`, but the actual order is:

1. project `.glue/skills`
2. configured extra paths
3. global `~/.glue/skills`
4. bundled paths

The tests encode global-over-bundled behavior, so the code and tests agree, but
the comment and earlier design docs do not. The plan should make precedence a
first-class policy and update docs/tests/comments to match.

### 3. Invalid Skills And Collisions Are Silent

Invalid `SKILL.md` files are skipped silently. Collisions are also silently
resolved by first-seen-wins. The upstream guidance asks clients to record
diagnostics and warn on collisions so users can understand why a skill is
missing or shadowed.

This is especially important once `.agents/skills`, `.claude/skills`, extra
paths, and bundled paths can overlap.

### 4. `allowed-tools` Is Accepted But Lost

The parser recognizes `allowed-tools` as a valid frontmatter field, and existing
docs say it is "stored but not enforced". In the actual `SkillMeta`, there is no
`allowedTools` field, so the value is discarded.

This is the clearest implementation inconsistency. Even if enforcement stays
out of scope, Glue should parse, store, display, and log `allowed-tools` so the
metadata is not lost.

### 5. Resource Handling Is Only Implicit

The prompt tells the model to load referenced files as needed, and the activation
tool returns `Source: <skillDir>`, but Glue does not enumerate bundled resources
or provide a skill-scoped resource resolver.

The spec expects resources to live beside the skill in directories such as
`scripts/`, `references/`, and `assets/`, and the client guidance recommends
listing them on activation without eagerly loading them. Today the model must
infer or manually inspect the directory.

### 6. Frontmatter Parsing Is Strict In Places That Hurt Portability

Glue enforces strict spec constraints as hard failures:

- name must match directory
- name length and character rules
- description length
- unknown top-level fields

The spec itself defines strict constraints, but the client implementation guide
recommends lenient loading with diagnostics for cosmetic issues, especially for
skills authored by other clients. Missing or empty `description` and unparseable
YAML should remain fatal because they break catalog disclosure. Other issues can
be warnings in compatibility mode.

The parser also splits frontmatter with `content.split('---')`. It should instead
find delimiter lines at the start of the file and the first closing delimiter
line, matching the guidance and avoiding accidental delimiter matches inside
content.

### 7. Activation Output Is Useful But Not Structured Enough

The `skill` tool returns a readable block:

```text
# Skill: code-review
Source: /path/to/skill

...body...
```

This works, but the upstream guidance recommends structured wrapping so the
harness can identify activated skill content later, preserve it during context
compaction, and make relative path semantics explicit.

Glue should move toward an activation envelope such as:

```xml
<skill_instructions name="code-review">
  <skill_directory>/abs/path/code-review</skill_directory>
  <relative_paths_base>/abs/path/code-review</relative_paths_base>
  <resources truncated="false">...</resources>
  <body>...</body>
</skill_instructions>
```

The exact shape should match Glue's existing provider/message constraints, but
it needs to be machine-identifiable.

### 8. No Session-Level Deduplication Or Protected Skill Context

Manual activation injects a synthetic tool call and tool result. Model-driven
activation also returns a normal tool result. There is no visible session state
for "this skill is already active" and no special marker in `Message` for
protected skill content.

If Glue later adds or expands context pruning, activated skill instructions can
be summarized away like ordinary tool output. The upstream guide recommends
deduplicating activations and protecting skill content from compaction.

### 9. Trust And Permissions Are Not Explicit

Project-local skills can influence the model through the prompt catalog and
activation path. The upstream guidance recommends considering trust checks for
project-level skills because a repository can inject behavior into the agent.

Glue also has a permission model for tools and shell execution, but there is no
skill-specific trust or resource allowlist policy. Once resource loading is made
more ergonomic, skill directory access should be explicit and bounded.

### 10. Discovery Surface Uses One Broad `custom` Source

`SkillSource` only has `project`, `global`, and `custom`, so extra paths and
bundled skills are indistinguishable in the prompt, UI, and logs. This makes
collisions and trust decisions harder to explain.

The source model should separate at least:

- `projectNative`
- `projectAgents`
- `projectClaude`
- `userNative`
- `userAgents`
- `userClaude`
- `configured`
- `bundled`

The public UI can still show short labels, but the registry should keep precise
source information.

## Target Behavior

Glue should remain friendly and conservative:

- Keep `.glue/skills` as the native path.
- Add `.agents/skills` for standards-based interoperability.
- Optionally add `.claude/skills` compatibility, behind a default-on config if
  we want pragmatic adoption without surprising users.
- Keep the `skill` tool and `/skills` UI as the main activation surfaces.
- Preserve lazy resource loading; do not eagerly read bundled files.
- Treat diagnostics as first-class data rather than stderr-only warnings.
- Avoid breaking existing user skills unless they are fundamentally unusable.

## Proposed Data Model

Add these types in `packages/glue_harness/lib/src/skills/`:

```dart
enum SkillSourceKind {
  projectNative,
  projectAgents,
  projectClaude,
  userNative,
  userAgents,
  userClaude,
  configured,
  bundled,
}

enum SkillDiagnosticSeverity { warning, error }

class SkillDiagnostic {
  final SkillDiagnosticSeverity severity;
  final String code;
  final String message;
  final String? path;
  final String? skillName;
}

class SkillResource {
  final String relativePath;
  final String absolutePath;
  final SkillResourceKind kind;
  final int? sizeBytes;
}

enum SkillResourceKind { script, reference, asset, other }
```

Extend `SkillMeta`:

```dart
class SkillMeta {
  final String name;
  final String description;
  final String? license;
  final String? compatibility;
  final String? allowedTools;
  final Map<String, String> metadata;
  final String skillDir;
  final String skillMdPath;
  final SkillSourceKind sourceKind;
  final String sourceLabel;
  final List<SkillDiagnostic> diagnostics;
}
```

Add a `SkillRegistrySnapshot`:

```dart
class SkillRegistrySnapshot {
  final List<SkillMeta> skills;
  final List<SkillDiagnostic> diagnostics;
  final List<SkillCollision> collisions;
}
```

This lets the runtime show valid skills while still exposing why other skills
were skipped or shadowed.

## Proposed Configuration

Keep existing config:

```yaml
skills:
  paths:
    - ~/shared-skills
```

Add optional compatibility controls:

```yaml
skills:
  scan_agents_paths: true
  scan_claude_paths: true
  diagnostics: true
  strict_validation: false
  trust_project_skills: prompt
  expose_resources_on_activation: true
  max_resource_list_entries: 200
  enforce_allowed_tools: false
```

Suggested defaults:

- `scan_agents_paths: true`
- `scan_claude_paths: true`
- `diagnostics: true`
- `strict_validation: false`
- `trust_project_skills: prompt` if Glue already has a trust concept available;
  otherwise `true` for backward compatibility with a follow-up trust task.
- `expose_resources_on_activation: true`
- `max_resource_list_entries: 200`
- `enforce_allowed_tools: false`

Environment overrides can follow the existing config pattern:

- `GLUE_SKILLS_PATHS`
- `GLUE_SKILLS_SCAN_AGENTS_PATHS`
- `GLUE_SKILLS_SCAN_CLAUDE_PATHS`
- `GLUE_SKILLS_STRICT_VALIDATION`
- `GLUE_SKILLS_ENFORCE_ALLOWED_TOOLS`

## Implementation Plan

### Phase 1: Make Current Behavior Honest And Observable

- Add `allowedTools` to `SkillMeta`.
- Parse and test `allowed-tools` as a string.
- Show `allowed-tools` in `/skills` details and activation metadata when present.
- Fix the registry precedence comment and docs to match current behavior, or
  change the code if we decide bundled should outrank global.
- Replace silent invalid-skill skipping with stored diagnostics.
- Add collision diagnostics for first-seen-wins shadowing.
- Add `/skills doctor` or an equivalent section in `/skills` for skipped and
  shadowed skills.
- Update `cli/skills/README.md`, `docs/architecture/glossary.md`, and
  `docs/architecture/agent-loop-and-rendering.md`.

Tests:

- Parser preserves `allowed-tools`.
- Invalid skill produces a diagnostic while valid skills still load.
- Name collision produces a shadowing diagnostic.
- `/skills` or `skill()` can expose diagnostics without polluting the default
  catalog.

### Phase 2: Add Standards-Based Discovery Paths

- Extend discovery to scan:
  - project `.glue/skills`
  - project `.agents/skills`
  - project `.claude/skills` if enabled
  - configured extra paths
  - user `~/.glue/skills`
  - user `~/.agents/skills`
  - user `~/.claude/skills` if enabled
  - bundled paths
- Keep project-level paths ahead of user-level paths.
- Decide and document same-scope precedence between native, `.agents`, and
  `.claude` paths. Recommended:
  1. native `.glue/skills`
  2. standard `.agents/skills`
  3. compatibility `.claude/skills`
- Add source kinds and short display labels.
- Update help text from `skillDiscoveryHelpText()`.

Tests:

- Project `.agents/skills` skills are discovered.
- User `~/.agents/skills` skills are discovered.
- Project skills override user skills across path conventions.
- Native path wins over `.agents` within the same scope.
- `.claude` path scanning can be disabled.

### Phase 3: Harden Parsing Without Losing Compatibility

- Replace `content.split('---')` with delimiter-line frontmatter extraction:
  - opening delimiter must be the first line
  - closing delimiter must be a delimiter line after the opening line
  - body is everything after the closing delimiter, trimmed left
- Add a parser mode:
  - strict mode: current spec constraints are fatal
  - compatibility mode: cosmetic issues are warnings where safe
- Keep these fatal in both modes:
  - missing frontmatter
  - unparseable YAML after fallback attempts
  - missing or empty `description`
  - missing or empty `name`
- Consider a small YAML fallback for common unquoted-colon descriptions.
- Decide whether unknown top-level fields should be warnings or should be copied
  into `metadata` under a `raw.` prefix in compatibility mode.

Tests:

- Body containing `---` after the closing delimiter is preserved.
- Delimiters are recognized only as delimiter lines.
- Directory-name mismatch loads with warning in compatibility mode.
- Unknown fields warn instead of skipping in compatibility mode.
- Strict mode preserves current failures.

### Phase 4: Surface Resources Safely

- Add a skill resource scanner that enumerates files under the skill root without
  reading file contents.
- Classify common directories:
  - `scripts/` -> `script`
  - `references/` -> `reference`
  - `assets/` -> `asset`
  - everything else -> `other`
- Canonicalize paths and ensure every resource resolves inside `skillDir`.
- Skip hidden directories, `.git`, `node_modules`, build outputs, and large
  generated directories.
- Cap the resource list and include a truncation marker.
- Add resources to activation output when enabled.
- Make relative-path instructions explicit in activation output.

Tests:

- Activation lists resources but does not read their contents.
- Resource paths are relative to the skill root.
- Symlink or `..` escapes are rejected or omitted.
- Resource listing caps are honored.

### Phase 5: Structure Activation And Track Active Skills

- Wrap activation output in a machine-identifiable envelope.
- Add activation metadata:
  - skill name
  - source kind
  - skill directory
  - `SKILL.md` path
  - compatibility
  - allowed tools
  - diagnostics summary
  - resource list
- Track active skill names in session state.
- If a skill is already active, return a short "already active" result unless
  the caller requests refresh.
- Mark skill tool results in a way future context management can preserve.
- Ensure manual `/skills <name>` and model-driven `skill(name: ...)` use the same
  activation path.

Tests:

- Activation output has stable tags.
- Duplicate activation does not inject a second full copy by default.
- Manual and model-driven activation produce the same content shape.
- Session logs include enough metadata to audit which skill version/path loaded.

### Phase 6: Trust And Permissions

- Define a trust policy for project-level skills:
  - `always`
  - `prompt`
  - `never`
- If project trust is not decided, hide project skills from the catalog or show
  them as blocked diagnostics until trusted.
- Make skill resource read access explicit:
  - allow reads under trusted skill directories
  - deny or prompt for paths outside the skill root
- Keep `allowed-tools` enforcement disabled by default because the field is
  experimental.
- If enforcement is enabled, interpret it as additive pre-approval hints only
  after mapping patterns to Glue's actual tool names and permission model.

Tests:

- Untrusted project skills do not appear in the model catalog.
- Trusted project skills activate normally.
- Resource reads cannot escape the skill directory.
- `allowed-tools` enforcement gate defaults off.

### Phase 7: Reference Validation And Interop Fixtures

- Add fixture skills that cover:
  - minimal valid skill
  - full optional frontmatter
  - `.agents/skills` discovery
  - `.claude/skills` compatibility
  - resources in `scripts/`, `references/`, and `assets/`
  - invalid-but-recoverable metadata
  - fatal missing description
- If practical, run the upstream `skills-ref validate` tool in CI for bundled
  fixture skills or document the manual validation command.
- Add a small compatibility matrix to docs showing:
  - spec field support
  - discovery paths
  - resource behavior
  - `allowed-tools` behavior
  - trust behavior

## Recommended Task Order

1. Fix the data model inconsistency by storing `allowed-tools`.
2. Add diagnostics and collision records without changing discovery behavior.
3. Add `.agents/skills` discovery and source kinds.
4. Replace delimiter parsing with line-based frontmatter extraction.
5. Add resource enumeration to activation output.
6. Add structured activation and deduplication.
7. Add trust and permission policy.
8. Add reference validation fixtures and docs.

This order reduces risk: early tasks make current behavior visible, then expand
interoperability, then improve safety around the larger surface area.

## Acceptance Criteria

- A valid skill in project `.agents/skills/<name>/SKILL.md` appears in the prompt
  catalog and `/skills` UI.
- A valid skill in user `~/.agents/skills/<name>/SKILL.md` appears when no
  project skill shadows it.
- A project skill shadows a user skill deterministically and records a collision
  diagnostic.
- `allowed-tools` is preserved in `SkillMeta`, shown in details, and recorded in
  activation metadata.
- Invalid skills produce visible diagnostics rather than disappearing silently.
- Activation output includes the skill directory and a bounded resource list.
- Skill resource paths are canonicalized and cannot escape the skill root.
- Re-activating an already active skill avoids duplicate full instruction blocks.
- Existing `.glue/skills` users keep working without config changes.
- Tests cover native, `.agents`, `.claude`, configured, global, and bundled
  discovery precedence.

## Open Decisions

- Should `.claude/skills` scanning be default-on for compatibility, or opt-in to
  avoid surprising users?
- Should compatibility-mode unknown frontmatter fields be warnings only, or
  copied into `metadata`?
- Should `skill.md` lowercase fallback remain supported even though the spec
  says the file name is exactly `SKILL.md`?
- What is the right UI shape for diagnostics: `/skills doctor`, a docked panel
  tab, or both?
- Does Glue already have a project trust primitive we should reuse, or should
  skills define the first version of that concept?
- How should `allowed-tools` patterns map onto Glue's current tool names and
  permission gate if enforcement is enabled later?

## Files To Touch

- `packages/glue_harness/lib/src/skills/skill_parser.dart`
- `packages/glue_harness/lib/src/skills/skill_registry.dart`
- `packages/glue_harness/lib/src/skills/skill_runtime.dart`
- `packages/glue_harness/lib/src/skills/skill_tool.dart`
- `packages/glue_harness/lib/src/skills/skill_activation.dart`
- `packages/glue_harness/lib/src/agent/prompts.dart`
- `packages/glue_harness/lib/src/config/glue_config.dart`
- `packages/glue_harness/lib/src/config/config_template.dart`
- `cli/lib/src/commands/slash/skills.dart`
- `cli/lib/src/ui/skills_docked_panel.dart`
- `cli/skills/README.md`
- `docs/architecture/glossary.md`
- `docs/architecture/agent-loop-and-rendering.md`
- `cli/test/skills/skill_parser_test.dart`
- `cli/test/skills/skill_registry_test.dart`
- `cli/test/skills/skill_runtime_test.dart`
- `cli/test/skills/skill_tool_test.dart`
- `cli/test/agent/prompts_test.dart`
- `cli/test/ui/skills_docked_panel_test.dart`
