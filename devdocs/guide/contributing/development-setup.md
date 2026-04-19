# Development Setup

## Prerequisites

- Dart SDK 3.0+
- Git
- [just](https://github.com/casey/just) command runner (recommended)

## Clone and Install

```bash
git clone https://github.com/helgesverre/glue.git
cd glue/cli
dart pub get
```

## Run from Source

```bash
# Run directly
dart run bin/glue.dart

# Or build and install
just install    # compiles + symlinks to ~/.local/bin/glue
```

## Available Just Commands

```bash
just build      # Compile AOT native binary
just install    # Build and symlink to ~/.local/bin
just run        # Build and run interactively
just test       # Run unit tests
just e2e        # Run e2e integration tests
just analyze    # Static analysis
just format     # Format all Dart files
just check      # Analyze + test
just deps       # Get dependencies
just docs       # Generate API docs
just clean      # Remove build artifacts
```

::: tip
Run `just check` before submitting a pull request to ensure your changes pass both static analysis and tests.
:::

## Project Structure

```
glue/
  cli/           # Main CLI application
  devdocs/       # VitePress documentation site
  website/       # Marketing website
```
