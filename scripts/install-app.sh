#!/usr/bin/env bash
# Installs the release build to /Applications and restarts Zack. Run ./build.sh first.
# Quits a running Zack with SIGTERM (no Automation prompt); a dictation in progress is lost.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=".build/xcode-app/Build/Products/Release/Zack.app"
TARGET="/Applications/Zack.app"

[[ -d "$APP" ]] || { echo "missing $APP: run ./build.sh first" >&2; exit 1; }
codesign --verify --strict "$APP"

if pgrep -xq Zack; then
    pkill -x Zack
    for _ in {1..50}; do pgrep -xq Zack || break; sleep 0.1; done
    if pgrep -xq Zack; then
        echo "Zack did not quit; quit it from the menu and run again" >&2
        exit 1
    fi
fi
# The old version goes to the Trash, not deleted, so it can be restored.
if [[ -d "$TARGET" ]]; then
    mv "$TARGET" "$HOME/.Trash/Zack-$(date +%Y%m%d-%H%M%S).app"
fi
ditto "$APP" "$TARGET"
open "$TARGET"
echo "installed $TARGET ($(defaults read "$TARGET/Contents/Info" CFBundleShortVersionString))"
