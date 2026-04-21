mod cli
mod website

default:
    @just --list --list-submodules

# Monorepo test pass
test: cli::test

# Monorepo build pass (CLI binary + unified site)
build: cli::build website::build

# Monorepo cleanup
clean: cli::clean website::clean

# Monorepo quality gate
check: cli::check website::check
