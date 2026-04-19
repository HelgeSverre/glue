#!/usr/bin/env node
// Generate per-page OpenGraph PNGs from a tokenized SVG template.
//
// Usage:   node scripts/og/generate.mjs
// Output:  website/public/og/<slug>.png  (and matching .svg for debugging)
//
// Walks every markdown page under website/ (skipping node_modules, dist,
// archive, generated), reads title + description from frontmatter, substitutes
// into scripts/og/template.svg, then rasterizes to PNG via @resvg/resvg-js.
//
// Fonts: we set `loadSystemFonts: true` and rely on the monospace/sans-serif
// fallback chain inside the template. For byte-identical output across CI,
// drop JetBrainsMono + Inter TTFs into scripts/og/fonts/ and they'll be
// picked up automatically.

import { readFile, writeFile, mkdir, readdir, stat } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import matter from 'gray-matter'
import { Resvg } from '@resvg/resvg-js'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const WEBSITE_ROOT = path.resolve(HERE, '..', '..')
const TEMPLATE_PATH = path.join(HERE, 'template.svg')
const FONTS_DIR = path.join(HERE, 'fonts')
const OUT_DIR = path.join(WEBSITE_ROOT, 'public', 'og')
// Debug SVGs land next to the PNGs only with --svg; otherwise we skip them
// so VitePress doesn't ship them in the production bundle.
const WRITE_DEBUG_SVG = process.argv.includes('--svg')

const SKIP_DIRS = new Set([
  'node_modules',
  '.vitepress',
  'public',
  'scripts',
  'snippets',     // partials, not pages
  '_archived',
  'generated',
  'api',
])

// ── Token substitution helpers ────────────────────────────────────────────

// Rough char-width → pixel conversion. Tuned for SemiBold sans-serif with
// system-font fallback (Helvetica / DejaVu Sans). A bit conservative so we
// never clip the right edge on full-width lines.
function charWidthPx(sizePx) {
  return sizePx * 0.58
}

// Pick the largest font size (between minSize and maxSize) at which the
// headline fits within maxLines. Returns the wrapped lines plus size.
function fitHeadline(text, { maxWidth, minSize, maxSize, step = 4, maxLines = 2 }) {
  for (let size = maxSize; size >= minSize; size -= step) {
    const lines = splitLines(text, maxWidth, size, maxLines + 1)
    if (lines.length <= maxLines) return { lines, size }
  }
  // Fallback: truncate to maxLines at minSize.
  const lines = splitLines(text, maxWidth, minSize, maxLines)
  return { lines, size: minSize }
}

// XML escape (conservative — template is trusted but content isn't).
function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

// Split a block of text into up to maxLines by greedy word packing.
function splitLines(text, maxWidth, sizePx, maxLines) {
  const perLineChars = Math.floor(maxWidth / charWidthPx(sizePx))
  const words = String(text).split(/\s+/).filter(Boolean)
  const lines = []
  let current = ''
  for (const w of words) {
    const tentative = current ? `${current} ${w}` : w
    if (tentative.length <= perLineChars) {
      current = tentative
    } else {
      if (current) lines.push(current)
      current = w
    }
    if (lines.length === maxLines) break
  }
  if (current && lines.length < maxLines) lines.push(current)
  // If we still have text left and we've hit maxLines, truncate the last line.
  if (lines.length === maxLines) {
    const last = lines[maxLines - 1]
    const cap = Math.max(0, perLineChars - 1)
    if (last.length > cap) lines[maxLines - 1] = last.slice(0, cap) + '…'
  }
  return lines
}

