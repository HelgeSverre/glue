mod cli
mod website
mod devdocs
mod infra

default:
    @just --list --list-submodules

# Monorepo test pass (CLI tests + website static checks)
test: (cli::test) (website::check)

# Monorepo build pass (CLI binary + devdocs site + website validation)
build: (cli::build) (devdocs::build) (website::build)

# Monorepo cleanup
clean: (cli::clean) (devdocs::clean) (website::clean)

# Monorepo quality gate
check: (cli::check) (devdocs::check) (website::check)

# Fast CLI-only shortcuts
cli-build: (cli::build)
cli-test: (cli::test)
cli-check: (cli::check)
cli-clean: (cli::clean)

# Infra passthrough shortcuts (opt-in)
infra-up: (infra::up)
infra-down: (infra::down)
infra-ps: (infra::ps)
