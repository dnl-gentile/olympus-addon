#!/usr/bin/env bash
# Finds functions that read a global with the same name as a local declared later in
# the same file (the "local defined below" trap: the global is nil at runtime).
cd "$(dirname "$0")/../Olympus"
status=0
for f in *.lua; do
	locals=$(grep -oE '^\s*local (function )?[A-Za-z_][A-Za-z0-9_]*' "$f" | awk '{print $NF}' | sort -u)
	globals=$(luajit -bl "$f" | grep -oE 'GGET .*"[A-Za-z_][A-Za-z0-9_]*"' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
	for name in $(comm -12 <(echo "$locals") <(echo "$globals")); do
		echo "$f: '$name' is read as a global but declared local in this file"
		status=1
	done
done
exit $status
