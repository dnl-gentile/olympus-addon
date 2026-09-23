#!/usr/bin/env bash
# Prints the addon's SavedVariables (log + captured errors) from the Windows PC.
# WoW writes this file on /reload or logout.
#   WOW_HOST=user@192.168.0.10 scripts/logs.sh
set -euo pipefail
: "${WOW_HOST:?set WOW_HOST=user@ip}"
WOW_DIR="${WOW_DIR:-C:/Program Files (x86)/World of Warcraft}"
WOW_FLAVOR="${WOW_FLAVOR:-_classic_era_}"
ssh "$WOW_HOST" "powershell -NoProfile -Command \"Get-ChildItem '$WOW_DIR/$WOW_FLAVOR/WTF/Account/*/SavedVariables/Olympus.lua' | ForEach-Object { '== ' + \$_.FullName + '  (' + \$_.LastWriteTime + ')'; Get-Content -Raw \$_.FullName }\""
