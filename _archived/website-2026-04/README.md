# Archived static website (2026-04)

This directory preserves the previous static `website/` that was superseded by
the unified VitePress site at [`/devdocs/`](../../devdocs/). Content was
reimagined under the "minimal technical" visual direction and moved into
VitePress pages — see `TASK-23` in the backlog and the
[website redesign plan](../../docs/plans/2026-04-19-website-redesign-plan.md).

## What's here

- `website/*.html` — the prior brutalist-yellow marketing pages.
- `website/brand/` — the original brand SVGs (now mirrored in
  `devdocs/public/brand/` for the live site).
- `website/mascots/` — blob mascot PNGs. Retained for internal use only;
  they are **not** used on the public site.
- `website/styles.css` — the prior CSS.
- `website/justfile` and `website/.vercel/` — the prior build/deploy config.

## Why keep it

- Git history is preserved via `git mv`; the old pages stay trivially
  recoverable if any content needs to be pulled back.
- Brand SVGs are canonical here for posterity. The live-site copies in
  `devdocs/public/brand/` are the source of truth for runtime references.

## Do not

- Edit anything in this directory. It's a snapshot.
- Link to paths here from the live site.
