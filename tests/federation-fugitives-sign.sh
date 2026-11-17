#!/usr/bin/env bash
# Round trip of the operator's signer and the production addon reader with a disposable key.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v python3 >/dev/null 2>&1; then
	printf 'python3 not found: federation fugitive signing round trip skipped\n'
	exit 0
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export OLYMPUS_COUNCIL_KEY="$scratch/council-key.json"
python3 "$repo_root/scripts/council-sign.py" keygen >/dev/null
cp "$OLYMPUS_COUNCIL_KEY" "$scratch/original-key.json"

python3 - "$scratch" <<'PY'
import json
from pathlib import Path
import sys

scratch = Path(sys.argv[1])
p = dict(region="US", group="ForeverPvE", faction="Alliance", revision=1, issued=1800010000, expires=1800020000)
a, b = "Ámber Vale-CAMWOWUS1Realm2PvE", "Silver Rock-CAMWOWUS2Realm5PvE"
valid = [
    ("initial", dict(p, names=[a, b])),
    ("replacement", dict(p, revision=2, names=[b])),
    ("clear", dict(p, revision=3, names=[])),
]
oversized = [f"{'A' * 69}{chr(65 + i // 26)}{chr(65 + i % 26)}-CAMWOWUS2Realm5PvE" for i in range(96)]
invalid = [
    ("wrong-region", dict(p, names=[a.replace("CAMWOWUS", "CAMWOWEU")])),
    ("wrong-rules", dict(p, names=[a.replace("PvE", "PvP")])),
    ("bare-name", dict(p, names=["Ámber Vale"])),
    ("faction", dict(p, faction="Neutral", names=[])),
    ("duplicate-name", dict(p, names=[a, a.lower().replace("camwowus1realm2pve", "CAMWOWUS1Realm2PvE")])),
    ("invalid-times", dict(p, expires=p["issued"] + 32 * 86400, names=[])),
    ("invalid-revision", dict(p, revision=2**31, names=[])),
    ("extra-data", dict(p, names=[], note="Private decision text")),
    ("too-many", dict(p, names=oversized + [a])),
    ("too-large", dict(p, names=oversized)),
]
for label, request in valid + invalid:
    (scratch / (label + ".json")).write_text(json.dumps(request, ensure_ascii=False), encoding="utf-8")
PY

signer="$repo_root/scripts/federation-fugitive-sign.py"
for label in initial replacement clear; do
	python3 "$signer" "$scratch/$label.json" "$scratch/$label.txt" > "$scratch/stdout"
	if grep -Fq 'FUG1' "$scratch/stdout"; then
		printf 'signer printed the signed payload to stdout\n' >&2
		exit 1
	fi
done

for label in wrong-region wrong-rules bare-name faction duplicate-name invalid-times invalid-revision extra-data too-many too-large; do
	if python3 "$signer" "$scratch/$label.json" "$scratch/$label.txt" > "$scratch/error" 2>&1 || [ -e "$scratch/$label.txt" ]; then
		printf 'signer accepted invalid fixture %s\n' "$label" >&2
		exit 1
	fi
done

if python3 "$signer" "$scratch/clear.json" "$scratch/initial.txt" > "$scratch/error" 2>&1; then
	printf 'signer overwrote an existing file\n' >&2
	exit 1
fi
python3 - "$scratch/initial.txt" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).stat().st_mode & 0o077 == 0, "signed artifact must be owner-only"
PY
cmp "$scratch/original-key.json" "$OLYMPUS_COUNCIL_KEY"

luajit "$repo_root/tests/federation-fugitives-sign.lua" "$repo_root" "$scratch"
