#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR_DIR="$ROOT_DIR/generator"
BUILD_DIR="$GENERATOR_DIR/build"
DEFAULT_COMMIT_MESSAGE="📝 Update API Docs"
COMMIT_MESSAGE="${1:-$DEFAULT_COMMIT_MESSAGE}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

ensure_node_tooling() {
  if command -v node >/dev/null 2>&1 && node -v >/dev/null 2>&1 \
    && command -v yarn >/dev/null 2>&1 && yarn -v >/dev/null 2>&1; then
    return
  fi

  if [ -s "${HOME}/.nvm/nvm.sh" ]; then
    # Prefer the user's NVM-managed Node installation when available.
    # shellcheck disable=SC1090
    . "${HOME}/.nvm/nvm.sh"
    nvm use --silent >/dev/null 2>&1 || true
  fi

  require_cmd node
  require_cmd yarn
}

ensure_clean_worktree() {
  local status
  status="$(git status --short --untracked-files=normal -- . ':(exclude)generator' ':(exclude)scripts/update-api-docs.sh')"
  if [ -n "$status" ]; then
    echo "Working tree is not clean. Commit or stash existing changes first." >&2
    echo "$status" >&2
    exit 1
  fi
}

main() {
  cd "$ROOT_DIR"

  require_cmd git
  require_cmd rsync
  require_cmd cp
  ensure_node_tooling

  if [ ! -f "$GENERATOR_DIR/openapi/openapi.yaml" ]; then
    echo "Missing OpenAPI spec at $GENERATOR_DIR/openapi/openapi.yaml" >&2
    exit 1
  fi

  if [ ! -f "$GENERATOR_DIR/package.json" ]; then
    echo "Missing generator project at $GENERATOR_DIR" >&2
    exit 1
  fi

  ensure_clean_worktree

  (
    cd "$GENERATOR_DIR"
    yarn docusaurus clean-api-docs all
    yarn docusaurus gen-api-docs all
    yarn build
  )

  rsync -a --delete "$BUILD_DIR/api/" "$ROOT_DIR/api/"
  rsync -a --delete "$BUILD_DIR/assets/" "$ROOT_DIR/assets/"
  rsync -a --delete "$BUILD_DIR/img/" "$ROOT_DIR/img/"
  cp -f "$BUILD_DIR/.nojekyll" "$ROOT_DIR/.nojekyll"
  cp -f "$BUILD_DIR/404.html" "$ROOT_DIR/404.html"
  cp -f "$BUILD_DIR/sitemap.xml" "$ROOT_DIR/sitemap.xml"

  git add 404.html api assets img .nojekyll sitemap.xml scripts/update-api-docs.sh

  if git diff --cached --quiet; then
    echo "No documentation changes to commit."
    exit 0
  fi

  git commit -m "$COMMIT_MESSAGE"
}

main "$@"
