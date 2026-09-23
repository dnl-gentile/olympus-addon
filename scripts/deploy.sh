#!/usr/bin/env bash
# Copies the addon to a Windows PC over SSH.
#   WOW_HOST=user@192.168.0.10 scripts/deploy.sh
# Optional: WOW_DIR (default C:/Program Files (x86)/World of Warcraft), WOW_FLAVOR (default _classic_era_)
set -euo pipefail
cd "$(dirname "$0")/.."
: "${WOW_HOST:?set WOW_HOST=user@ip}"
WOW_DIR="${WOW_DIR:-C:/Program Files (x86)/World of Warcraft}"
WOW_FLAVOR="${WOW_FLAVOR:-_classic_era_}"
DEST="$WOW_DIR/$WOW_FLAVOR/Interface/AddOns"
ssh "$WOW_HOST" "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '$DEST' | Out-Null; Remove-Item -Recurse -Force -ErrorAction SilentlyContinue '$DEST/Olympus'; exit 0\""
COPYFILE_DISABLE=1 tar --no-mac-metadata --exclude "._*" --exclude '.DS_Store' -cf - Olympus | ssh "$WOW_HOST" "tar -xf - -C \"$DEST\""
echo "deployed to $WOW_HOST:$DEST/Olympus  -> in game: /reload (restart the game if files were added)"
