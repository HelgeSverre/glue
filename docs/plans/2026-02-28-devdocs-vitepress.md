# VitePress Developer Docs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a VitePress-based API documentation site at `devdocs/` that generates Markdown from Dart source using `dart_doc_markdown_generator`, extracts category metadata via a custom Dart script using `package:analyzer`, and styles it to match the existing website's brutalist yellow/black theme.

**Architecture:** Two-phase build pipeline: (1) `dart_doc_markdown_generator` walks `cli/lib/src/` and emits one `.md` per Dart file into `devdocs/api/`, (2) a custom Dart script `cli/tool/generate_devdocs_config.dart` uses `package:analyzer` to parse `{@category}` tags and class structure, then writes `devdocs/.vitepress/sidebar.json` which VitePress config imports to build the sidebar/navbar. VitePress custom theme overrides CSS variables to match the website's brutalist style (yellow `#FACC15`, black `#0A0A0B`, JetBrains Mono + Inter).

**Tech Stack:** VitePress (latest), Node.js, `dart_doc_markdown_generator` (pub global), `package:analyzer` (Dart), custom CSS theme override.

---

## Architecture Diagram

```
cli/lib/src/**/*.dart
        │
        ├──► dart_doc_markdown_generator ──► devdocs/api/**/*.md
        │
        └──► cli/tool/generate_devdocs_config.dart (package:analyzer)
                  │
                  ├──► devdocs/.vitepress/sidebar.json  (sidebar structure)
                  └──► devdocs/.vitepress/categories.json (category → classes map)
                            │
                            ▼
                  devdocs/.vitepress/config.ts (imports JSON, builds nav/sidebar)
                            │
                            ▼
                  vitepress build ──► devdocs/.vitepress/dist/ (static site)
```

## Directory Structure

```
devdocs/
├── .vitepress/
│   ├── config.ts              # VitePress config — imports sidebar.json
│   ├── sidebar.json           # GENERATED — do not edit
│   ├── categories.json        # GENERATED — do not edit
│   └── theme/
│       ├── index.ts           # Extends default theme
│       └── custom.css         # Brutalist overrides
├── api/                       # GENERATED — markdown from dart source
│   ├── agent/
│   │   ├── agent-core.md
│   │   ├── agent-manager.md
│   │   ├── agent-runner.md
│   │   └── ...
│   ├── llm/
│   ├── terminal/
│   ├── rendering/
│   ├── shell/
│   ├── config/
│   ├── observability/
│   ├── skills/
│   ├── storage/
│   ├── ui/
│   ├── input/
│   ├── tools/
│   ├── web/
│   └── commands/
├── guide/                     # Hand-written docs (future)
│   └── index.md
├── index.md                   # Landing page
├── package.json
└── .gitignore
```

---

### Task 1: Scaffold VitePress Project

**Files:**
- Create: `devdocs/package.json`
- Create: `devdocs/.gitignore`
- Create: `devdocs/index.md`

**Step 1: Create `devdocs/package.json`**

```json
{
  "name": "glue-devdocs",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vitepress dev",
    "build": "vitepress build",
    "preview": "vitepress preview"
  },
  "devDependencies": {
    "vitepress": "^1.6.3"
  }
}
```

**Step 2: Create `devdocs/.gitignore`**

```
node_modules/
.vitepress/dist/
.vitepress/cache/
api/
.vitepress/sidebar.json
.vitepress/categories.json
```

Note: `api/` is generated output and should not be committed. The sidebar/categories JSON files are also generated.

**Step 3: Create `devdocs/index.md`**

```markdown
---
layout: home
hero:
  name: Glue
  text: API Reference
  tagline: Developer documentation for the Glue coding agent internals.
  actions:
    - theme: brand
      text: API Reference
      link: /api/
    - theme: alt
      text: GitHub
      link: https://github.com/helgesverre/glue
---
```

**Step 4: Install dependencies**

Run: `cd devdocs && npm install`
Expected: `node_modules/` created, vitepress installed.

**Step 5: Smoke test**

