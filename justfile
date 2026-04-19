mod cli
mod website

default:
    @just --list --list-submodules

# Monorepo test pass
test: (cli::test)

# Monorepo build pass (CLI binary + unified site)
build: (cli::build) (website::build)

# Monorepo cleanup
clean: (cli::clean) (website::clean)

# Monorepo quality gate
check: (cli::check) (website::check)

# ── Unified site (VitePress consolidation) ────────────────────────────────
# The old static `website/` module was archived — see _archived/website-2026-04/.
# `website/` is now the single source for both marketing and docs.

# Serve the unified site locally
site-dev:
    just website::dev

# Build the unified site
site-build:
    just website::build

# Quality gate for the unified site
site-check:
    just website::check
