#!/usr/bin/env python3
"""Sign a reviewed public-key grant or revocation, never a guild enrollment.

Operators export /oly federation key. Review the exact native identity and role,
then sign a JSON file with request, role, guild, issued and expires. The private
author key stays in the same local key store used by council-sign.py.
"""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re


def fail(message):
    raise ValueError(message)


def canonical64(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{43}", value):
        fail("a canonical 32-byte public key is required")
    raw = base64.urlsafe_b64decode(value + "=")
    if len(raw) != 32 or base64.urlsafe_b64encode(raw).decode().rstrip("=") != value:
        fail("noncanonical public key")
    return value


def scope_of(scope):
    if not isinstance(scope, str) or not re.fullmatch(r"[A-Z]{2}:Forever(?:PvE|PvP|RP|RPPvP):(Alliance|Horde)", scope):
        fail("an exact Forever region, ruleset and faction are required")
    return scope


def timestamps(data):
    issued, expires = data.get("issued"), data.get("expires")
    if type(issued) is not int or type(expires) is not int or issued < 1577836800 or expires > 9999999999 or not 0 < expires - issued <= 31 * 86400:
        fail("issued/expires must be Unix seconds no more than 31 days apart")
    return issued, expires


def certificate_body(data):
    if set(data) != {"request", "role", "guild", "issued", "expires"}:
        fail("expected only request, role, guild, issued and expires")
    request = data.get("request")
    match = isinstance(request, str) and re.fullmatch(r"FKQ1~([^~]+)~([^~]+)~([^~]+)", request)
    if not match:
        fail("use the exact /oly federation key request")
    scope, name, pk = match.groups()
    scope_of(scope)
    identity = re.fullmatch(r"([^~|\x00-\x1f-]{1,48})-CAMWOW([A-Z]{2})\d+Realm\d+(PvE|PvP|RP|RPPvP)", name)
    if not identity or not 1 <= len(identity[1].split(" ")) <= 2 or not all(part.isalpha() for part in identity[1].split(" ")):
        fail("exact native character name and realm required")
    if identity[2] != scope[:2] or "Forever" + identity[3] != scope.split(":")[1]:
        fail("character realm and certificate scope differ")
    canonical64(pk)
    role, guild = data.get("role"), data.get("guild")
    if role not in ("council", "treasurer", "operator"):
        fail("role must be council, treasurer or operator")
    if not isinstance(guild, str) or not guild or guild.strip() != guild or len(guild.encode()) > 72 or re.search(r"[~|\x00-\x1f\x7f]", guild):
        fail("guild must be an exact guild name or '-' for a standing signed role")
    if role == "operator" and guild == "-":
        fail("an operator grant is confined to one guild")
    issued, expires = timestamps(data)
    return "~".join(map(str, ("FK1", scope, name, guild, role, issued, expires, pk)))


def sign(data, revoke=False, key_path=None):
    if revoke:
        if set(data) != {"scope", "issued", "certificate"}:
            fail("revocation expects scope, issued, certificate SHA-256")
        scope = scope_of(data["scope"])
        if type(data["issued"]) is not int or not 1577836800 <= data["issued"] <= 9999999999:
            fail("issued must be Unix seconds")
        digest = data["certificate"]
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            fail("certificate is its exact lowercase SHA-256 digest")
        body = "~".join(map(str, ("FKR1", scope, data["issued"], digest)))
    else:
        body = certificate_body(data)
    spec = importlib.util.spec_from_file_location("olympus_council_sign", Path(__file__).with_name("council-sign.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    path = Path(key_path or os.environ.get("OLYMPUS_COUNCIL_KEY", str(Path.home() / ".olympus/council-key.json")))
    key = json.loads(path.read_text())
    return body + "~" + module.signature(body, key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--revoke", action="store_true")
    args = parser.parse_args()
    try:
        print(sign(json.loads(args.input.read_text()), args.revoke))
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