Run: `cd devdocs && npx vitepress dev`
Expected: Dev server starts, landing page visible at http://localhost:5173

---

### Task 2: VitePress Config + Custom Theme

**Files:**
- Create: `devdocs/.vitepress/config.ts`
- Create: `devdocs/.vitepress/theme/index.ts`
- Create: `devdocs/.vitepress/theme/custom.css`

**Step 1: Create VitePress config**

`devdocs/.vitepress/config.ts`:

```ts
import { defineConfig } from 'vitepress'
import { existsSync, readFileSync } from 'fs'

// Import generated sidebar (falls back to empty if not yet generated)
const sidebarPath = new URL('./sidebar.json', import.meta.url)
const sidebar = existsSync(sidebarPath)
  ? JSON.parse(readFileSync(sidebarPath, 'utf-8'))
  : []

export default defineConfig({
  title: 'Glue',
  description: 'API Reference for the Glue coding agent',
  
  head: [
    ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' }],
    ['link', { href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600;700;800&display=swap', rel: 'stylesheet' }],
  ],

  themeConfig: {
    logo: false,
    siteTitle: 'GLUE',
    
    nav: [
      { text: 'API Reference', link: '/api/' },
      { text: 'Website', link: 'https://glue.dev' },
      { text: 'GitHub', link: 'https://github.com/helgesverre/glue' },
    ],

    sidebar: {
      '/api/': sidebar,
    },

    search: {
      provider: 'local',
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/helgesverre/glue' },
    ],
  },
})
```

**Step 2: Create custom theme entry**

`devdocs/.vitepress/theme/index.ts`:

```ts
import DefaultTheme from 'vitepress/theme'
import './custom.css'

export default DefaultTheme
```

**Step 3: Create brutalist CSS overrides**

`devdocs/.vitepress/theme/custom.css` — matches the website's yellow/black brutalist aesthetic:

```css
/* ─── Glue Brutalist Theme ─── */

:root {
  /* Brand colors from website/styles.css */
  --glue-yellow: #FACC15;
  --glue-gold: #EAB308;
  --glue-black: #0A0A0B;
  --glue-dark: #1a1a1a;
  --glue-dark2: #2a2a2a;
  --glue-gray: #555;
  --glue-white: #fafafa;

  /* VitePress color overrides */
  --vp-c-brand-1: var(--glue-yellow);
  --vp-c-brand-2: var(--glue-gold);
  --vp-c-brand-3: var(--glue-yellow);
  --vp-c-brand-soft: rgba(250, 204, 21, 0.14);

  /* Typography */
  --vp-font-family-base: 'Inter', sans-serif;
  --vp-font-family-mono: 'JetBrains Mono', monospace;

  /* Nav */
  --vp-nav-bg-color: var(--glue-black);
  --vp-c-text-1: var(--glue-black);
}

.dark {
  --vp-c-bg: var(--glue-black);
  --vp-c-bg-alt: var(--glue-dark);
  --vp-c-bg-soft: var(--glue-dark2);
  --vp-c-text-1: var(--glue-white);
  --vp-c-text-2: #ccc;
  --vp-c-text-3: #888;
  --vp-sidebar-bg-color: var(--glue-dark);
  --vp-c-divider: var(--glue-dark2);
}

/* Force dark mode by default (matches brutalist website) */
html {
  color-scheme: dark;
}

/* Tape-style border under nav */
.VPNav::after {
  content: '';
  display: block;
  height: 4px;
  background: var(--glue-yellow);
}

/* Nav site title styling */
.VPNavBarTitle .title {
  font-family: 'JetBrains Mono', monospace;
  font-weight: 800;
  letter-spacing: -1px;
  text-transform: uppercase;
  color: var(--glue-yellow) !important;
}

/* Sidebar category headers */
.VPSidebarItem.level-0 > .item > .text {
  font-family: 'JetBrains Mono', monospace;
  font-weight: 700;
  text-transform: uppercase;
  font-size: 12px;
  letter-spacing: 0.05em;
}

/* Code blocks — dark background */
.vp-doc div[class*='language-'] {
  border: 2px solid var(--glue-dark2);
}

/* Hero overrides for landing page */
.VPHero .name {
  font-family: 'JetBrains Mono', monospace !important;
  font-weight: 900 !important;
  letter-spacing: -0.04em;
  text-transform: uppercase;
}

.VPHero .text {
  font-family: 'JetBrains Mono', monospace !important;
  font-weight: 800;
  text-transform: uppercase;
}

/* Brand button styling */
.VPButton.brand {
  background-color: var(--glue-yellow) !important;
  color: var(--glue-black) !important;
  border-color: var(--glue-yellow) !important;
  font-family: 'JetBrains Mono', monospace;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.03em;
}

.VPButton.brand:hover {
  background-color: var(--glue-black) !important;
  color: var(--glue-yellow) !important;
}
```

