#!/usr/bin/env bash
# CLI signer -> production RSA/certificate reader, exclusively with a throwaway
# key in a temporary directory. No author key or user HOME is read or changed.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v python3 >/dev/null 2>&1; then
	printf 'python3 not found: federation authority signing round trip skipped\n'
	exit 0
fi
authority_scratch=$(mktemp -d)
trap 'rm -rf "$authority_scratch"' EXIT
export OLYMPUS_COUNCIL_KEY="$authority_scratch/disposable-key.json"
python3 "$repo_root/scripts/council-sign.py" keygen >/dev/null
cp "$OLYMPUS_COUNCIL_KEY" "$authority_scratch/key-before.json"

python3 - "$repo_root" "$authority_scratch" <<'PY'
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

root, scratch = map(Path, sys.argv[1:])
signer = root / 'scripts/federation-sign.py'
now = 1795000000
pk = base64.urlsafe_b64encode(bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')).decode().rstrip('=')
request = f'FKQ1~US:ForeverPvE:Alliance~Silver Rock-CAMWOWUS1Realm2PvE~{pk}'
valid = dict(request=request, role='council', guild='-', issued=now - 10, expires=now + 86400)

def invoke(label, value, revoke=False, accepted=False):
    path = scratch / (label + '.json')
    path.write_text(json.dumps(value))
    result = subprocess.run([sys.executable, str(signer), str(path)] + (['--revoke'] if revoke else []), capture_output=True, text=True)
    if accepted:
        assert result.returncode == 0, (label, result.stderr)
        assert result.stdout.startswith('FKR1~' if revoke else 'FK1~'), label
        (scratch / (label + '.txt')).write_text(result.stdout.strip())
    else:
        assert result.returncode != 0 and not result.stdout, label + ' must be refused before signing'

invoke('valid', valid, accepted=True)
cases = {}
for label, field, value in [
    ('foreign-region', 'request', request.replace('US:Forever', 'EU:Forever')),
    ('foreign-ruleset', 'request', request.replace('ForeverPvE', 'ForeverPvP')),
    ('wrong-faction', 'request', request.replace(':Alliance~', ':Neutral~')),
    ('bare-name', 'request', request.replace('-CAMWOWUS1Realm2PvE', '')),
    ('boolean-issued', 'issued', True),
    ('boolean-expires', 'expires', True),
    ('too-long', 'expires', now + 32 * 86400),
    ('future-upper-bound', 'expires', 10000000000),
    ('reversed-times', 'expires', now - 20),
    ('unknown-role', 'role', 'king'),
    ('unscoped-operator', 'role', 'operator'),
    ('guild-separator', 'guild', 'Olympus~Azure'),
    ('guild-control', 'guild', 'Olympus\x7fAzure'),
    ('guild-leading-space', 'guild', ' Olympus Azure'),
]:
    value_dict = dict(valid); value_dict[field] = value; cases[label] = value_dict
cases['extra-fields'] = dict(valid, grants='everyone')
alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
noncanonical = pk[:-1] + alphabet[alphabet.index(pk[-1]) | 1]
cases['noncanonical-pubkey'] = dict(valid, request=request[:-len(pk)] + noncanonical)
cases['padded-pubkey'] = dict(valid, request=request + '=')
for label, value in cases.items():
    invoke(label, value)

certificate = (scratch / 'valid.txt').read_text()
revoke = dict(scope='US:ForeverPvE:Alliance', issued=now, certificate=hashlib.sha256(certificate.encode()).hexdigest())
invoke('revoke', revoke, revoke=True, accepted=True)
invoke('revoke-boolean', dict(revoke, issued=True), revoke=True)
invoke('revoke-extra', dict(revoke, reason='private'), revoke=True)
invoke('revoke-bad-hash', dict(revoke, certificate='a' * 63), revoke=True)

# Only the public modulus and reduction parameters enter Lua.
key = json.loads((scratch / 'disposable-key.json').read_text())
(scratch / 'public-key.lua').write_text('return { n=%s, mu=%s, k=%d }\n' % (json.dumps(key['n']), json.dumps(key['mu']), key['k']))
assert (scratch / 'disposable-key.json').read_bytes() == (scratch / 'key-before.json').read_bytes()
assert os.stat(scratch / 'disposable-key.json').st_mode & 0o077 == 0
print('federation authority signer: 1 valid grant, 17 invalid grants and 3 invalid revocations checked; key unchanged')
PY

cmp "$authority_scratch/key-before.json" "$OLYMPUS_COUNCIL_KEY"
luajit "$repo_root/tests/federation-authority-sign.lua" "$repo_root" "$authority_scratch"
