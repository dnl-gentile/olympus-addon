#!/usr/bin/env bash
# Copies the bundle to a Windows PC over SSH: Olympus, Olympus_Arena and OlympusSiteAggregate,
# each removed there first.
#   WOW_HOST=user@192.168.0.10 scripts/deploy.sh
# Optional: WOW_DIR (default C:/Program Files (x86)/World of Warcraft), WOW_FLAVOR (default _classic_era_),
# OLY_TREE (default: the repository): the folder holding the bundled addon folders, as
# scripts/package.sh --test N writes dist/testN.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${WOW_HOST:?set WOW_HOST=user@ip}"
WOW_DIR="${WOW_DIR:-C:/Program Files (x86)/World of Warcraft}"
WOW_FLAVOR="${WOW_FLAVOR:-_classic_era_}"
TREE="${OLY_TREE:-.}"
FOLDERS=(Olympus Olympus_Arena OlympusSiteAggregate)
for folder in "${FOLDERS[@]}"; do
	[ -f "$TREE/$folder/$folder.toc" ] || { echo "no $folder/$folder.toc in $TREE" >&2; exit 1; }
done
DEST="$WOW_DIR/$WOW_FLAVOR/Interface/AddOns"
ssh "$WOW_HOST" "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '$DEST' | Out-Null; Remove-Item -Recurse -Force -ErrorAction SilentlyContinue '$DEST/Olympus','$DEST/Olympus_Arena','$DEST/OlympusSiteAggregate'; exit 0\""
COPYFILE_DISABLE=1 tar --no-mac-metadata --exclude "._*" --exclude '.DS_Store' -C "$TREE" -cf - "${FOLDERS[@]}" | ssh "$WOW_HOST" "tar -xf - -C \"$DEST\""
echo "deployed ${FOLDERS[*]} to $WOW_HOST:$DEST  -> in game: /reload (restart the game if files were added)"
