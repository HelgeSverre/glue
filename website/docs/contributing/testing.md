# Testing

## Running Tests

```bash
# Run all unit tests
just test

# Run tests in a specific directory
just test test/llm/

# Run e2e integration tests (requires: ollama + qwen3:1.7b)
just e2e
```

Or using Dart directly:

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
just analyze    # dart analyze --fatal-infos
just format     # dart format .
just check      # analyze + test
```

::: tip
Run `just check` before submitting a PR to catch analysis issues and test failures early.
:::
