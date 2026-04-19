---
pageClass: page-marketing
title: Brand
description: Glue marks, color, typography, and usage notes.
sidebar: false
aside: false
outline: false
---

# Brand

Glue's visual identity is intentionally quiet. The product is a terminal agent —
the marks and the website get out of its way.

## Name

Written **Glue**. Never all-caps, never stylized. The CLI binary is `glue`.

## Mark

<div class="brand-row">
  <figure>
    <img src="/brand/symbol-yellow.svg" alt="Glue symbol (yellow)" width="96" height="96" />
    <figcaption>Symbol · yellow</figcaption>
  </figure>
  <figure>
    <img src="/brand/symbol-dark.svg" alt="Glue symbol (dark)" width="96" height="96" />
    <figcaption>Symbol · dark</figcaption>
  </figure>
  <figure>
    <img src="/brand/symbol-white.svg" alt="Glue symbol (white)" width="96" height="96" />
    <figcaption>Symbol · white</figcaption>
  </figure>
</div>

## Wordmark

<div class="brand-row">
  <figure>
    <img src="/brand/wordmark-yellow.svg" alt="Glue wordmark (yellow)" height="40" />
    <figcaption>Wordmark · yellow</figcaption>
  </figure>
  <figure>
    <img src="/brand/wordmark-dark.svg" alt="Glue wordmark (dark)" height="40" />
    <figcaption>Wordmark · dark</figcaption>
  </figure>
  <figure>
    <img src="/brand/wordmark-white.svg" alt="Glue wordmark (white)" height="40" />
    <figcaption>Wordmark · white</figcaption>
  </figure>
</div>

## Color

Yellow is an **accent**, not decoration. Use it for focus states, the
`shipping` status pill, and the mark itself. Everything else is neutral.

| Role | Hex |
| --- | --- |
| Accent | `#FACC15` |
| Accent soft | `rgba(250, 204, 21, 0.12)` |
| Surface (dark) | `#0A0A0B` |
| Surface (light) | `#FFFFFF` |
| Text primary (dark) | `#E6E6E6` |
| Text primary (light) | `#111111` |
| Divider | `#222326` |
| Success | `#22C55E` |
| Warning | `#EAB308` |
| Error | `#EF4444` |
| Info | `#3B82F6` |

## Typography

- **Inter** — body text (400 / 500 / 600).
- **JetBrains Mono** — code, terminal blocks, monospace labels.

Do not use uppercase styling on headings. Do not stretch letter-spacing. The
default theme metrics are the canonical ones.

<!--@include: ./generated/brand-tokens.md-->

## Voice

- Say what Glue does; show commands and config; avoid marketing hype.
- Prefer examples over claims.
- Admit what is local, what is Docker, what is future work.

Banned words: *autonomous developer*, *10x*, *magic*, *revolutionary*.

## Downloads

- [`symbol-yellow.svg`](/brand/symbol-yellow.svg) · [`symbol-dark.svg`](/brand/symbol-dark.svg) · [`symbol-white.svg`](/brand/symbol-white.svg)
- [`wordmark-yellow.svg`](/brand/wordmark-yellow.svg) · [`wordmark-dark.svg`](/brand/wordmark-dark.svg) · [`wordmark-white.svg`](/brand/wordmark-white.svg)
- [`logo-yellow.svg`](/brand/logo-yellow.svg) · [`logo-dark-bg.svg`](/brand/logo-dark-bg.svg) · [`logo-light-bg.svg`](/brand/logo-light-bg.svg)
- [`readme-banner.svg`](/brand/readme-banner.svg)

<style scoped>
.brand-row {
  display: flex;
  gap: 1.5rem;
  flex-wrap: wrap;
  padding: 1rem 1.25rem;
  background: var(--vp-c-bg-soft);
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  margin: 1rem 0;
}

.brand-row figure {
  margin: 0;
  text-align: center;
}

.brand-row figcaption {
  margin-top: 0.5rem;
  font-family: var(--vp-font-family-mono);
  font-size: 0.75rem;
  color: var(--vp-c-text-3);
}

.brand-row img {
  display: block;
  max-width: 100%;
  height: auto;
}
</style>
