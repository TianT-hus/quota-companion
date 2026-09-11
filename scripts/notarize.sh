#!/bin/zsh
set -euo pipefail
# Run only after explicit permission to upload the audited app to Apple.
app="${1:?Provide an audited .app path}"
archive="${2:?Provide the final zip path}"
[[ -n "${NOTARYTOOL_PROFILE:-}" ]] || { print -u2 'Set a locally configured NOTARYTOOL_PROFILE.'; exit 2; }
codesign -dv "$app" 2>&1 | /usr/bin/grep -q 'Authority=Developer ID Application:' || { print -u2 'Developer ID Application signing is required.'; exit 2; }
codesign --verify --deep --strict "$app"
ditto --norsrc -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
# Recreate after stapling so the distributed ZIP contains the ticket.
ditto --norsrc -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive"
