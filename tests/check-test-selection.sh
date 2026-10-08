#!/usr/bin/env bash
# Exercise the actual runner without executing any addon test bodies.
set -euo pipefail
cd "$(dirname "$0")/.."
selection_log=$(mktemp /tmp/olympus-test-selection.XXXXXX)
trap 'rm -f "$selection_log"' EXIT
selection_status=0
env -u OLYMPUS_TEST_ARENA_MODULES -u OLYMPUS_TEST_WATCH_ONLY -u OLYMPUS_TEST_AUTHORITY_ONLY \
	OLYMPUS_TEST_FILTER='__no_such_olympus_test_selection__' \
	luajit tests/run.lua >"$selection_log" 2>&1 || selection_status=$?
if [ "$selection_status" -ne 1 ]; then
	printf 'Empty selection must exit 1; actual runner exited %s.\n' "$selection_status" >&2
	exit 1
fi
if ! grep -Fq 'No tests matched or were selected.' "$selection_log"; then
	printf 'Empty selection did not produce its diagnostic.\n' >&2
	exit 1
fi
if ! grep -Fq '0 passed, 0 failed' "$selection_log"; then
	printf 'Impossible filter unexpectedly executed test bodies.\n' >&2
	exit 1
fi
printf 'Empty test selection: refused by the actual runner.\n'
