mod cli
mod website
mod glue_core 'packages/glue_core'
mod glue_strategies 'packages/glue_strategies'
mod glue_harness 'packages/glue_harness'
mod glue_server 'packages/glue_server'

default:
    @just --list --list-submodules

# Monorepo test pass
test: glue_core::test glue_strategies::test glue_harness::test glue_server::test cli::test

# Monorepo build pass (CLI binary + unified site)
build: cli::build website::build

# Monorepo cleanup
clean: glue_core::clean glue_strategies::clean glue_harness::clean glue_server::clean cli::clean website::clean

# Monorepo quality gate
check: glue_core::check glue_strategies::check glue_harness::check glue_server::check cli::check website::check
