mod cli
mod website
mod glue_core 'packages/glue_core'
mod glue_strategies 'packages/glue_strategies'

default:
    @just --list --list-submodules

# Monorepo test pass
test: glue_core::test glue_strategies::test cli::test

# Monorepo build pass (CLI binary + unified site)
build: cli::build website::build

# Monorepo cleanup
clean: glue_core::clean glue_strategies::clean cli::clean website::clean

# Monorepo quality gate
check: glue_core::check glue_strategies::check cli::check website::check
