set dotenv-load

mod cli
mod website

# Every Dart package in the pub workspace, in dependency order.
PKGS := "packages/glue_core packages/glue_strategies packages/glue_harness packages/glue_server packages/glue_runtimes cli"

# Packages with committed dart_mappable (.mapper.dart) output.
MAPPER_PKGS := "packages/glue_core packages/glue_strategies packages/glue_harness"

default:
    @just --list

# Resolve the pub workspace + site deps
[group('setup')]
deps:
    dart pub get
    npm ci --prefix website

# Remove all build artifacts
[group('setup')]
clean: website::clean
    rm -rf dist .dart_tool cli/.dart_tool cli/doc/api cli/diagrams
    rm -rf packages/*/.dart_tool

# Full quality gate
[group('check')]
check: deps format-check gen-check analyze test cli::check-layers website::check

# Format every Dart package + generated site reference
[group('check')]
format:
    dart format .
    cd website && npx prettier --write ./generated/*.md

# Fail if anything is unformatted
[group('check')]
format-check:
    dart format --output=none --set-exit-if-changed .

# Analyze the whole workspace
[group('check')]
analyze: build-info
    dart analyze --fatal-infos

# Unit tests for every package (path filters: use cli::test)
[group('check')]
test *args: build-info
    #!/usr/bin/env bash
    set -euo pipefail
    for p in {{ PKGS }}; do
      echo "→ $p"
      (cd "$p" && dart test {{ args }})
    done

# Regenerate every committed generated file
[group('gen')]
gen: build-info
    #!/usr/bin/env bash
    set -euo pipefail
    for p in {{ MAPPER_PKGS }}; do
      (cd "$p" && dart run build_runner build)
    done
    cd packages/glue_runtimes && dart run tool/gen_modal_sidecar.dart
    cd ../../cli
    dart run tool/gen_models.dart
    dart run tool/gen_version.dart
    dart run tool/gen_share_assets.dart
    dart run tool/gen_session_schemas.dart
    cd .. && just website::generate-reference

# Fail if any generated file is stale
[group('gen')]
gen-check: gen
    #!/usr/bin/env bash
    set -euo pipefail
    # --untracked-files=all so a *newly* generated file (e.g. a new
    # @MappableClass) fails too, not just edits to tracked ones.
    drift="$(git status --porcelain --untracked-files=all -- \
      '*.mapper.dart' '*_generated.dart' '*.g.dart' website/generated)"
    if [ -n "$drift" ]; then
      echo '✗ Generated files are out of date — run `just gen` and commit the result.' >&2
      echo "$drift" >&2
      exit 1
    fi
    echo '✓ Generated files match their sources.'

# build_info_generated.dart is gitignored but imported transitively, so it must
# exist before anything analyzes or runs.
[private]
build-info:
    cd cli && dart run tool/gen_build_info.dart

# Build + symlink glue into ~/.local/bin
[group('build')]
install: cli::install

# Remove the ~/.local/bin/glue symlink
[group('build')]
uninstall: cli::uninstall

# Unlink, rebuild from scratch, relink
[group('build')]
reinstall: cli::reinstall

# CLI binary + site
[group('build')]
build: deps cli::build website::build

# Live Daytona suite (needs DAYTONA_API_KEY)
[group('cloud')]
daytona:
    cd packages/glue_runtimes && dart test --run-skipped -t cloud-daytona test/daytona

# Live Sprites suite (needs SPRITES_TOKEN)
[group('cloud')]
sprites:
    cd packages/glue_runtimes && dart test --run-skipped -t cloud-sprites test/sprites

# Live Modal suite (needs `modal` CLI + login)
[group('cloud')]
modal:
    cd packages/glue_runtimes && dart test --run-skipped -t cloud-modal test/modal
