# Glue Brand Guide

> **"The coding agent that holds it all together."**

---

## Brand Identity

**Name**: Glue
**Tagline**: "The coding agent that holds it all together."
**Alternative taglines**: "Everything sticks." / "Bind your workflow."

**Concept**: Glue binds AI to your codebase. It's the adhesive that holds your development workflow together — tools, agents, models, worktrees all connected seamlessly.

---

## Color Palette

### Primary Colors

| Name             | Hex       | Usage                                          |
| ---------------- | --------- | ---------------------------------------------- |
| **Yellow**       | `#FACC15` | Signature Glue yellow. Primary actions, brand marks, key UI accents. |
| **Gold**         | `#EAB308` | Deeper gold for hover states, secondary accents. |
| **Amber (Warm)** | `#F59E0B` | Warm amber for warnings, highlights.           |

### Dark Mode Foundation

| Name                | Hex       | Usage                                |
| ------------------- | --------- | ------------------------------------ |
| **Background**      | `#0A0A0B` | Near-black, the canvas.             |
| **Surface**         | `#18181B` | Cards, panels, elevated surfaces.   |
| **Surface Elevated**| `#27272A` | Modals, dropdowns, popovers.        |
| **Border**          | `#3F3F46` | Subtle borders and dividers.        |
| **Border Bright**   | `#52525B` | Active/hover borders.               |

### Text Colors

| Name               | Hex       | Usage                              |
| ------------------ | --------- | ---------------------------------- |
| **Primary Text**   | `#FAFAFA` | Main content text.                 |
| **Secondary Text** | `#A1A1AA` | Descriptions, metadata.            |
| **Muted Text**     | `#71717A` | Timestamps, placeholders.          |
| **Yellow Text**    | `#FDE047` | Highlighted text, links on dark.   |

### Semantic Colors

| Name        | Hex       | Reference     |
| ----------- | --------- | ------------- |
| **Success** | `#22C55E` | green-500     |
| **Error**   | `#EF4444` | red-500       |
| **Warning** | `#F59E0B` | amber-500     |
| **Info**    | `#3B82F6` | blue-500      |

---

## Typography

### Brand / Display

- **Font**: `JetBrains Mono` or `Berkeley Mono` — monospace for all brand/display text
- **Weights**: Bold (700) for headings, Medium (500) for subheadings

### Body / UI

- **Font**: `Inter` — clean sans-serif for body text, UI labels
- **Weights**: Regular (400) for body, Medium (500) for labels, Semibold (600) for emphasis

### CLI / Code

- **Font**: System monospace / `JetBrains Mono`
- Terminal output uses the user's configured terminal font

---

## Logo

### Primary Mark

- The word **glue** in lowercase JetBrains Mono Bold
- The dot on the "g" is replaced with a filled circle in yellow (`#FACC15`)
- Can also use a standalone glue droplet icon (teardrop/hexagon hybrid shape)

### Logo Variants

1. **Full**: `glue` wordmark + droplet icon
2. **Compact**: Droplet icon only (for favicons, small spaces)
3. **CLI**: ASCII art version for terminal splash screen

### Clear Space

- Minimum clear space = height of the "g" character on all sides

### ASCII Logo

```
        .__
   ____ |  |  __ __   ____
  / ___\|  | |  |  \_/ __ \
 / /_/  >  |_|  |  /\  ___/
 \___  /|____/____/  \___  >
/_____/                  \/
```

---

## Voice & Tone

### Brand Voice

- **Direct**: No fluff. Say what you mean.
- **Technical**: Respect the developer audience. Don't dumb things down.
- **Warm**: Unlike cold, corporate dev tools. Glue has personality.
- **Confident**: Not arrogant. "Here's how it works" not "We're the best."

### Writing Style

- Short sentences. Active voice.
- Use "you" not "users" or "developers"
- Code examples over paragraphs
- Lowercase brand name in running text: "glue"
- Capitalized only at sentence start or in logos: "Glue"

---

## Visual Motifs

### Patterns

- **Dot grid**: Evenly spaced dots in yellow/gold on dark backgrounds — represents connections
- **Honeycomb**: Hexagonal patterns — references adhesion, structure
- **Connection lines**: Thin lines connecting dots — represents binding

### Iconography

- Line icons, 1.5px stroke weight
- Rounded caps and joins
- 24×24 base grid
- Yellow accent on dark backgrounds

### Photography / Imagery

- Dark, moody, atmospheric
- Code on screens with yellow accents
- Terminal screenshots with the Glue TUI

---

## CLI Design Language

### Prompt

```
❯ glue
```

The yellow `❯` chevron is the signature prompt character.

### Status Bar

```
 ● Streaming · claude-4-sonnet · 1,247 tokens
```

Yellow dot for active state, dim text for metadata.

### Tool Calls

```
┌ 🔧 read_file
│ path: src/main.dart
└ ✓ 47 lines
```

Box-drawing characters with yellow accent icons.

---

## Social & Marketing

### GitHub

- **Repo name**: `glue-cli`
- **Description**: "The coding agent that holds it all together. Built in Dart."
- **Topics**: `coding-agent`, `cli`, `dart`, `ai`, `llm`

### Website

- **Domain**: glue.dev (aspirational) / getglue.dev
- Dark mode only landing page
- Hero: ASCII/terminal animation showing Glue in action

---

## Design Tokens (CSS Custom Properties)

```css
:root {
  /* Brand */
  --glue-yellow: #FACC15;
  --glue-gold: #EAB308;
  --glue-amber: #F59E0B;

  /* Backgrounds */
  --glue-bg: #0A0A0B;
  --glue-surface: #18181B;
  --glue-surface-elevated: #27272A;

  /* Borders */
  --glue-border: #3F3F46;
  --glue-border-bright: #52525B;

  /* Text */
  --glue-text: #FAFAFA;
  --glue-text-secondary: #A1A1AA;
  --glue-text-muted: #71717A;
  --glue-text-yellow: #FDE047;

  /* Semantic */
  --glue-success: #22C55E;
  --glue-error: #EF4444;
  --glue-warning: #F59E0B;
  --glue-info: #3B82F6;

  /* Typography */
  --glue-font-mono: 'JetBrains Mono', 'Berkeley Mono', 'Fira Code', monospace;
  --glue-font-sans: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;

  /* Spacing */
  --glue-radius: 8px;
  --glue-radius-lg: 12px;
}
```

---

*Last updated: February 2026*
