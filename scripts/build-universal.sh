#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
mkdir -p "$repo_root/.build-universal/module-cache" "$repo_root/.build-universal/swiftpm-cache" "$repo_root/dist/universal"
export CLANG_MODULE_CACHE_PATH="$repo_root/.build-universal/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/.build-universal/module-cache"
for arch in arm64 x86_64; do
  swift build --package-path "$repo_root" -c release --arch "$arch" --scratch-path "$repo_root/.build-universal/$arch" --disable-sandbox --cache-path "$repo_root/.build-universal/swiftpm-cache" -Xswiftc -debug-prefix-map -Xswiftc "$repo_root=." -Xswiftc -file-prefix-map -Xswiftc "$repo_root=."
done
for binary in "额度水滴-Dev" quota-companion-mcp; do
  lipo -create "$repo_root/.build-universal/arm64/arm64-apple-macosx/release/$binary" "$repo_root/.build-universal/x86_64/x86_64-apple-macosx/release/$binary" -output "$repo_root/dist/universal/$binary"
  strip -S "$repo_root/dist/universal/$binary"
  lipo "$repo_root/dist/universal/$binary" -verify_arch arm64 x86_64
done
