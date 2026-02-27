mod cli
mod website

default:
    @just --list --list-submodules

# Run all tests
test: (cli::test)

# Build everything
build: (cli::build)

# Clean all build artifacts
clean: (cli::clean)

# Full check: analyze + test everything
check: (cli::check)

# Fuzzy-pick a recipe to run
pick:
    @just --choose