// Render headline lines with the final word of the final line highlighted
// in brand yellow. Single-word lines get the whole line highlighted.
function tspansForHeadline(lines, firstY, _size, lineHeight) {
  return lines
    .map((line, i) => {
      const y = firstY + i * lineHeight
      const isLast = i === lines.length - 1
      if (!isLast) {
        return `<tspan x="80" y="${y}">${esc(line)}</tspan>`
      }
      const idx = line.lastIndexOf(' ')
      if (idx === -1) {
        return `<tspan x="80" y="${y}"><tspan class="accent">${esc(line)}</tspan></tspan>`
      }
      const head = line.slice(0, idx)
      const tail = line.slice(idx + 1)
      return `<tspan x="80" y="${y}">${esc(head)} <tspan class="accent">${esc(tail)}</tspan></tspan>`
    })
    .join('')
}

// Plain tspan list — used for subtitles.
function tspansFromLines(lines, firstY, lineHeight) {
  return lines
    .map((line, i) => `<tspan x="80" y="${firstY + i * lineHeight}">${esc(line)}</tspan>`)
    .join('')
}

// ── Per-page derivation ───────────────────────────────────────────────────

const DEFAULTS = {
  eyebrow: 'GLUE · TERMINAL-NATIVE CODING AGENT',
  // Fallback title/subtitle for frontmatter that omits them — keeps the OG
  // card on-brand even on a bare page.
  title: 'A terminal agent where the browser is a runtime.',
  subtitle: 'Drive Chrome from the transcript — navigate, click, extract. Local, Docker, or cloud.',
}

// Routes where we deliberately want the root-site title rather than the page's
// frontmatter title (which would read like a doc heading).
const ROUTE_OVERRIDES = {
  '/': {
    eyebrow: 'GLUE · BROWSER AS A RUNTIME',
    title: 'Drive a real browser from the terminal.',
    subtitle: 'Navigate, click, extract. Local Chrome, Docker, or cloud — swapped with one config line.',
  },
}

// Map a markdown path to its cleanUrls route (matches vitepress `cleanUrls: true`).
// website/index.md            → /
// website/why.md              → /why
// website/docs/x/y.md         → /docs/x/y
function routeFor(relMd) {
  const noExt = relMd.replace(/\.md$/, '')
  if (noExt === 'index') return '/'
  if (noExt.endsWith('/index')) return '/' + noExt.slice(0, -'/index'.length)
  return '/' + noExt
}

