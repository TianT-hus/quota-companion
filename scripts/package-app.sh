#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
configuration="${1:-debug}"
identity="${DEVELOPER_ID_APPLICATION:--}"
[[ "$configuration" == debug || "$configuration" == release ]] || exit 2
if [[ "$identity" != '-' && "$identity" != 'Developer ID Application:'* ]]; then
  print -u2 'Only ad-hoc or Developer ID Application signing is supported.'; exit 2
fi
export COPYFILE_DISABLE=1
if [[ "$configuration" == release ]]; then
  "$repo_root/scripts/build-universal.sh"
  build_bin="$repo_root/dist/universal"
else
  mkdir -p "$repo_root/.build/module-cache" "$repo_root/.build/swiftpm-cache"
  export CLANG_MODULE_CACHE_PATH="$repo_root/.build/module-cache"
  swift build --package-path "$repo_root" -c debug --disable-sandbox --cache-path "$repo_root/.build/swiftpm-cache"
  build_bin="$(swift build --package-path "$repo_root" -c debug --show-bin-path)"
fi
app="$repo_root/dist/朝夕.app"
[[ ! -e "$app" ]] || { print -u2 'Output app already exists. Choose a fresh build checkout.'; exit 2; }
contents="$app/Contents"
market="$contents/Resources/PluginMarketplace"
mkdir -p "$contents/MacOS" "$market/.agents/plugins" "$market/plugins"
cp "$repo_root/Packaging/Info.plist" "$contents/Info.plist"
cp "$build_bin/额度水滴-Dev" "$contents/MacOS/额度水滴-Dev"
cp "$build_bin/quota-companion-follow" "$contents/MacOS/"
mkdir -p "$contents/Library/LaunchAgents"
cp "$repo_root/Packaging/dev.quota-companion.follow.plist" "$contents/Library/LaunchAgents/"
swift "$repo_root/scripts/generate-brand-icon.swift" "$repo_root/.build/Zhaoxi.iconset"
iconutil -c icns "$repo_root/.build/Zhaoxi.iconset" -o "$contents/Resources/Zhaoxi.icns"
cp "$repo_root/Sources/QuotaCompanionApp/Resources/"*.png "$contents/Resources/"
cp "$repo_root/.agents/plugins/marketplace.json" "$market/.agents/plugins/"
cp -R "$repo_root/plugins/quota-companion" "$market/plugins/"
mkdir -p "$market/plugins/quota-companion/bin"
cp "$build_bin/quota-companion-mcp" "$market/plugins/quota-companion/bin/"
cp "$repo_root/LICENSE" "$repo_root/THIRD_PARTY_NOTICES.md" "$contents/Resources/"
cp "$repo_root/LICENSE" "$repo_root/THIRD_PARTY_NOTICES.md" "$market/plugins/quota-companion/"
# Sign nested executable first. No --deep signing, no source-tree binary writes.
sign_args=(--force --sign "$identity")
if [[ "$identity" != '-' ]]; then sign_args+=(--options runtime --timestamp); fi
codesign "${sign_args[@]}" "$market/plugins/quota-companion/bin/quota-companion-mcp"
codesign "${sign_args[@]}" "$contents/MacOS/quota-companion-follow"
codesign "${sign_args[@]}" "$app"
codesign --verify --deep --strict "$app"
print "$app"
