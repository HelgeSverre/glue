# Glue Brand Guide

> **"The coding agent that holds it all together."**

---

## Brand Identity

**Name**: Glue
**Tagline**: "The coding agent that holds it all together."
**Alternative taglines**: "Everything sticks." / "Bind your workflow."

**Concept**: Glue binds AI to your codebase. It's the adhesive that holds your development workflow together — tools, agents, models, worktrees all connected seamlessly.

---

## Mascot — The Glue Blob

The Glue Blob is a cheerful, honey-yellow amorphous blob character. It's the heart of Glue's visual personality.

### Appearance

- **Body**: Viscous, dome-topped shape with melting drips at the base and small detached droplets on the ground
- **Color**: Honey-yellow/amber (`#FACC15`) with white sheen highlights and a thin dark-brown outline
- **Face**: Large expressive black eyes with white highlights, small open-mouthed smile
- **Style**: 2D vector illustration — minimalist, cartoonish, clean lines

### Poses

| Pose            | File                 | Usage                                                                                  |
| --------------- | -------------------- | -------------------------------------------------------------------------------------- |
| **Waving**      | `blob-waving.png`    | Default / welcome state, website hero areas                                            |
| **Hardhat**     | `blob-hardhat.png`   | Under construction, building features, website footer                                  |
| **Coding**      | `blob-coding.png`    | Active work — seated at laptop with code floating behind, blue screen glow, sweat drop |
| **Celebrating** | `blob-celebrate.png` | Success states, milestones                                                             |
| **Sleeping**    | `blob-sleeping.png`  | Idle / waiting states                                                                  |
| **Favicon**     | `blob-favicon.png`   | Browser tab, small icons                                                               |

### CLI Splash Screen

The blob is rendered as a half-block pixel art sprite in the terminal splash screen with a **liquid physics simulation** — clicking it sends ripple waves across its surface. Click too many times and it triggers a **goo explosion** particle system that fills the viewport.

### Usage Guidelines

- Always place on dark backgrounds (`#0A0A0B`) or yellow backgrounds (`#FACC15`)
- Minimum clear space = blob height on all sides
- Never distort, rotate, or recolor the blob
- Use the coding pose for active/working contexts, waving for welcome/landing

---

## Color Palette

### Primary Colors

| Name       | Hex       | Usage                                                                                    |
| ---------- | --------- | ---------------------------------------------------------------------------------------- |
| **Yellow** | `#FACC15` | Signature Glue yellow. Website background, primary actions, brand marks, key UI accents. |
| **Gold**   | `#EAB308` | Hover states, secondary accents.                                                         |
| **Amber**  | `#F59E0B` | Warnings, tool call highlights.                                                          |

### Dark Foundation

| Name                 | Hex       | Usage                                                    |
| -------------------- | --------- | -------------------------------------------------------- |
| **Background**       | `#0A0A0B` | Near-black canvas — nav, terminal blocks, dark sections. |
| **Surface**          | `#18181B` | Cards, panels, elevated surfaces.                        |
| **Surface Elevated** | `#27272A` | Modals, dropdowns, popovers.                             |
| **Border**           | `#3F3F46` | Subtle borders and dividers.                             |
| **Border Bright**    | `#52525B` | Active/hover borders.                                    |

### Text Colors

| Name               | Hex       | Usage                                        |
| ------------------ | --------- | -------------------------------------------- |
| **Primary Text**   | `#FAFAFA` | Main content text (on dark backgrounds).     |
| **Secondary Text** | `#A1A1AA` | Descriptions, metadata.                      |
| **Muted Text**     | `#71717A` | Timestamps, placeholders.                    |
| **Yellow Text**    | `#FDE047` | Highlighted text, links on dark backgrounds. |

### Semantic Colors

| Name        | Hex       |
| ----------- | --------- |
| **Success** | `#22C55E` |
| **Error**   | `#EF4444` |
| **Warning** | `#F59E0B` |
| **Info**    | `#3B82F6` |

---

## Typography

### Brand / Display

- **Font**: `JetBrains Mono` — monospace for all brand/display text
- **Weights**: Black (900) for hero headings, Bold (700) for section headings, Medium (500) for labels
- **Style**: All-caps with tight letter-spacing (`-0.04em`) for headings

### Body / UI

- **Font**: `Inter` — clean sans-serif for body text, UI labels
- **Weights**: Regular (400) for body, Medium (500) for labels, Semibold (600) for emphasis

### CLI / Code

- **Font**: System monospace / `JetBrains Mono`
- Terminal output uses the user's configured terminal font

