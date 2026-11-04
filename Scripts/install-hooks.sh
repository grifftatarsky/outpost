#!/bin/bash
# Usage: Scripts/install-hooks.sh            install the pre-commit hooks for this clone
#        Scripts/install-hooks.sh --remove   take them out again
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

pre_commit="$(command -v pre-commit || true)"
[ -z "$pre_commit" ] && [ -x /opt/homebrew/bin/pre-commit ] && pre_commit=/opt/homebrew/bin/pre-commit
if [ -z "$pre_commit" ]; then
    echo "error: pre-commit is not installed. Every hook is local, so nothing else is fetched once it is."
    exit 1
fi

if [ -n "$(git config --get core.hooksPath || true)" ]; then
    echo "error: core.hooksPath is set to $(git config --get core.hooksPath); pre-commit will not install over it."
    exit 1
fi

if [ "${1:-}" = "--remove" ]; then
    "$pre_commit" uninstall --hook-type pre-commit
    exit 0
fi

"$pre_commit" validate-config .pre-commit-config.yaml
"$pre_commit" install --hook-type pre-commit
echo "Installed. The hooks live in $(git rev-parse --git-common-dir)/hooks, so every worktree of this clone runs them."
echo "Skip one with SKIP=<hook-id> git commit; run them all over the tree with pre-commit run --all-files."