**Step 4: Verify theme**

Run: `cd devdocs && npx vitepress dev`
Expected: Landing page visible with yellow/black brutalist styling, JetBrains Mono headings.

---

### Task 3: Generate API Markdown with `dart_doc_markdown_generator`

**Files:**
- Generated: `devdocs/api/**/*.md`

**Step 1: Install the generator**

Run: `dart pub global activate dart_doc_markdown_generator`
Expected: Tool activated successfully.

**Step 2: Create a `.dartdocmarkdownrc` in `cli/`**

Create: `cli/.dartdocmarkdownrc`:

```
test/
bin/
.dart_tool/
```

**Step 3: Generate markdown**

Run: `dart pub global run dart_doc_markdown_generator cli devdocs/api`
Expected: Markdown files generated in `devdocs/api/` mirroring the `cli/lib/src/` directory structure.

**Step 4: Verify output**

Run: `ls devdocs/api/`
Expected: Directories like `agent/`, `llm/`, `terminal/`, etc. with `.md` files inside.

**Step 5: Create `devdocs/api/index.md`**

```markdown
# API Reference

Browse the Glue CLI internals by module:

| Module | Description |
|--------|-------------|
| [Agent](./agent/) | Core agent loop, runner, and manager |
| [LLM](./llm/) | Provider clients (Anthropic, OpenAI, Ollama) |
| [Terminal](./terminal/) | Raw terminal I/O and layout |
| [Rendering](./rendering/) | Block renderer, Markdown, ANSI utils |
| [Shell](./shell/) | Command execution, Docker sandbox |
| [Config](./config/) | Configuration and model registry |
| [Observability](./observability/) | Tracing, spans, sinks |
| [Tools](./tools/) | Subagent tools |
| [UI](./ui/) | Modals, panels, autocomplete |
| [Skills](./skills/) | Skill parser and registry |
| [Storage](./storage/) | Session and config persistence |
| [Web](./web/) | Web fetch, search, browser |
```

**Step 6: Smoke test**

Run: `cd devdocs && npx vitepress dev`
Expected: API markdown pages render in the site. Content may be rough (depends on generator output quality), but pages load.

---

### Task 4: Custom Dart Script for VitePress Sidebar Config

This is the "approach 3" piece — a Dart script that walks the source tree, reads `{@category}` tags and class/function names, and emits the VitePress sidebar JSON.

**Files:**
- Create: `cli/tool/generate_devdocs_config.dart`

**Step 1: Create the metadata extraction script**

`cli/tool/generate_devdocs_config.dart`:

