#!/usr/bin/env sh
# glue installer — served at https://getglue.dev/install.sh
#
# Downloads the latest glue binary from GitHub Releases and drops it in
# ~/.local/bin (or $GLUE_INSTALL_DIR if set).
#
# Usage:
#   curl -fsSL https://getglue.dev/install.sh | sh
#   curl -fsSL https://getglue.dev/install.sh | sh -s -- --version v0.1.0
#
# Environment variables:
#   GLUE_INSTALL_DIR   Where to write the binary (default: $HOME/.local/bin)
#   GLUE_VERSION       Specific version tag to install (default: latest)
#   GLUE_REPO          GitHub repo (default: helgesverre/glue)

set -eu

# ── Defaults ────────────────────────────────────────────────────────────────
REPO="${GLUE_REPO:-helgesverre/glue}"
INSTALL_DIR="${GLUE_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${GLUE_VERSION:-latest}"

# ── Arg parsing ─────────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)  VERSION="$2"; shift 2 ;;
    --dir)      INSTALL_DIR="$2"; shift 2 ;;
    --repo)     REPO="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --version <tag>     Install a specific release tag (default: latest)
  --dir <path>        Install directory (default: \$HOME/.local/bin)
  --repo <owner/name> GitHub repo (default: helgesverre/glue)
  -h, --help          Show this help

Environment overrides: GLUE_VERSION, GLUE_INSTALL_DIR, GLUE_REPO
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
done

# ── UI helpers ──────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"
  ACCENT="$(printf '\033[38;2;250;204;21m')"
  DIM="$(printf '\033[90m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""; ACCENT=""; DIM=""; RESET=""
fi

say()  { printf '%s◆%s %s\n' "$ACCENT" "$RESET" "$1"; }
note() { printf '%s  %s%s\n' "$DIM" "$1" "$RESET"; }
fail() { printf '✗ %s\n' "$1" >&2; exit 1; }

# ── Detect platform ─────────────────────────────────────────────────────────
UNAME_S="$(uname -s)"
UNAME_M="$(uname -m)"

case "$UNAME_S" in
  Linux)   OS="linux"  ;;
  Darwin)  OS="macos"  ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  *)       fail "unsupported OS: $UNAME_S" ;;
esac

case "$UNAME_M" in
  x86_64|amd64)   ARCH="x64"   ;;
  arm64|aarch64)  ARCH="arm64" ;;
  *)              fail "unsupported arch: $UNAME_M" ;;
esac

EXT=""
if [ "$OS" = "windows" ]; then
  EXT=".exe"
fi

ASSET="glue-${OS}-${ARCH}${EXT}"
say "${BOLD}glue installer${RESET}"
note "platform: ${OS}-${ARCH}"
note "repo:     ${REPO}"

# ── Check dependencies ──────────────────────────────────────────────────────
need() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}
need curl
need mkdir
need chmod
need mv

# ── Resolve version ─────────────────────────────────────────────────────────
api_url="https://api.github.com/repos/${REPO}/releases"
if [ "$VERSION" = "latest" ]; then
  api_url="${api_url}/latest"
else
  api_url="${api_url}/tags/${VERSION}"
fi

note "fetching release metadata…"
release_json="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api_url")" \
  || fail "could not fetch release info from $api_url"

# Grep the tag and the asset download URL — jq is optional.
resolved_tag="$(printf '%s' "$release_json" \
  | grep -m 1 '"tag_name":' \
  | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')"
[ -n "$resolved_tag" ] || fail "could not parse release tag"

download_url="$(printf '%s' "$release_json" \
  | grep '"browser_download_url":' \
  | sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]+)".*/\1/' \
  | grep -F "/${ASSET}" \
  | head -n 1)"
[ -n "$download_url" ] || fail "no asset named ${ASSET} in release ${resolved_tag}"

note "version:  ${resolved_tag}"

# ── Download ────────────────────────────────────────────────────────────────
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
tmp_file="${tmp_dir}/glue${EXT}"

say "downloading ${ASSET}…"
curl -fsSL -o "$tmp_file" "$download_url" || fail "download failed"
chmod +x "$tmp_file"

# ── Optional checksum verification ──────────────────────────────────────────
checksum_url="$(printf '%s' "$release_json" \
  | grep '"browser_download_url":' \
  | sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]+)".*/\1/' \
  | grep -F "/${ASSET}.sha256" \
  | head -n 1)"

if [ -n "$checksum_url" ]; then
  note "verifying checksum…"
  expected="$(curl -fsSL "$checksum_url" | awk '{print $1}')"
  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$tmp_file" | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp_file" | awk '{print $1}')"
  else
    actual=""
    note "shasum/sha256sum not found; skipping checksum verification"
  fi
  if [ -n "$actual" ] && [ "$expected" != "$actual" ]; then
    fail "checksum mismatch (expected $expected, got $actual)"
  fi
fi

# ── Install ─────────────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
target="${INSTALL_DIR}/glue${EXT}"
mv "$tmp_file" "$target"

say "installed to ${BOLD}${target}${RESET}"

# ── PATH hint ───────────────────────────────────────────────────────────────
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    note "tip: ${INSTALL_DIR} is not on your \$PATH."
    note "     add this to your shell rc:"
    note "       export PATH=\"${INSTALL_DIR}:\$PATH\""
    ;;
esac

# ── Done ────────────────────────────────────────────────────────────────────
say "try it out:"
note "  glue --version"
note "  glue --where"
note "  glue"
