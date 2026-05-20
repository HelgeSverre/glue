mod cli
mod website
mod glue_core 'packages/glue_core'
mod glue_strategies 'packages/glue_strategies'
mod glue_harness 'packages/glue_harness'
mod glue_server 'packages/glue_server'
mod glue_runtimes 'packages/glue_runtimes'

default:
    @just --list --list-submodules

# Monorepo test pass
test: glue_core::test glue_strategies::test glue_harness::test glue_server::test glue_runtimes::test cli::test

# Monorepo build pass (CLI binary + unified site)
build: cli::build website::build

# Monorepo cleanup
clean: glue_core::clean glue_strategies::clean glue_harness::clean glue_server::clean glue_runtimes::clean cli::clean website::clean

# Monorepo quality gate
check: glue_core::check glue_strategies::check glue_harness::check glue_server::check glue_runtimes::check cli::check website::check

# Monorepo format pass
format: glue_core::format glue_strategies::format glue_harness::format glue_server::format glue_runtimes::format cli::format

# Run the live Daytona integration suite (requires DAYTONA_API_KEY).
daytona: glue_runtimes::daytona

# Run the live Sprites integration suite (requires SPRITES_TOKEN).
sprites: glue_runtimes::sprites

# Run the live Modal integration suite (requires `modal` CLI + login).
modal: glue_runtimes::modal
