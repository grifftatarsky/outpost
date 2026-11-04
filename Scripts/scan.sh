#!/bin/bash
# Usage: Scripts/scan.sh [simulator-name]          the package suite under Thread Sanitizer, then under
#                                                 Address and Undefined Behavior Sanitizers, then the
#                                                 dependency, analyzer and secret scan; ends in a digest
#        Scripts/scan.sh --only STEP[,STEP] [simulator]
#        Scripts/scan.sh --digest
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CHECK_LOGS="${TMPDIR:-/tmp}/carpenter-scan"

case "${1:-}" in
--only | --digest) exec "$root/Scripts/check-all.sh" "$@" ;;
*) exec "$root/Scripts/check-all.sh" --only thread-sanitizer,address-sanitizer,vulnerabilities "$@" ;;
esac
