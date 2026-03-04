# Contributing

## Development Setup

1. Clone the repository.
2. Install Dart SDK 3.4+.
3. Run `cd cli && dart pub get`.

## Local Validation

Before opening a PR, run:

```sh
cd cli
dart format --set-exit-if-changed .
dart analyze
dart test
```

## Pull Requests

1. Keep changes focused and small.
2. Include tests for behavior changes.
3. Update docs when user-facing behavior changes.
4. Describe the problem and fix clearly in the PR description.

## Reporting Issues

Open an issue with:

- Expected behavior
- Actual behavior
- Reproduction steps
- Environment details (OS, Dart version, shell)
