# Testing

## Running Tests

Recipes are namespaced per-package under the root justfile. Run from the
repo root, or `cd` into the package and use the unqualified names.

```bash
# Run all unit tests across the monorepo
just test

# CLI tests only (from repo root)
just cli::test

# Run tests in a specific directory (CLI package)
just cli::test test/llm/

# Run CLI e2e integration tests (requires: ollama + qwen3:1.7b)
just cli::e2e
```

Or using Dart directly (from `cli/`):

```bash
dart test
dart test test/llm/
dart test --run-skipped -t e2e
```

## Test Conventions

- Tests live in `test/` mirroring the `lib/src/` structure
- Unit tests use the standard `package:test` framework
- Test files are named `*_test.dart`
- Use descriptive `group()` and `test()` names
- E2E tests are tagged with `@Tags(['e2e'])` and skipped by default

## Static Analysis

```bash
just cli::analyze   # dart analyze --fatal-infos
just cli::format    # dart format .
just cli::check     # gen-check + analyze + test + layer hygiene (CLI)
just check          # Monorepo quality gate (all packages)
```

::: tip
Run `just check` (from the repo root) before submitting a PR to catch analysis
issues and test failures across the whole monorepo.
:::
