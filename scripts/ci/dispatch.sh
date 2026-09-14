#!/usr/bin/env bash
# Dispatch the committed local revision, not an unverified remote branch tip.
set -euo pipefail
product=${1:-all}
case $product in all|linux-host|linux-client|macos-host|macos-client) ;; *) exit 2 ;; esac
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
test -z "$(git status --porcelain)" || { echo 'Commit the candidate before dispatch.' >&2; exit 1; }
branch=$(git symbolic-ref --quiet --short HEAD)
revision=$(git rev-parse HEAD)
remote=$(git ls-remote origin "refs/heads/$branch" | cut -f1)
test "$remote" = "$revision" || { echo 'Push this exact commit before dispatch.' >&2; exit 1; }
gh workflow run build.yml --ref "$branch" -f "product=$product" -f "source_sha=$revision"
