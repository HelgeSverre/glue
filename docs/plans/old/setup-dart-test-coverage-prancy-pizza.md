# Setup Dart Test Coverage Reporting

## Context

The Glue CLI (`cli/`) has a full test suite (`just cli test`) but no coverage reporting. Adding a `just cli coverage` recipe makes it easy to see which parts of `lib/` lack test coverage, which is useful as the refactor branches continue to restructure modules (agent/, app/, ui/, etc.). The recipe should produce a browsable HTML report and open it automatically so it's a one-command flow.

## Approach

All steps use native / official Dart tooling. There is no first-party Dart HTML renderer, so we use `genhtml` from `lcov` — the universal standard for LCOV → HTML (same tool the Dart SDK itself uses in its own CI).

Add a `coverage` recipe to `cli/justfile` that:

1. Runs `dart pub global run coverage:test_with_coverage` — the official wrapper from `package:coverage` (maintained by the Dart team). It runs tests with the VM service, collects hitmaps, and writes `coverage/coverage.json` + `coverage/lcov.info` in one step.
2. Renders HTML: `genhtml coverage/lcov.info -o coverage/html`.
3. Opens `coverage/html/index.html` with `open` (macOS).

Preflight: if `genhtml` isn't on `PATH`, print `brew install lcov` and exit non-zero. If the global `coverage` package isn't activated, activate it silently (idempotent — matches the pattern already used by the `diagrams` recipe for `dcdg`).

Also update `.gitignore` to ignore `coverage/`.

No monorepo-root recipe — `just cli coverage` already works via the existing `mod cli` declaration and the user asked for exactly that surface.

## Files to modify

- `cli/justfile` — add `coverage` recipe (below the existing `integration` recipe, near the other test commands).
- `cli/.gitignore` — add `coverage/`.

## Recipe (to append to `cli/justfile`)

```just
# Generate HTML test coverage report and open it in the browser
coverage:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v genhtml >/dev/null 2>&1; then
      echo "genhtml not found. Install with: brew install lcov" >&2
      exit 1
    fi
    if ! dart pub global list 2>/dev/null | grep -q '^coverage '; then
      echo "Activating coverage package..."
      dart pub global activate coverage >/dev/null
    fi
    rm -rf coverage
    dart pub global run coverage:test_with_coverage
    genhtml coverage/lcov.info -o coverage/html --quiet
    echo "Coverage report: coverage/html/index.html"
    open coverage/html/index.html
```

## Verification

1. From repo root: `just cli coverage` — expect tests to run, LCOV to be written, HTML to build, and the report to open in the default browser.
2. Confirm `coverage/html/index.html` shows per-file line coverage for `lib/src/**`.
3. Confirm `coverage/` is untracked (`git status` clean after run).
4. Without `lcov` installed (`brew uninstall lcov`), the recipe should fail fast with the install hint.

## Assumptions / notes

- macOS-only `open` is fine — this repo's dev workflows already assume macOS/Linux (see `diagrams` recipe using `brew --prefix`).
- `--report-on=lib` scopes coverage to source (not test files, not generated).
- `bin/glue.dart` is not covered by unit tests, which is expected (that path is exercised by e2e tests only).