```dart
/// Extracts {@category} tags and public API structure from cli/lib/src/
/// and generates VitePress sidebar.json and categories.json.
///
/// Usage: dart run tool/generate_devdocs_config.dart [output_dir]
///   output_dir defaults to ../devdocs/.vitepress

import 'dart:convert';
import 'dart:io';

/// A discovered documentation entry.
class DocEntry {
  final String filePath;      // relative to cli/lib/src/
  final String fileName;      // e.g. agent_core.dart
  final String module;        // e.g. agent
  final String? category;     // from {@category ...}
  final List<String> classes; // public class names
  final List<String> enums;   // public enum names

  DocEntry({
    required this.filePath,
    required this.fileName,
    required this.module,
    this.category,
    this.classes = const [],
    this.enums = const [],
  });
}

void main(List<String> args) {
  final outputDir = args.isNotEmpty ? args[0] : '../devdocs/.vitepress';
  final srcDir = Directory('lib/src');

  if (!srcDir.existsSync()) {
    stderr.writeln('Error: run from cli/ directory (lib/src/ not found)');
    exit(1);
  }

  final entries = <DocEntry>[];

  // Walk all .dart files in lib/src/
  for (final file in srcDir.listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;

    final relativePath = file.path.substring('lib/src/'.length);
    final parts = relativePath.split('/');
    final module = parts.length > 1 ? parts[0] : 'core';
    final fileName = parts.last;

    final content = file.readAsStringSync();

    // Extract {@category ...} tag
    final categoryMatch =
        RegExp(r'\{@category\s+(.+?)\}').firstMatch(content);
    final category = categoryMatch?.group(1)?.trim();

    // Extract public class/enum names (simple regex — good enough)
    final classes = RegExp(r'^(?:abstract\s+)?class\s+(\w+)', multiLine: true)
        .allMatches(content)
        .map((m) => m.group(1)!)
        .where((name) => !name.startsWith('_'))
        .toList();

    final enums = RegExp(r'^enum\s+(\w+)', multiLine: true)
        .allMatches(content)
        .map((m) => m.group(1)!)
        .where((name) => !name.startsWith('_'))
        .toList();

    entries.add(DocEntry(
      filePath: relativePath,
      fileName: fileName,
      module: module,
      category: category,
      classes: classes,
      enums: enums,
    ));
  }

  // Group by module for sidebar
  final modules = <String, List<DocEntry>>{};
  for (final entry in entries) {
    modules.putIfAbsent(entry.module, () => []).add(entry);
  }

  // Module display order (matches dartdoc categories roughly)
  const moduleOrder = [
    'core',
    'agent',
    'llm',
    'config',
    'terminal',
    'rendering',
    'shell',
    'tools',
    'observability',
    'storage',
    'ui',
    'input',
    'skills',
    'web',
    'commands',
  ];

  // Build VitePress sidebar structure
  final sidebar = <Map<String, dynamic>>[];

  for (final mod in moduleOrder) {
    final files = modules[mod];
    if (files == null || files.isEmpty) continue;

    // Sort files within module
    files.sort((a, b) => a.fileName.compareTo(b.fileName));

    final items = <Map<String, dynamic>>[];
    for (final entry in files) {
      // Convert file_name.dart → file-name (VitePress page slug)
      final slug = entry.fileName
          .replaceAll('.dart', '')
          .replaceAll('_', '-');

      final label = entry.classes.isNotEmpty
          ? entry.classes.first
          : entry.enums.isNotEmpty
              ? entry.enums.first
              : _titleCase(slug);

      items.add({
        'text': label,
        'link': '/api/${entry.module}/$slug',
      });
    }

    sidebar.add({
      'text': _moduleDisplayName(mod),
      'collapsed': mod != 'agent' && mod != 'core',
      'items': items,
    });
  }

  // Build categories.json (category → list of qualified class names)
  final categories = <String, List<Map<String, String>>>{};
  for (final entry in entries) {
    if (entry.category == null) continue;
    categories.putIfAbsent(entry.category!, () => []);
    for (final cls in [...entry.classes, ...entry.enums]) {
      categories[entry.category!]!.add({
        'name': cls,
        'module': entry.module,
        'file': entry.fileName,
      });
    }
  }

  // Write outputs
  final outDir = Directory(outputDir);
  outDir.createSync(recursive: true);

  File('$outputDir/sidebar.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sidebar));
  File('$outputDir/categories.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(categories));

  print('Generated:');
  print('  $outputDir/sidebar.json  (${sidebar.length} modules)');
  print('  $outputDir/categories.json  (${categories.length} categories)');
}

String _moduleDisplayName(String mod) => switch (mod) {
      'llm' => 'LLM Providers',
      'ui' => 'UI',
      'web' => 'Web',
      _ => mod[0].toUpperCase() + mod.substring(1),
    };

String _titleCase(String slug) =>
    slug.split('-').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
```

