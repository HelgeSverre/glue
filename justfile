mod cli
mod website

default:
    @just --list --list-submodules

# Monorepo test pass
test: cli::test

# Monorepo build pass (CLI binary + unified site)
build: cli::build website::build

# Monorepo codegen (CLI catalog/version + website reference docs)
gen: cli::gen website::gen

# Monorepo cleanup
clean: cli::clean website::clean

# Monorepo quality gate
check: cli::check website::check
