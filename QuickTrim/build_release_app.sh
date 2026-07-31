#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/QuickTrim/QuickTrim.xcodeproj"
SCHEME="QuickTrim"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="${TMPDIR:-/tmp}/QuickTrim-$STAMP.xcarchive"
OUT_DIR="$ROOT_DIR/Builds/QuickTrim-$STAMP-unsigned-release"
APP_NAME="QuickTrim.app"
INSTALL=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--install]

Builds an unsigned Release archive and copies QuickTrim.app to:
  Builds/QuickTrim-<timestamp>-unsigned-release/QuickTrim.app

Options:
  --install   Replace /Applications/QuickTrim.app. The replaced app (and any
              old QuickTrim.app.backup-* bundles) are moved to the Trash.
USAGE
}

# Move a file to the macOS Trash via Finder (never rm) so it stays
# recoverable. Note: Homebrew's `trash` uses the Linux XDG trash location
# (~/.local/share/Trash), which Finder never shows — don't use it.
send_to_trash() {
  osascript -e "tell application \"Finder\" to delete POSIX file \"$1\"" >/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  archive

mkdir -p "$OUT_DIR"
ditto "$ARCHIVE_PATH/Products/Applications/$APP_NAME" "$OUT_DIR/$APP_NAME"

echo "Built: $OUT_DIR/$APP_NAME"

if [[ "$INSTALL" -eq 1 ]]; then
  # Sweep any leftover backup bundles from earlier installs into the Trash
  for old_backup in /Applications/QuickTrim.app.backup-*; do
    if [[ -e "$old_backup" ]]; then
      send_to_trash "$old_backup"
      echo "Trashed old backup: $old_backup"
    fi
  done

  if [[ -e "/Applications/$APP_NAME" ]]; then
    BACKUP="/Applications/QuickTrim.app.backup-$STAMP"
    mv "/Applications/$APP_NAME" "$BACKUP"
    send_to_trash "$BACKUP"
    echo "Moved previous app to Trash: $(basename "$BACKUP")"
  fi

  ditto "$OUT_DIR/$APP_NAME" "/Applications/$APP_NAME"
  echo "Installed: /Applications/$APP_NAME"
fi
