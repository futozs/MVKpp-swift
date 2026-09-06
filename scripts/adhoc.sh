#!/bin/bash
#
# Build a directly-installable .ipa of the iOS app — which embeds the Watch
# app, which embeds the widget — signed for the devices registered on the
# team. The provisioning profile is good for a year; TestFlight is handled
# separately by Xcode Cloud.
#
#   ./scripts/adhoc.sh [build-number]
#
# The build number defaults to a UTC timestamp, which always increases.
# The signing team comes from the project itself, so there is nothing to
# configure here.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="MVK++.xcodeproj"
SCHEME="MVK++"
BUILD_NUMBER="${1:-$(date -u +%Y%m%d%H%M)}"
BUILD_DIR="build/adhoc"
ARCHIVE="$BUILD_DIR/MVK++.xcarchive"

TEAM_ID="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ DEVELOPMENT_TEAM = /{print $2; exit}')"
[ -n "$TEAM_ID" ] || { echo "error: no DEVELOPMENT_TEAM set in $PROJECT" >&2; exit 1; }

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>release-testing</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

echo "==> Archiving build $BUILD_NUMBER (team $TEAM_ID)"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "==> Exporting .ipa"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$BUILD_DIR/export" \
    -allowProvisioningUpdates

IPA="$(ls "$BUILD_DIR"/export/*.ipa)"
echo
echo "Build $BUILD_NUMBER ready:"
echo "  $IPA"
echo
echo "Install it by dropping the file onto your device in Finder, or with:"
echo "  xcrun devicectl device install app --device <udid> \"$IPA\""