---

## Website Design Language

The website follows a **brutalist design** aesthetic:

- **Background**: Solid yellow (`#FACC15`) — not dark mode
- **Text**: Near-black (`#0A0A0B`) on yellow
- **Dark sections**: Inverted — black background with yellow type
- **Borders**: 3px solid black, no border-radius
- **Hover effects**: `translate(-3px, -3px)` with `3px 3px 0` box-shadow — creates a lifted/offset effect
- **Tape separators**: Diagonal stripe pattern (black/yellow at 45°, 8px tall) between every section
- **Feature cells**: Grid of bordered boxes that invert on hover (black bg, yellow text)
- **Navigation**: Sticky black bar with yellow text, 4px bottom border, uppercase JetBrains Mono links
- **Buttons**: Thick-bordered, uppercase mono text, offset shadow on hover
- **Terminal mockups**: Black background with yellow border, yellow title bar, syntax-colored content

### Key Principle

The design is deliberately **loud, confident, and anti-minimalist** — it rejects the soft gradients and rounded corners of typical SaaS sites in favor of hard edges, bold type, and maximum contrast.

---

## Logo

### Primary Mark

- The word **GLUE** in uppercase JetBrains Mono Black (900 weight)
- Website hero renders at `clamp(48px, 12vw, 140px)` for maximum impact
- Navigation uses 22px bold with `-1px` letter-spacing

### Logo Variants

1. **Full**: `GLUE` wordmark — all caps, mono, black on yellow or yellow on black
2. **Compact**: Blob favicon for browser tabs and small spaces
3. **CLI**: ASCII art (shown below) for headers and help output

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

## CLI Design Language

### Prompt

```
❯ _
```

Yellow `❯` chevron in idle mode, red `!` in bash mode, dimmed `  ` during streaming.

### Status Bar

```
 ⠹ Generating  claude-sonnet-4-6  ~/project    tok 1247
```

Animated braille spinner (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) at 80ms during LLM streaming. Static indicators for other modes: `⚙ Tool`, `? Approve`, `! Running`.

### Tool Calls

```
 ▶ Tool: read_file
    path: src/main.dart
 ✓ Tool result
    47 lines read
```

Bold yellow headers with dim argument preview. Green `✓` for success, red `✗` for failure.

### Subagent Output

```
 ↳ [1/3] Implement auth module (5 steps…)
 ↳ [2/3] Write tests (3 steps…)
 ↳ [3/3] Update docs (✓)
```

Grouped by task, collapsed by default. Click to expand step details. Dimmed cyan to distinguish from main conversation.

### Bash Output

```
 ┌─ dart test ──────────────────────┐
 │ 00:05 +403: All tests passed!    │
 └──────────────────────────────────┘
```

Box-drawn fieldset with command name as legend.

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
- Capitalized only at sentence start or in logos: "Glue" / "GLUE"

---

## Visual Motifs

### Patterns

- **Diagonal tape**: Black/yellow stripe pattern at 45° — used between sections on the website
- **Dot grid**: Evenly spaced dots on dark backgrounds — represents connections
- **Box drawing**: Terminal box-drawing characters (`┌ ─ ┐ │ └ ┘`) — represents structure

### Iconography

- Line icons, 1.5px stroke weight
- Rounded caps and joins
- 24×24 base grid
- Yellow accent on dark backgrounds

---

## Design Tokens (CSS Custom Properties)

```css
:root {
  /* Brand */
  --glue-yellow: #facc15;
  --glue-gold: #eab308;
  --glue-amber: #f59e0b;

  /* Backgrounds */
  --glue-bg: #0a0a0b;
  --glue-surface: #18181b;
  --glue-surface-elevated: #27272a;

  /* Borders */
  --glue-border: #3f3f46;
  --glue-border-bright: #52525b;

  /* Text */
  --glue-text: #fafafa;
  --glue-text-secondary: #a1a1aa;
  --glue-text-muted: #71717a;
  --glue-text-yellow: #fde047;

  /* Semantic */
  --glue-success: #22c55e;
  --glue-error: #ef4444;
  --glue-warning: #f59e0b;
  --glue-info: #3b82f6;

  /* Typography */
  --glue-font-mono: "JetBrains Mono", "Berkeley Mono", "Fira Code", monospace;
  --glue-font-sans: "Inter", -apple-system, BlinkMacSystemFont, sans-serif;

  /* Spacing */
  --glue-radius: 0; /* brutalist: no rounded corners */
  --glue-border-width: 3px; /* heavy borders */
}
```

---

_Last updated: February 2026_