**Step 2: Run the script**

Run: `cd cli && dart run tool/generate_devdocs_config.dart`
Expected: Prints "Generated: sidebar.json (N modules), categories.json (N categories)"

**Step 3: Verify output**

Run: `cat devdocs/.vitepress/sidebar.json | head -30`
Expected: JSON array with `{ "text": "Agent", "items": [...] }` structure.

---

### Task 5: Justfile Integration

**Files:**
- Modify: `justfile` (root)
- Modify: `cli/justfile`

**Step 1: Add `devdocs` commands to root `justfile`**

Add to root `justfile`:

```just
# Generate developer docs (API reference)
devdocs:
    cd cli && dart pub global run dart_doc_markdown_generator . ../devdocs/api
    cd cli && dart run tool/generate_devdocs_config.dart ../devdocs/.vitepress
    cd devdocs && npm run build

# Serve developer docs locally
devdocs-dev:
    cd cli && dart pub global run dart_doc_markdown_generator . ../devdocs/api
    cd cli && dart run tool/generate_devdocs_config.dart ../devdocs/.vitepress
    cd devdocs && npx vitepress dev

# Regenerate devdocs metadata only (fast)
devdocs-config:
    cd cli && dart run tool/generate_devdocs_config.dart ../devdocs/.vitepress
```

**Step 2: Update `.gitignore`**

Add to root `.gitignore`:

```
devdocs/api/
devdocs/.vitepress/dist/
devdocs/.vitepress/cache/
devdocs/.vitepress/sidebar.json
devdocs/.vitepress/categories.json
devdocs/node_modules/
```

**Step 3: Verify end-to-end**

Run: `just devdocs-dev`
Expected: Generates markdown, builds config, starts VitePress dev server with full sidebar.

---

### Task 6: Polish — API Index + Fallback Handling

**Files:**
- Modify: `devdocs/.vitepress/config.ts` (handle missing sidebar gracefully)
- Create: `devdocs/api/index.md` (API landing page, if not created by generator)

**Step 1: Ensure generated Markdown has proper frontmatter**

After running the generator, check the output. If files lack VitePress-friendly titles, create a small post-processing step in the justfile that prepends frontmatter. For example:

```bash
# In justfile, after generation:
# for f in devdocs/api/**/*.md; do ... add title frontmatter ... done
```

This is a stretch goal — check the generator output first before adding.

**Step 2: Add `devdocs/guide/index.md` placeholder**

```markdown
# Developer Guide

> Coming soon — hand-written guides for contributing to Glue internals.
```

**Step 3: Final verification**

Run: `just devdocs-dev`
Expected:
- Landing page renders with brutalist yellow/black theme
- Sidebar shows all modules grouped (Agent, Core, LLM Providers, etc.)
- Clicking sidebar items navigates to API docs
- Search works
- Code blocks use JetBrains Mono

---

## Key Decisions

1. **`devdocs/` at root** — parallel to `website/` and `cli/`, keeps concerns separated.
2. **Generated files gitignored** — `api/`, `sidebar.json`, `categories.json` are build artifacts. Only the VitePress scaffold + theme are committed.
3. **Simple regex-based metadata extraction** — no `package:analyzer` dependency needed. The `{@category}` tags and class/enum names are trivially extractable with regex. If we later need inheritance trees or method signatures, we upgrade to `package:analyzer`.
4. **Dark mode default** — matches the website's brutalist aesthetic.
5. **`dart_doc_markdown_generator` as content source** — if its output is poor quality, we can replace it with a custom Dart script later without changing the VitePress structure.

## Risk: Generator Output Quality

`dart_doc_markdown_generator` is a small third-party tool. If its output doesn't match VitePress conventions (bad filenames, missing titles, etc.), we have two fallbacks:
- **Quick fix:** Post-process the generated Markdown with a shell script
- **Long-term:** Replace with a custom Dart script using `package:analyzer` that emits exactly the Markdown we want

Test the generator early (Task 3) and assess before investing in Tasks 4-6.
