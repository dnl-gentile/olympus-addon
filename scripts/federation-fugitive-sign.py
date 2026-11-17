#!/usr/bin/env python3
"""Sign an attended, complete FUG1 replacement with the existing Olympus council key."""
import argparse
import json
import os
from pathlib import Path
import re
import runpy
import stat

MIN_TIME, MAX_TIME = 1577836800, 9999999999
MAX_LIFETIME = 31 * 86400
MAX_REVISION, MAX_NAMES, MAX_NAME_BYTES, MAX_BLOB = 2**31 - 1, 96, 96, 7400
FIELDS = {"region", "group", "faction", "revision", "issued", "expires", "names"}
NATIVE_REALM = re.compile(r"CAMWOW([A-Z]{2})[0-9]+Realm[0-9]+[A-Za-z]+")


def body_for(request, council):
    if not isinstance(request, dict) or request.keys() != FIELDS:
        raise ValueError("expected region, group, faction, revision, issued, expires and names")
    region, group, faction = (request[field] for field in ("region", "group", "faction"))
    if not isinstance(region, str) or not re.fullmatch(r"[A-Z]{2}", region):
        raise ValueError("region must be the two-letter code in the native Forever realm name")
    if not isinstance(group, str) or not re.fullmatch(r"Forever[A-Za-z]+", group):
        raise ValueError("group must be the exact Forever ruleset group")
    if faction not in council["FACTIONS"]:
        raise ValueError("faction must be Alliance or Horde")

    revision, issued, expires = (request[field] for field in ("revision", "issued", "expires"))
    if type(revision) is not int or not 1 <= revision <= MAX_REVISION:
        raise ValueError("revision must be an integer from 1 to 2147483647")
    if (type(issued) is not int or type(expires) is not int or not MIN_TIME <= issued < expires <= MAX_TIME
            or expires - issued > MAX_LIFETIME):
        raise ValueError("issued and expires must be Unix seconds at most 31 days apart")

    names = request["names"]
    if not isinstance(names, list) or len(names) > MAX_NAMES:
        raise ValueError("names must be a list of at most 96 characters")
    seen = set()
    for index, name in enumerate(names, 1):
        if not isinstance(name, str) or len(name.encode()) > MAX_NAME_BYTES:
            raise ValueError(f"name {index} must be an exact character name of at most 96 bytes")
        person, dash, realm = name.partition("-")
        words = person.split(" ")
        native = NATIVE_REALM.fullmatch(realm)
        if not dash or not 1 <= len(words) <= 2 or not all(word.isalpha() for word in words) or not native:
            raise ValueError(f"name {index} must use the exact Name-Realm or First Last-Realm form")
        if native.group(1) != region or council["forever_family"](realm) != group:
            raise ValueError(f"name {index} is outside the list's region or ruleset")
        key = name.casefold()
        if key in seen:
            raise ValueError(f"name {index} duplicates another character")
        seen.add(key)

    entries = ",".join(sorted(names, key=str.casefold)) or "-"
    return f"FUG1~{region}~{group}~{faction}~{revision}~{issued}~{expires}~{entries}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("request", type=Path, help="local JSON containing the complete list")
    parser.add_argument("output", type=Path, help="new file for the signed blob")
    args = parser.parse_args()

    council = runpy.run_path(str(Path(__file__).with_name("council-sign.py")))
    try:
        request = json.loads(args.request.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        parser.error("could not read the request as UTF-8 JSON")
    try:
        body = body_for(request, council)
    except UnicodeError:
        parser.error("names must be valid UTF-8")
    except ValueError as error:
        parser.error(str(error))
    council["fits"](body, MAX_BLOB, "the federation fugitive list")

    try:
        with open(council["KEY"], encoding="utf-8") as keyfile:
            mode = os.fstat(keyfile.fileno()).st_mode
            if not stat.S_ISREG(mode) or mode & 0o077:
                parser.error("the council key must be a regular file accessible only to its owner")
            signature = council["signature"](body, json.load(keyfile))
    except (KeyError, OSError, TypeError, ValueError):
        parser.error("could not sign with the configured council key")

    try:
        with open(os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w", encoding="utf-8") as output:
            output.write(body + "~" + signature + "\n")
    except FileExistsError:
        parser.error("the output already exists")
    except OSError:
        parser.error("could not write the signed list")
    print("Signed federation fugitive list written.")


if __name__ == "__main__":
    main()
