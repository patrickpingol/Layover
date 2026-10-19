#!/bin/sh
# Re-signs a built Layover.app with a code-signing identity, innermost code first, as Sparkle documents
# for signing outside Xcode's export. Keeps the entitlements Xcode embedded and the hardened runtime.
#
# Usage: scripts/sign-app.sh <path/to/Layover.app> <identity name or SHA-1>
set -eu

app=$1
identity=$2
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"

sign() {
    codesign --force --timestamp=none --options runtime --sign "$identity" "$@"
}

sign "$sparkle/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
sign --preserve-metadata=entitlements "$app"

codesign --verify --deep --strict "$app"
