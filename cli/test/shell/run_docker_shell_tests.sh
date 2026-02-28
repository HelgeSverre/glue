#!/usr/bin/env bash
# Builds a Docker image with bash/fish/zsh/sh and runs ShellCompleter
# integration tests against each shell.
#
# Usage: ./test/shell/run_docker_shell_tests.sh
# Exit code 0 = all pass, 1 = at least one failure.

set -euo pipefail
cd "$(dirname "$0")/../.."  # cd to cli/

IMAGE="glue-shell-test"
SHELLS=("/bin/bash" "/usr/bin/fish" "/usr/bin/zsh" "/bin/sh" "")

echo "=== Building Docker image ==="
docker build -q -t "$IMAGE" -f test/shell/Dockerfile.shell-test . > /dev/null

failures=0
for shell in "${SHELLS[@]}"; do
  label="${shell:-"(unset)"}"
  echo ""
  echo "=== SHELL=$label ==="
  if docker run --rm -e "SHELL=$shell" "$IMAGE" 2>&1; then
    echo "--- PASS: $label ---"
  else
    echo "--- FAIL: $label ---"
    failures=$((failures + 1))
  fi
done

echo ""
docker rmi "$IMAGE" > /dev/null 2>&1 || true

if [ $failures -gt 0 ]; then
  echo "=== $failures shell environment(s) FAILED ==="
  exit 1
else
  echo "=== All shell environments PASSED ==="
  exit 0
fi
