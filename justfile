mod cli
mod website
mod devdocs

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
