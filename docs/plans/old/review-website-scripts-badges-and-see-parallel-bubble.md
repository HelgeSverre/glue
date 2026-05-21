# Simplify `website/scripts/badges/`

## Context

The badge generator is a 3-file Node script (`config.mjs`, `design-tokens.mjs`, `generate.mjs`) that produces 187 files in `public/badges/` (SVG + PNG for 31 configs × 3 sizes, plus a JSON manifest). Wired up via `npm run badges` and consumed by exactly one page: `website/badges.md`, which only uses the SVG variants.

After reading the three files end-to-end and tracing every export to its consumer, several pieces are clearly dead, and a few small tweaks will tighten the rest. Nothing here changes generated output (except removing PNGs, which are unused) — the goal is leaner, easier-to-edit code.

## Scope

Files: `website/scripts/badges/config.mjs`, `website/scripts/badges/design-tokens.mjs`, `website/scripts/badges/generate.mjs`. No consumer changes required.

## Findings (priority order)

### 1. [HIGH] Dead `showIcon` parameter
**Where:** `config.mjs:17`, `generate.mjs:54,61-72,86,108`
No badge config sets `showIcon: false`. The param exists in the JSDoc typedef, the destructure in `generateSvg`, and gates the `iconGroup`/text-x offset. Remove the parameter entirely; always render the icon.

### 2. [HIGH] Unused `getStyles()` helper
**Where:** `config.mjs:269-273`
`generate.mjs` imports `STYLES` directly. `getStyles` is never called anywhere in the repo. Delete the function and its JSDoc.

### 3. [MEDIUM] Unused color tokens
**Where:** `design-tokens.mjs:10,13`
`surfaceLight` and `textLight` are exported but never referenced in any badge config. Delete them (or leave a comment if they're intentionally reserved — but absent that signal, drop them).

### 4. [MEDIUM] PNG generation is unused output
**Where:** `generate.mjs:97-100,144-147,151`
`badges.md` only references `badge.file` (the SVG). PNGs double the file count (93 unused PNGs) and ~double the generator runtime via `@resvg/resvg-js`. Two options:
- **Recommended:** Drop PNG output entirely. Remove `renderPng`, the resvg import, the PNG write, and `pngFile` from the manifest. (`@resvg/resvg-js` stays a devDep because `scripts/og/generate.mjs` still uses it.)
- Alternative: keep behind an opt-in `--png` flag.

### 5. [LOW] No-op clipPath in SVG template
**Where:** `generate.mjs:76-81`
`<clipPath id="r"><rect ... rx="0" .../></clipPath>` clips the SVG to its own bounding box (no rounded corners, full size). Has no visual effect. Remove the `<defs>` block and the `<g clip-path="url(#r)">` wrapper.

### 6. [LOW] Repetition in `BADGE_CONFIGS`
**Where:** `config.mjs:21-257`
Every badge in a category repeats `label: "Glue"`, `labelBg: COLORS.surface`, `category: "..."`. Optional cleanup: define small per-category factory helpers (e.g. `status(message, messageBg)`, `meme(message, messageBg, opts?)`) so the table reads as data, not boilerplate. Reduces the file from ~250 → ~80 lines of declarations. Defer if you'd rather keep the explicit/searchable form.

### 7. [LOW] Implicit `messageColor` footgun
**Where:** `generate.mjs:87`
`messageColor` defaults to `COLORS.surface` (dark). Any future badge with a dark `messageBg` that forgets `messageColor` will render invisible text. The reverse configs already work around this. Optional: derive a sensible default from `messageBg` luminance, or just document the convention with a one-line comment above the default.

## Recommended changes (apply in this order)

1. **`generate.mjs`**: remove `showIcon` param/branch (always render icon); remove `<defs>/<clipPath>` and the `<g clip-path>` wrapper; drop the PNG render, the resvg import, the PNG write, and `pngFile` from the manifest entry; update final `console.log` to count one file per badge instead of two.
2. **`config.mjs`**: delete `getStyles`; remove `showIcon` from the typedef; (optional) collapse declarations via category factories.
3. **`design-tokens.mjs`**: delete `surfaceLight` and `textLight`.
4. **`public/badges/`**: after the next run, the 93 stale `.png` files become orphans. Delete them with `find website/public/badges -name '*.png' -delete` so the directory matches what the generator now emits.

## Critical files

- `website/scripts/badges/generate.mjs` — main edits
- `website/scripts/badges/config.mjs` — typedef + helper cleanup
- `website/scripts/badges/design-tokens.mjs` — drop unused tokens
- `website/badges.md` — consumer; verify it still renders unchanged
- `website/package.json` — `npm run badges` script (no change needed)

## Verification

```sh
cd website
npm run badges                      # should print 93 badges, 93 files
ls public/badges/*.svg | wc -l      # 93
ls public/badges/*.png | wc -l      # 0 after the find -delete above
npm run dev                         # open /badges and confirm grid renders
```

Spot-check that `badges.md` still copy-paste-works for one status, one brand, one reverse, and one meme badge. SVG bytes should be identical except for the removed `<defs>/<clipPath>` wrapper — diff one file with `git diff` to confirm only the wrapper changed.
