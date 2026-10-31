#!/usr/bin/env bash
# Rebuilds the QuickTrim Help Book search indexes. Run after editing any page
# in QuickTrim/QuickTrim.help/Contents/Resources/en.lproj, then rebuild the app.
set -euo pipefail
cd "$(dirname "$0")/QuickTrim/QuickTrim.help/Contents/Resources/en.lproj"
hiutil -I corespotlight -Caf QuickTrim.cshelpindex -vv . 2>&1 | grep -v "^Indexing" || true
hiutil -I lsm -Caf QuickTrim.helpindex -vv . 2>&1 | grep -v "^Indexing" || true
echo "Indexed: $(hiutil -I corespotlight -Af QuickTrim.cshelpindex 2>/dev/null | wc -l | tr -d ' ') entries"

# Help Viewer (Tips on recent macOS) caches books by their short version
# string, so bump it on every rebuild — otherwise updated pages are hidden
# behind a stale cached copy.
PLIST="$(cd ../.. && pwd)/Info.plist"
NEXT=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.$NEXT" "$PLIST"
echo "Help book version → 1.$NEXT"