// Map a route to a stable filesystem slug under public/og/.
// "/"                → index
// "/why"             → why
// "/docs/x/y"        → docs--x--y
function slugFor(route) {
  if (route === '/') return 'index'
  return route.replace(/^\//, '').replace(/\//g, '--')
}

// Pull the first `# Heading` from a markdown body — mirrors VitePress' own
// title inference when there's no frontmatter `title:`.
function extractH1(content) {
  const m = /^#\s+(.+?)\s*$/m.exec(content)
  return m ? m[1] : null
}

function coerceEyebrow(route, explicit) {
  if (explicit) return String(explicit).toUpperCase()
  if (route === '/') return DEFAULTS.eyebrow
  // /docs/advanced/browser-automation → GLUE · DOCS · ADVANCED · BROWSER AUTOMATION
  const parts = route.split('/').filter(Boolean).map(s => s.replace(/-/g, ' '))
  return ['GLUE', ...parts].join(' · ').toUpperCase()
}

// ── Main ──────────────────────────────────────────────────────────────────

async function walkMarkdown(dir, out = []) {
  const entries = await readdir(dir, { withFileTypes: true })
  for (const e of entries) {
    if (e.name.startsWith('.')) continue
    if (SKIP_DIRS.has(e.name)) continue
    const full = path.join(dir, e.name)
    if (e.isDirectory()) {
      await walkMarkdown(full, out)
    } else if (e.isFile() && e.name.endsWith('.md')) {
      out.push(full)
    }
  }
  return out
}

async function loadFonts() {
  if (!existsSync(FONTS_DIR)) return []
  const entries = await readdir(FONTS_DIR)
  return entries
    .filter(n => /\.(ttf|otf|woff2?)$/i.test(n))
    .map(n => path.join(FONTS_DIR, n))
}

async function main() {
  const template = await readFile(TEMPLATE_PATH, 'utf-8')
  const fontFiles = await loadFonts()

  await mkdir(OUT_DIR, { recursive: true })

  const mdFiles = await walkMarkdown(WEBSITE_ROOT)
  if (mdFiles.length === 0) {
    console.error('No markdown pages found under', WEBSITE_ROOT)
    process.exit(1)
  }

  const results = []
  for (const abs of mdFiles) {
    const rel = path.relative(WEBSITE_ROOT, abs).split(path.sep).join('/')
    const route = routeFor(rel)
    const slug = slugFor(route)

    const raw = await readFile(abs, 'utf-8')
    const { data, content } = matter(raw)

    const override = ROUTE_OVERRIDES[route] ?? {}
    const title = override.title ?? data.title ?? extractH1(content) ?? DEFAULTS.title
    const subtitle = override.subtitle ?? data.description ?? DEFAULTS.subtitle
    const eyebrow = coerceEyebrow(route, override.eyebrow ?? data.ogEyebrow)

    // Strip a leading "Glue · " prefix so the headline doesn't repeat the
    // brand; the eyebrow already says it.
    const cleanedTitle = String(title).replace(/^glue\s*·\s*/i, '').replace(/\s*·\s*glue\s*$/i, '')

    const { lines, size } = fitHeadline(cleanedTitle, {
      maxWidth: 1040,        // 1200 – 80 (left) – 80 (right margin)
      minSize: 48,
      maxSize: 82,
      step: 4,
      maxLines: 2,
    })

    // Layout: anchor the headline a fixed distance below the top rule; subtitle
    // follows under the last headline line; foot strip sits at y=555. We want
    // the whole block to comfortably fit between y=180 and y=500.
    const headlineLineHeight = Math.round(size * 1.08)
    const subtitleSize = 26
    const subtitleLineHeight = Math.round(subtitleSize * 1.3)
    const subtitleLines = splitLines(String(subtitle), 1040, subtitleSize, 2)

    const HEADLINE_Y = 220 + Math.round(size * 0.1)   // visual top ~200–215
    const HEADLINE_TSPANS = tspansForHeadline(lines, HEADLINE_Y, size, headlineLineHeight)

    const subtitleGap = 42
    const SUBTITLE_Y = HEADLINE_Y + (lines.length - 1) * headlineLineHeight + subtitleGap
    const SUBTITLE_TSPANS = tspansFromLines(subtitleLines, SUBTITLE_Y, subtitleLineHeight)

    const svg = template
      .replace(/{{EYEBROW}}/g, esc(eyebrow))
      .replace(/{{HEADLINE_SIZE}}/g, String(size))
      .replace(/{{HEADLINE_TSPANS}}/g, HEADLINE_TSPANS)
      .replace(/{{SUBTITLE_TSPANS}}/g, SUBTITLE_TSPANS)

    const pngPath = path.join(OUT_DIR, `${slug}.png`)

    if (WRITE_DEBUG_SVG) {
      const svgPath = path.join(OUT_DIR, `${slug}.svg`)
      await writeFile(svgPath, svg, 'utf-8')
    }

    const resvg = new Resvg(svg, {
      background: '#0A0A0B',
      font: {
        fontFiles,
        loadSystemFonts: true,
        defaultFontFamily: 'sans-serif',
      },
      fitTo: { mode: 'width', value: 1200 },
    })
    const png = resvg.render().asPng()
    await writeFile(pngPath, png)

    results.push({ route, slug, bytes: png.length })
  }

  results.sort((a, b) => a.route.localeCompare(b.route))
  for (const r of results) {
    const kb = (r.bytes / 1024).toFixed(1)
    console.log(`  ${r.route.padEnd(40)} → og/${r.slug}.png  (${kb} KB)`)
  }
  console.log(`✓ generated ${results.length} OG images in ${path.relative(WEBSITE_ROOT, OUT_DIR)}/`)
}

main().catch(err => {
  console.error(err)
  process.exit(1)
})
