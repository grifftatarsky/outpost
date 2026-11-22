#!/bin/bash
# Usage: Scripts/test-tag.sh TAG [swift test options]   e.g. Scripts/test-tag.sh crypto --skip-build
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="${1:?name a tag: crypto, membership, sync, storage, ui or timing}"
shift
filter="$(python3 "$root/Scripts/tests-tagged.py" "$tag")"
exec swift test --package-path "$root/Packages/Carpenter" --filter "$filter" "$@"
