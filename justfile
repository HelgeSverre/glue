mod cli
mod website
mod glue_core 'packages/glue_core'

default:
    @just --list --list-submodules

# Monorepo test pass
test: glue_core::test cli::test

# Monorepo build pass (CLI binary + unified site)
build: cli::build website::build

# Monorepo cleanup
clean: glue_core::clean cli::clean website::clean

# Monorepo quality gate
check: glue_core::check cli::check website::check
