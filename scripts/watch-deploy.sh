#!/usr/bin/env bash
# Keeps the WoW PC on the latest push of a branch: checks GitHub every 20 s and runs
# scripts/deploy.sh (from that commit) whenever the branch moves. Then /reload in game.
# Your working copy is not touched: each push is unpacked into a temp folder.
#   WOW_HOST=user@192.168.0.10 scripts/watch-deploy.sh [branch]
# Same optional WOW_DIR / WOW_FLAVOR as deploy.sh; WATCH_INTERVAL in seconds. Ctrl+C stops it.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
: "${WOW_HOST:?set WOW_HOST=user@ip}"
BRANCH="${1:-main}"
INTERVAL="${WATCH_INTERVAL:-20}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
last=""
echo "watching origin/$BRANCH -> $WOW_HOST (every ${INTERVAL}s, Ctrl+C to stop)"
while true; do
	if git fetch -q origin "$BRANCH" 2>/dev/null; then
		sha=$(git rev-parse FETCH_HEAD)
		if [ "$sha" != "$last" ]; then
			rm -rf "$WORK/tree" && mkdir -p "$WORK/tree"
			git archive "$sha" Olympus scripts | tar -xf - -C "$WORK/tree"
			if "$WORK/tree/scripts/deploy.sh" >/dev/null; then
				last=$sha
				echo "$(date +%H:%M:%S) deployed $(git log -1 --format='%h %s' "$sha")  -> /reload in game"
				osascript -e "display notification \"/reload in game\" with title \"Olympus ${sha:0:7} deployed\"" 2>/dev/null || true
			else
				echo "$(date +%H:%M:%S) deploy of ${sha:0:7} failed, trying again in ${INTERVAL}s"
			fi
		fi
	fi
	sleep "$INTERVAL"
done
