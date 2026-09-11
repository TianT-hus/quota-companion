#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
mkdir -p "$repo_root/.build/module-cache" "$repo_root/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$repo_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/.build/module-cache"
python3 "$repo_root/scripts/validate-plugin.py"
swift test --no-parallel --package-path "$repo_root" --disable-sandbox --cache-path "$repo_root/.build/swiftpm-cache" "$@"
