#!/usr/bin/env python3
"""Signs the High Council's lists for the Olympus addon.

  python3 scripts/council-sign.py keygen                                  # once: ~/.olympus/council-key.json
  python3 scripts/council-sign.py sign "Name One,Name Two" [realm group]  # the names alone: dist/CouncilList.lua
  python3 scripts/council-sign.py council [council.json]                  # names, departments and titles: dist/CouncilList.lua
  python3 scripts/council-sign.py steward "<Name-Realm>" [Alliance|Horde] # mark the King's Steward, then sign as "council"
  python3 scripts/council-sign.py steward --remove "<Name-Realm>"         # end it: sign again without him
  python3 scripts/council-sign.py guild "<Guild Name>" [Alliance|Horde]  # approve a guild of Olympus, then sign as "council"
  python3 scripts/council-sign.py guild --remove "<Guild Name>"          # take it off: sign again without it
  python3 scripts/council-sign.py arbiter [--audit] "<Name-Realm>" [Alliance|Horde] # a signed arena arbiter (1.2), then sign as "council"
  python3 scripts/council-sign.py arbiter --remove "<Name-Realm>"        # end it: sign again without him
  python3 scripts/council-sign.py apostle "<Name-Realm>" [Alliance|Horde] # one of the Church's Twelve Apostles (1.1.6), then sign as "council"
  python3 scripts/council-sign.py apostle --remove "<Name-Realm>"        # end it: sign again without him
  python3 scripts/council-sign.py king "<Name-Realm>" [Alliance|Horde]   # that side's King (1.3.4), then sign as "council"
  python3 scripts/council-sign.py king --remove [Alliance|Horde]
  python3 scripts/council-sign.py queen "<Name-Realm>" [Alliance|Horde]  # that side's Queen (presentation only), then sign
  python3 scripts/council-sign.py queen --remove [Alliance|Horde]
  python3 scripts/council-sign.py speedrunner "<Name-Realm>" [Alliance|Horde] # the Olympus Speedrunner (1.5.5), then sign
  python3 scripts/council-sign.py speedrunner --remove [Alliance|Horde]
  python3 scripts/council-sign.py quaestor "<Name-Realm>" [Alliance|Horde]    # a Quaestor, the Treasurer's executor (1.5.5), then sign
  python3 scripts/council-sign.py quaestor --remove "<Name-Realm>"
  python3 scripts/council-sign.py treasurer "<Treasurer-Realm>[,<Mail-Realm>,...]" [Alliance|Horde] # the Treasurer first
  python3 scripts/council-sign.py treasurer --remove [Alliance|Horde]
  python3 scripts/council-sign.py author "<Name-Realm>" [Alliance|Horde] # one of the author's own characters (1.3.4)
  python3 scripts/council-sign.py author --remove "<Name-Realm>"
  python3 scripts/council-sign.py realm "<Realm>" <pvp|pve|rp|rppvp|hardcore> <NA|EU>  # what a realm is (1.3.4)
  python3 scripts/council-sign.py realm --remove "<Realm>"
  ... --group "<Realm>+<Realm>"   # with council, steward, guild, arbiter, apostle, king, queen, speedrunner, quaestor, treasurer, author or realm:
                                  # the realm group the lists are for, kept in the council file ("realm")
  python3 scripts/council-sign.py check [CouncilList.lua]                 # (or --check) read back what was signed
  python3 scripts/council-sign.py seal "RS1~..."                         # reviewed monthly Records request; prints its signed seal

The private key never leaves ~/.olympus. The addon carries only the public key (Sign.lua) and
checks the signature: RSA-2048, e = 3, PKCS#1 v1.5 over SHA-256. CouncilList.lua holds the lists:
it is copied to the author's own game only (never in the repository or the public zip).

"sign" writes the name list alone (HS1, ns.COUNCIL_SIGNED), as before 0.9.9. "council" reads
the council from a JSON file (~/.olympus/council.json unless a path is given):

  {"realm": "optional realm group", "public": false,
   "departments": [{"name": "Department of War", "icon": "INV_Sword_04",
                    "members": [{"name": "First Surname", "title": "Operations Director"}]}],
   "members": [{"name": "First Surname", "title": "optional"}]}

and writes two lists: the names (HS1, every name of the departments and of "members", which
0.9.8 clients read too) and the departments and titles (HT1, ns.COUNCIL_TITLES, 0.9.9):
  HT1~<time>~<realm group>~<public 0|1>~<departments>~<signature>
  <departments>: <name>^<icon>^<First Surname>=<title>,...;...   ("members": the entry with no name)
"members" are the councillors outside any department; a title and a department's icon (a game
icon's name under Interface\\Icons, or its file number) may be left out. "public": whether
everyone sees the council in the census (until then, the councillors and the author alone).

The King's Steward (1.0.0): an optional "stewards" list in the same file names the characters
who name Hands of their own beside the King's, set up for the King what only he could set up
(the treasury's keepers and what the army sees of it) and send the Crown's decrees on every
client:

  "stewards": ["First Surname-Realm", {"name": "First Surname-Realm", "faction": "Horde"}]

A plain name is the Alliance King's Steward; the Horde gets one only when the list names one
for it. The titles list carries them in an entry of its own after the departments, one per
faction ("^steward^<faction>^<First Surname-Realm>,..."): three "^" where a department has two,
so 0.9.9 clients leave it out unread and still take, show and pass on the whole list. At most 3
per faction; a name of letters with one space at most, its realm (that realm's group) or none
(any realm of the list's group). "steward" adds one to the council file (rewritten whole, the
rest kept) and signs the council at once; "steward --remove" takes him off and signs again: the
newer list ends it on every client. "check" (or --check) reads a written CouncilList.lua back,
checks both signatures with the key and prints the names, departments and Stewards it holds.

The approved guilds (1.1): guilds of Asmon's Olympus whose names the addon's name rule leaves out
(it leaves Olympian and Olympia out on purpose) count as Olympus guilds once an optional
"guilds" list in the same file names them:

  "guilds": ["Guild Name", {"name": "Guild Name", "faction": "Horde"}]

A plain name is an Alliance guild. The titles list carries them after the Stewards, one entry per
faction ("^guilds^<faction>^<Guild Name>,..."), three "^" again, so clients before 1.1 leave it out
unread. At most 20 per faction; a name of letters and spaces, 24 characters at most, as the game
allows; each once. "guild" adds one to the council file and signs the council at once; "guild
--remove" takes it off and signs again. Both print the signed titles list whole, for pasting in
game with /oly approved paste: the first member of such a guild has no other way to get it (its
addon hears nothing of Olympus until it holds it); his addon then passes it to his guild.

The Blood Arena's signed arbiters (1.2): an optional "arbiters" list in the same file names the
characters who may arbitrate public fights and direct rehearsals on test builds, whatever the
King's own list says, one faction's at most MAX_ARBITERS; "audit": true also makes one an auditor
(he receives the arena's ledgers):

  "arbiters": ["First Surname-Realm", {"name": "First Surname-Realm", "faction": "Horde", "audit": true}]

The titles list carries them after the approved guilds, one entry per faction
("^arbiter^<faction>^<First Surname-Realm>[+a],..."), three "^" again, so clients before 1.2 leave
it out unread. A name as a Steward's (a realm of the list's group). "arbiter" adds one (with
--audit: an auditor too) and signs the council at once; "arbiter --remove" takes him off and signs
again. No arena file names the author: this entry is how his own character arbitrates too.

The Missionary Church of Olympus's Twelve Apostles (1.1.6): an optional "apostles" list in the same
file names them, at most MAX_APOSTLES per faction, set once here so they hold on every client with
nobody online (the Head of the Church, the King or the author may change them in game later, until
a newer list):

  "apostles": ["First Surname-Realm", {"name": "First Surname-Realm", "faction": "Horde"}]

The titles list carries them after the arbiters, one entry per faction
("^apostles^<faction>^<First Surname-Realm>,..."), three "^" again, so clients before 1.1.6 leave it
out unread. A name as a Steward's (a realm of the list's group). "apostle" adds one and signs the
council at once; "apostle --remove" takes him off and signs again. Asmongold is the immutable
Head of the Church, using the addon's canonical King identity. It is not an assignable Apostle
position. Remove legacy "head": true flags before signing a new list; old signed starred lists
remain readable by the addon but confer no Head authority.

The launch identities (1.3.4; Queen added in 1.4.6). The addon pins the King, the Queen, the Treasurer and the author by name on the
beta's realm group only (names get sniped on launch realms, so the code names nobody for them). On
any other realm group they are whom the titles list names for it, from optional fields of the same
file:

  "king": {"Alliance": "First Surname-Realm", "Horde": "First Surname-Realm"},
  "queen": {"Alliance": "First Surname-Realm", "Horde": "First Surname-Realm"},
  "speedrunner": {"Alliance": "First Surname-Realm"},
  "quaestor": {"Alliance": ["First Surname-Realm"]},
  "treasurer": {"Alliance": ["Treasurer Name-Realm", "Mail Character-Realm"]},
  "author": ["First Surname-Realm", {"name": "First Surname-Realm", "faction": "Horde"}],
  "realms": [{"name": "Realm", "kind": "pvp", "region": "NA"}]

The titles list carries them after the Apostles, three "^" again, so clients before 1.3.4 leave them
out unread and still take, show and pass on the whole list:
  ^king^<faction>^<Name-Realm>   ^queen^<faction>^<Name-Realm>   ^treasurer^<faction>^<Name-Realm>,...   ^author^<faction>^<Name-Realm>,...
  ^realms^<NA|EU>^<Realm>=<pvp|pve|rp|rppvp|hardcore>,...
  ^speedrunner^<faction>^<Name-Realm>   (1.5.5: the Olympus Speedrunner, the level race's gold comet and its title, no authority)
  ^quaestor^<faction>^<Name-Realm>,...  (1.5.5: the Quaestors, the Treasurer's executors: the Treasurer's blue dragon, their title
                                         and a trusted relay of their side; none of the Treasurer's powers; 2 a faction)
Every name needs its realm (a name without one would count on every realm of the group), a realm of
the list's group. One King and one Queen a faction; the Queen is a presentation identity only and
receives no King, council, officer or moderation authority. The Treasurer first, then his mail characters (where the dues'
mail goes), 4 in all; 8 author's characters a faction (both factions' count: the dev's privileges
alone, never the King's or the council's); 40 realms a region. A side named here has that King or
Treasurer alone; a side named nowhere keeps the code's pin on the beta alone, and on a launch realm
group has none: no guild master of a guild called Olympus stands for the King where this list reaches.

Launch day, once the realms and the characters exist (nothing in the repository names them):
  1. python3 scripts/council-sign.py council --group "<Realm>+<Realm>"
     The launch realm group, kept in the council file. While a Steward, an arbiter, an Apostle or a
     signed leader carries a realm of another group, it is refused with the whole list of them and
     the command that takes each off.
  2. author "<Name-Realm>" (each of your characters), king "<Name-Realm>" [Horde], queen "<Name-Realm>" [Horde],
     treasurer "<Treasurer-Realm>,<Mail-Realm>" [Horde], realm "<Realm>" <kind> <NA|EU> (each realm):
     each signs the whole council again and prints the titles list to paste. Sign the King once his
     character leads the King's guild: a census report of that guild naming another guild master is
     refused while a King is named (as on the beta), and its guild master is the King only if named.
  3. check; copy dist/CouncilList.lua into the game (Interface/AddOns/Olympus/) and /reload: that
     client takes both lists and relays them. Anyone else in Olympus can paste the printed HT1~ text
     with /oly approved paste, and passes it on. /oly status: "identities: King signed ...".

Cross-guild leadership migration (1.2): absent by default, so the documented census behaviour is
unchanged. It is activated only by the deliberately explicit "leadership" object below:

  "leadership": {"mode": "enforce", "epoch": 1, "factions": ["Alliance"],
    "guilds": [{"guild": "Olympus II", "leader": "Lord Name-ClassicBetaPvP",
                "officers": ["Captain One-ClassicBetaPvP2"], "faction": "Alliance"}]}

Every character must carry an exact realm from the signed realm group. Each enforced faction gets
an entry even when its guilds list is empty (the signed empty tombstone). Once a client accepts an
enforcing entry, it remembers that one-way boundary locally: an expired, malformed, lower-epoch or
newer absent entry grants nobody and never reopens census authority. Increase "epoch" for a new
authority generation; ordinary additions/removals may keep it. The manifest lasts 14 days.

Leadership is signed separately from HT1 as one or more HA1 parts in
`ns.COUNCIL_AUTHORITY`. Each part binds the SHA-256 of the complete canonical manifest and is
independently signed. Receivers activate the one-way fail-closed boundary on the first valid part,
but grant roles only after every part of that exact set verifies and the joined digest matches.
Parts split only between guild entries. Older addon versions ignore H2/H3. The set is deliberately
bounded; the signer refuses anything beyond the addon's guild, person, part and byte limits.

Every list gets a newer time than the last one signed with the key (kept in the key file as
"last_at"): clients keep a list only if it is newer than theirs, so two lists signed in the
same second both reach them. Anything the addon would not take is refused here, before anything
is signed: a "~" or "|" or a control character anywhere; a "," in a name; a "^", ";", "=" or
"," in a name, title or department of the titles list; a name or title of more than 48 bytes, a
department of more than 40; more than 30 names, or a name twice; more than 8 departments; an icon
that is not a game icon's name or number; a list longer than the addon takes.
OLYMPUS_COUNCIL_KEY, OLYMPUS_COUNCIL_OUT and OLYMPUS_COUNCIL_JSON give other paths for the key,
the lists and the council (the tests use a throwaway key in a temporary folder).
"""
import datetime, hashlib, json, os, re, secrets, sys, time

KEY = os.environ.get("OLYMPUS_COUNCIL_KEY") or os.path.expanduser("~/.olympus/council-key.json")
OUT = os.environ.get("OLYMPUS_COUNCIL_OUT") or os.path.join("dist", "CouncilList.lua")
COUNCIL = os.environ.get("OLYMPUS_COUNCIL_JSON") or os.path.expanduser("~/.olympus/council.json")
REALM = "ClassicBetaPvP+ClassicBetaPvP2"
PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")
BASE, BITS = 1 << 24, 2048
MAX_NAMES, MAX_NAME, MAX_BLOB = 30, 48, 2000 # what the addon takes (Workshop.TakeCouncil)
MAX_TITLE, MAX_DEPT, MAX_DEPTS, MAX_TITLES_BLOB = 48, 40, 8, 3000 # and of the titles (Workshop.TakeTitles)
MAX_STEWARDS, MAX_REALM, FACTIONS = 3, 40, ("Alliance", "Horde") # the King's Steward (Core.lua: ns.ReadStewards)
MAX_GUILDS, MAX_GUILD_CHARS, MAX_GUILD_BYTES = 20, 24, 72 # the approved guilds (Core.lua: ns.ReadApprovedGuilds)
MAX_PROGRAM_GUILDS, MAX_PROGRAM_LIFETIME = 20, 31 * 86400 # FederationProgram.lua
MAX_ARBITERS = 5 # the arena's signed arbiters per faction (Core.lua: ns.ReadArbiters, 1.2)
MAX_APOSTLES = 12 # the Church's Twelve Apostles per faction (Church.lua: Church.ReadApostles, 1.1.6)
# The launch identities (1.3.4, Core.lua: ns.ReadPins, ns.PINS_MAX, ns.REALM_KINDS, ns.REALM_REGIONS, ns.REALMS_MAX).
MAX_PINS = {"king": 1, "queen": 1, "treasurer": 4, "author": 8, "speedrunner": 1, "quaestor": 2}
REALM_KINDS, REGIONS, MAX_REALMS_EACH = ("pvp", "pve", "rp", "rppvp", "hardcore"), ("NA", "EU"), 40
GROUP = None # --group "<Realm>+<Realm>": the realm group a signing is for (written to the council file's "realm")
MAX_LEADER_GUILDS, MAX_LEADERS_EACH, MAX_LEADERS_TOTAL = 128, 25, 512 # Authority.lua
MAX_LEADERS_EPOCH = 2 ** 31 - 1
LEADERS_DAYS = 14
MAX_AUTH_PARTS, MAX_AUTH_BODY = 8, 5000
SIG_LEN = 512 # hex digits of a signature, always (Sign.Verify)

def is_prime(n, rounds=40):
    if n < 2: return False
    for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n % p == 0: return n == p
    d, r = n - 1, 0
    while d % 2 == 0: d //= 2; r += 1
    for _ in range(rounds):
        a = secrets.randbelow(n - 3) + 2
        x = pow(a, d, n)
        if x in (1, n - 1): continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1: break
        else: return False
    return True

def prime(bits):
    while True:
        p = secrets.randbits(bits) | (1 << (bits - 1)) | 1
        if p % 3 == 2 and is_prime(p): return p

def limbs(n):
    k = 0
    while BASE ** k <= n: k += 1
    return k

def keygen():
    if os.path.exists(KEY): sys.exit("key exists: " + KEY)
    os.makedirs(os.path.dirname(os.path.abspath(KEY)), mode=0o700, exist_ok=True)
    while True:
        p, q = prime(BITS // 2), prime(BITS // 2)
        n = p * q
        if p != q and n.bit_length() == BITS: break
    lam = (p - 1) * (q - 1)
    d = pow(3, -1, lam)
    k = limbs(n)
    mu = BASE ** (2 * k) // n
    with open(os.open(KEY, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as f:
        json.dump({"n": hex(n), "d": hex(d), "mu": hex(mu), "k": k}, f)
    print("N =", format(n, "x")); print("MU =", format(mu, "x")); print("K =", k)

# The key file, rewritten whole or not at all (it holds the private key), readable by its owner only.
def save_key(key):
    tmp = KEY + ".tmp"
    if os.path.exists(tmp): os.unlink(tmp)
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as f:
        json.dump(key, f)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, KEY)

# What the addon keeps of a name or a realm group: anything else would be dropped, cut or
# stripped on the way ("|" and control characters never cross the channel), and the list
# would no longer match its signature, or name someone else.
def plain(s, extra=""):
    return not any(c in "~|" + extra or ord(c) < 32 or ord(c) == 127 for c in s)

def check(names, realm):
    if len(names) > MAX_NAMES: sys.exit("%d names: the addon takes %d" % (len(names), MAX_NAMES))
    seen = set()
    for x in names:
        if not plain(x, ",") or len(x.encode()) > MAX_NAME: sys.exit("not a name the addon takes: %r" % x)
        if x.lower() in seen: sys.exit("named twice: %r" % x)
        seen.add(x.lower())
    if not plain(realm): sys.exit("not a realm group the addon takes: %r" % realm)

# Newer than the last list this key signed, whatever the clock says.
def next_at(key, at=None):
    return max(int(time.time() if at is None else at), int(key.get("last_at", 0)) + 1)

# A signed list must fit what the addon takes, its signature included (always SIG_LEN digits).
def fits(text, limit, what):
    if len(text.encode()) + 1 + SIG_LEN > limit: sys.exit("%s is too long for the addon (%d bytes at most)" % (what, limit))

def signature(text, key):
    n, d = int(key["n"], 16), int(key["d"], 16)
    h = hashlib.sha256(text.encode()).digest()
    em = b"\x00\x01" + b"\xff" * (256 - 3 - len(PREFIX) - len(h)) + b"\x00" + PREFIX + h
    return format(pow(int.from_bytes(em, "big"), d, n), "0%dx" % SIG_LEN)

def sign(names, realm=REALM, at=None):
    with open(KEY) as f: key = json.load(f)
    names = [x.strip() for x in names.split(",") if x.strip()]
    check(names, realm)
    at = next_at(key, at)
    text = "HS1~%d~%s~%s" % (at, realm, ",".join(names))
    fits(text, MAX_BLOB, "the list")
    sig = signature(text, key)
    key["last_at"] = at
    save_key(key)
    return text, sig

def seal(request):
    """Sign only a validated monthly Records request; never replace the council output."""
    request = request.strip()
    m = re.fullmatch(r"RS1~(\d+)~([^~]+)~(Alliance|Horde)~([bd])~(\d+)~(\d+)~([0-9a-f]{64})", request)
    if not m: sys.exit("not a monthly records request")
    at, realm, faction, letter, month, count, digest = m.groups()
    at, month, count = int(at), int(month), int(count)
    check([], realm)
    if count > 5000 or month < 1970 * 12 or month > 9998 * 12:
        sys.exit("records month or row count outside the addon bounds")
    end_year, end_month = divmod(month + 1, 12)
    end = datetime.datetime(end_year, end_month + 1, 1, tzinfo=datetime.timezone.utc).timestamp()
    if at < end + 7 * 86400 or at > int(time.time()) + 86400:
        sys.exit("records month has not closed for seven days, or request is in the future")
    fits(request, 900, "records seal")
    with open(KEY) as f: key = json.load(f)
    return request + "~" + signature(request, key)

# The council file (see the top): every field checked as the addon reads it, before anything is
# signed. Returns the realm group, public, the councillors outside any department and the
# departments, as ([(name, title)], [(department, icon, [(name, title)])]).
def text_field(v, what, limit, required):
    if v is None: v = ""
    if not isinstance(v, str): sys.exit("%s is not text: %r" % (what, v))
    v = v.strip()
    if required and not v: sys.exit("%s is empty" % what)
    # Separators of the titles list: "^" between a department's parts, ";" between departments,
    # "=" and "," inside a department's list of names.
    if not plain(v, "^;=,") or len(v.encode()) > limit: sys.exit("not a %s the addon takes: %r" % (what, v))
    return v

# A game icon as ns.CouncilIconValue takes it: a file number (1 to 2^31 - 1), or a plain name.
def icon_field(v, what):
    if v is None or v == "": return ""
    if isinstance(v, int) and not isinstance(v, bool): v = str(v)
    if isinstance(v, str) and re.fullmatch(r"[0-9]+", v):
        if len(v) <= 10 and 1 <= int(v) < 2 ** 31: return str(int(v))
    elif isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9_]{1,64}", v): return v
    sys.exit("not an icon the addon takes (a game icon's name or file number): %s %r" % (what, v))

def fields(obj, what, allowed):
    if not isinstance(obj, dict): sys.exit("%s is not an object: %r" % (what, obj))
    extra = sorted(set(obj) - set(allowed))
    if extra: sys.exit("%s: unknown field %r (a typo?)" % (what, extra[0]))
    return obj

def people(v, what):
    if v is None: return []
    if not isinstance(v, list): sys.exit("%s is not a list" % what)
    out = []
    for m in v:
        fields(m, what, ("name", "title"))
        out.append((text_field(m.get("name"), "name", MAX_NAME, True), text_field(m.get("title"), "title", MAX_TITLE, False)))
    return out

# A Steward's name as the addon takes it (Core.lua, StewardName): "First Surname-Realm" or
# "First Surname"; the name letters with one space at most (48 bytes), the realm letters and
# digits (40 bytes). Returned trimmed.
def steward_name(v):
    if not isinstance(v, str): sys.exit("a Steward is a name, not %r" % (v,))
    v = v.strip()
    short, dash, realm = v.partition("-")
    words = short.split(" ")
    good = plain(v, "^;=,") and 1 <= len(words) <= 2 and all(w and all(c.isalpha() for c in w) for w in words)
    good = good and len(short.encode()) <= MAX_NAME
    if dash: good = good and realm != "" and all(c.isalnum() for c in realm) and len(realm.encode()) <= MAX_REALM
    if not good: sys.exit("not a Steward's name the addon takes (First Surname-Realm): %r" % v)
    return v

# The council file's "stewards": each a name (the Alliance King's) or {"name", "faction"}.
# Returns {faction: [names]}, each faction MAX_STEWARDS at most, nobody twice, each realm one of
# the list's realm group (a Steward elsewhere would be nobody's on every client).
def read_stewards(v, realm):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("stewards is not a list")
    out, seen = {}, set()
    for s in v:
        if isinstance(s, dict):
            fields(s, "a steward", ("name", "faction"))
            name, faction = s.get("name"), s.get("faction", "Alliance")
        else:
            name, faction = s, "Alliance"
        name = steward_name(name)
        if faction not in FACTIONS: sys.exit("a Steward's faction is Alliance or Horde, not %r" % (faction,))
        home = name.partition("-")[2]
        if home and not in_group(home, realm):
            sys.exit("%r is not of the list's realm group (%s)" % (name, realm))
        if name.lower() in seen: sys.exit("a Steward twice: %r" % name)
        seen.add(name.lower())
        out.setdefault(faction, []).append(name)
        if len(out[faction]) > MAX_STEWARDS: sys.exit("more than %d Stewards for the %s" % (MAX_STEWARDS, faction))
    return out

# An approved guild's name as the addon takes it (Core.lua, ApprovedName): letters and spaces, a
# letter first, 24 characters (72 bytes) at most. Returned trimmed.
def guild_name(v):
    if not isinstance(v, str): sys.exit("an approved guild is a name, not %r" % (v,))
    v = v.strip()
    good = v != "" and plain(v, "^;=,") and v[0].isalpha() and all(c.isalpha() or c == " " for c in v)
    good = good and len(v) <= MAX_GUILD_CHARS and len(v.encode()) <= MAX_GUILD_BYTES
    if not good: sys.exit("not a guild name the addon takes (letters and spaces, 24 at most): %r" % v)
    return v

# The council file's "guilds": each a name (an Alliance guild) or {"name", "faction"}. Returns
# {faction: [names]}, each faction MAX_GUILDS at most, each guild once.
def read_guilds(v):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("guilds is not a list")
    out, seen = {}, set()
    for g in v:
        if isinstance(g, dict):
            fields(g, "a guild", ("name", "faction"))
            name, faction = g.get("name"), g.get("faction", "Alliance")
        else:
            name, faction = g, "Alliance"
        name = guild_name(name)
        if faction not in FACTIONS: sys.exit("a guild's faction is Alliance or Horde, not %r" % (faction,))
        if (faction, name.casefold()) in seen: sys.exit("a guild twice: %r" % name)
        seen.add((faction, name.casefold()))
        out.setdefault(faction, []).append(name)
        if len(out[faction]) > MAX_GUILDS: sys.exit("more than %d approved guilds for the %s" % (MAX_GUILDS, faction))
    return out

# The council file's "arbiters" (1.2): each a name (an Alliance arbiter) or {"name", "faction",
# "audit"}. Returns {faction: ["Name-Realm" or "Name-Realm+a"]}, each faction MAX_ARBITERS at most,
# nobody twice, each realm one of the list's realm group.
def read_arbiters(v, realm):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("arbiters is not a list")
    out, seen = {}, set()
    for a in v:
        if isinstance(a, dict):
            fields(a, "an arbiter", ("name", "faction", "audit"))
            name, faction, audit = a.get("name"), a.get("faction", "Alliance"), a.get("audit", False)
        else:
            name, faction, audit = a, "Alliance", False
        if not isinstance(name, str): sys.exit("an arbiter is a name, not %r" % (name,))
        name = steward_name(name)
        if faction not in FACTIONS: sys.exit("an arbiter's faction is Alliance or Horde, not %r" % (faction,))
        if not isinstance(audit, bool): sys.exit("audit is true or false, not %r" % (audit,))
        home = name.partition("-")[2]
        if home and not in_group(home, realm):
            sys.exit("%r is not of the list's realm group (%s)" % (name, realm))
        if name.lower() in seen: sys.exit("an arbiter twice: %r" % name)
        seen.add(name.lower())
        out.setdefault(faction, []).append(name + ("+a" if audit else ""))
        if len(out[faction]) > MAX_ARBITERS: sys.exit("more than %d arbiters for the %s" % (MAX_ARBITERS, faction))
    return out

# The council file's "apostles" (1.1.6): each a name (an Alliance Apostle) or {"name", "faction",
# "head"}. Returns {faction: ["Name-Realm"]}; legacy head flags are refused, not a nomination.
# Each faction MAX_APOSTLES at most, nobody twice, each realm one of the list's realm
# group. A name of the Church's (Church.lua's WireName): 30 bytes at most.
def read_apostles(v, realm):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("apostles is not a list")
    out, seen = {}, set()
    for a in v:
        head = False
        if isinstance(a, dict):
            fields(a, "an apostle", ("name", "faction", "head"))
            name, faction, head = a.get("name"), a.get("faction", "Alliance"), a.get("head", False)
            if not isinstance(head, bool): sys.exit("an apostle's head is true or false, not %r" % (head,))
        else:
            name, faction = a, "Alliance"
        if not isinstance(name, str): sys.exit("an apostle is a name, not %r" % (name,))
        name = steward_name(name)
        if len(name.partition("-")[0].encode()) > 30: sys.exit("an apostle's name is 30 bytes at most: %r" % name)
        if faction not in FACTIONS: sys.exit("an apostle's faction is Alliance or Horde, not %r" % (faction,))
        home = name.partition("-")[2]
        if home and not in_group(home, realm):
            sys.exit("%r is not of the list's realm group (%s)" % (name, realm))
        if name.partition("-")[0].lower() in seen: sys.exit("an apostle twice: %r" % name)
        seen.add(name.partition("-")[0].lower())
        if head: sys.exit("Asmongold is Head of the Church; remove legacy head flags before signing")
        out.setdefault(faction, []).append(name)
        if len(out[faction]) > MAX_APOSTLES: sys.exit("more than %d apostles for the %s" % (MAX_APOSTLES, faction))
    return out

# The dormant signed leadership migration. Absence means legacy census behaviour; only the
# explicit mode "enforce" activates the one-way client boundary. Its first character is the guild
# master (rank 0), followed by officers (rank 1). Every identity has an exact realm; nobody may
# occur twice in a faction, including under another guild. issued/expires use the wall clock, not
# HT1's monotonic ordering time (last_at can intentionally be ahead after a clock correction).
def read_leadership(v, realm):
    if v is None: return None, None, {}, None, None
    fields(v, "leadership", ("mode", "epoch", "factions", "guilds"))
    if v.get("mode") != "enforce": sys.exit("leadership mode is 'enforce'")
    epoch = v.get("epoch")
    if isinstance(epoch, bool) or not isinstance(epoch, int) or not 1 <= epoch <= MAX_LEADERS_EPOCH:
        sys.exit("leadership epoch is an integer from 1 to %d" % MAX_LEADERS_EPOCH)
    factions = v.get("factions")
    if not isinstance(factions, list) or not factions: sys.exit("leadership factions is a non-empty list")
    if any(f not in FACTIONS for f in factions): sys.exit("leadership factions contain only Alliance or Horde")
    if len(set(factions)) != len(factions): sys.exit("a leadership faction is named twice")
    listed = v.get("guilds")
    if not isinstance(listed, list): sys.exit("leadership guilds is not a list")
    realms = set(realm.split("+")) if realm else set()
    if not realms: sys.exit("signed leadership requires a realm group")
    out, guild_seen, people_seen, total = {}, set(), set(), 0
    for e in listed:
        fields(e, "a guild's leaders", ("guild", "leader", "officers", "faction"))
        guild = guild_name(e.get("guild"))
        faction = e.get("faction", "Alliance")
        if faction not in FACTIONS: sys.exit("a guild's leaders faction is Alliance or Horde, not %r" % (faction,))
        if faction not in factions: sys.exit("%r has leadership but its faction is not enforced" % guild)
        gkey = (faction, guild.casefold())
        if gkey in guild_seen: sys.exit("a guild's leaders twice: %r" % guild)
        guild_seen.add(gkey)
        officers = e.get("officers") or []
        if not isinstance(officers, list): sys.exit("officers of %r is not a list" % guild)
        if len(officers) + 1 > MAX_LEADERS_EACH: sys.exit("more than %d signed leaders of %r" % (MAX_LEADERS_EACH, guild))
        raw = [e.get("leader")] + officers
        names = []
        for value in raw:
            name = steward_name(value)
            home = name.partition("-")[2]
            if not home: sys.exit("a signed leader needs an exact realm: %r" % name)
            if not in_group(home, realm): sys.exit("%r is not of the list's realm group (%s)" % (name, realm))
            pkey = (faction, name.casefold())
            if pkey in people_seen: sys.exit("a signed leader twice: %r" % name)
            people_seen.add(pkey)
            names.append(name)
            total += 1
            if total > MAX_LEADERS_TOTAL: sys.exit("more than %d signed leaders" % MAX_LEADERS_TOTAL)
        out.setdefault(faction, []).append((guild, names))
        if len(out[faction]) > MAX_LEADER_GUILDS: sys.exit("more than %d guild leadership entries for the %s" % (MAX_LEADER_GUILDS, faction))
    issued = int(time.time())
    return epoch, factions, out, issued, issued + LEADERS_DAYS * 86400

# A realm as a name carries it ("Name-Realm": no space, no dash), 40 bytes at most (Core.lua: ns.ReadPins).
def realm_ok(r):
    return r != "" and plain(r, "^;=,+") and all(c.isalnum() or c == "'" for c in r) and len(r.encode()) <= MAX_REALM

# A launch identity's name (1.3.4) as the addon takes it: "First Surname-Realm", its realm required
# (a name without one would count on every realm of the list's group), that realm of the list's
# group when it names one.
def pin_name(v, what, realm):
    if not isinstance(v, str): sys.exit("%s is a name, not %r" % (what, v))
    v = v.strip()
    short, dash, home = v.partition("-")
    words = short.split(" ")
    good = plain(v, "^;=,") and 1 <= len(words) <= 2 and all(w and all(c.isalpha() for c in w) for w in words)
    good = good and len(short.encode()) <= MAX_NAME and bool(dash) and realm_ok(home)
    if not good: sys.exit("not a name the addon takes for %s (First Surname-Realm, with its realm): %r" % (what, v))
    if not in_group(home, realm):
        sys.exit("%r (%s) is not of the list's realm group (%s)" % (v, what, realm))
    return v

def faction_of(f, what):
    if f not in FACTIONS: sys.exit("%s's faction is Alliance or Horde, not %r" % (what, f))
    return f

# The council file's "king" (1.3.4): {"Alliance": "First Surname-Realm", "Horde": ...}, each side's
# King on the list's realm group. Returns {faction: name}.
def read_king(v, realm):
    if v is None: return {}
    if not isinstance(v, dict): sys.exit('king is {"Alliance": "First Surname-Realm", "Horde": "..."}, not %r' % (v,))
    return {faction_of(f, "a King"): pin_name(n, "the %s King" % f, realm) for f, n in v.items()}

# The council file's "queen": the signed presentation identity for each side. It is
# deliberately parsed separately from every authority-bearing role.
def read_queen(v, realm):
    if v is None: return {}
    if not isinstance(v, dict): sys.exit('queen is {"Alliance": "First Surname-Realm", "Horde": "..."}, not %r' % (v,))
    return {faction_of(f, "a Queen"): pin_name(n, "the %s Queen" % f, realm) for f, n in v.items()}

# The council file's "speedrunner" (1.5.5): the Olympus Speedrunner of each side, who holds the level race's
# gold comet and its title whatever the race does (Core.lua: ns.IsSpeedrunnerName). A title and a frame alone:
# no authority of any kind. Clients before 1.5.5 leave the entry out unread.
def read_speedrunner(v, realm):
    if v is None: return {}
    if not isinstance(v, dict): sys.exit('speedrunner is {"Alliance": "First Surname-Realm", "Horde": "..."}, not %r' % (v,))
    return {faction_of(f, "a Speedrunner"): pin_name(n, "the %s Speedrunner" % f, realm) for f, n in v.items()}

# The council file's "quaestor" (1.5.5): {"Alliance": ["First Surname-Realm", ...]}, each side's Quaestors (the
# Treasurer's executors: the Treasurer's blue dragon, their title and a trusted relay of their side, none of his
# powers; Core.lua: ns.IsQuaestorName), MAX_PINS["quaestor"] a side, nobody twice. Clients before 1.5.5 leave the
# entry out unread.
def read_quaestor(v, realm):
    if v is None: return {}
    if not isinstance(v, dict): sys.exit('quaestor is {"Alliance": ["First Surname-Realm"], "Horde": [...]}, not %r' % (v,))
    out = {}
    for f, names in v.items():
        faction_of(f, "a Quaestor")
        if isinstance(names, str): names = [names]
        if not isinstance(names, list) or not names: sys.exit("the %s Quaestors are a list of names" % f)
        if len(names) > MAX_PINS["quaestor"]: sys.exit("more than %d Quaestors for the %s" % (MAX_PINS["quaestor"], f))
        clean, seen = [], set()
        for n in names:
            n = pin_name(n, "a %s Quaestor" % f, realm)
            if n.lower() in seen: sys.exit("a Quaestor twice: %r" % n)
            seen.add(n.lower())
            clean.append(n)
        out[f] = clean
    return out

# The council file's "treasurer" (1.3.4): {"Alliance": ["Treasurer-Realm", "Mail Character-Realm", ...]}:
# the Treasurer first, then his mail characters, MAX_PINS["treasurer"] in all, nobody twice.
def read_treasurer(v, realm):
    if v is None: return {}
    if not isinstance(v, dict): sys.exit('treasurer is {"Alliance": ["Treasurer-Realm", "Mail-Realm"]}, not %r' % (v,))
    out = {}
    for f, names in v.items():
        faction_of(f, "a Treasurer")
        if isinstance(names, str): names = [names]
        if not isinstance(names, list) or not names: sys.exit("the %s Treasurer is a list of names, the Treasurer first" % f)
        if len(names) > MAX_PINS["treasurer"]: sys.exit("more than %d Treasurer's characters for the %s" % (MAX_PINS["treasurer"], f))
        clean, seen = [], set()
        for n in names:
            n = pin_name(n, "the %s Treasurer" % f, realm)
            if n.lower() in seen: sys.exit("a Treasurer's character twice: %r" % n)
            seen.add(n.lower())
            clean.append(n)
        out[f] = clean
    return out

# The council file's "author" (1.3.4): the author's own characters, each a name (Alliance) or
# {"name", "faction"}; MAX_PINS["author"] a faction, nobody twice. The dev's privileges alone.
def read_author(v, realm):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("author is a list of names")
    out, seen = {}, set()
    for a in v:
        if isinstance(a, dict):
            fields(a, "an author's character", ("name", "faction"))
            name, faction = a.get("name"), a.get("faction", "Alliance")
        else:
            name, faction = a, "Alliance"
        name = pin_name(name, "the author", realm)
        faction_of(faction, "an author's character")
        if name.lower() in seen: sys.exit("an author's character twice: %r" % name)
        seen.add(name.lower())
        out.setdefault(faction, []).append(name)
        if len(out[faction]) > MAX_PINS["author"]: sys.exit("more than %d author's characters for the %s" % (MAX_PINS["author"], faction))
    return out

# The council file's "realms" (1.3.4): [{"name": "Realm", "kind": "pvp", "region": "NA"}], what each
# realm is (ns.RealmInfo). Returns {region: [(realm, kind)]}, MAX_REALMS_EACH a region, each realm once.
def read_realms(v):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("realms is a list")
    out, seen = {}, set()
    for r in v:
        fields(r, "a realm", ("name", "kind", "region"))
        name = r.get("name")
        name = name.strip() if isinstance(name, str) else name
        if not isinstance(name, str) or not realm_ok(name): sys.exit("not a realm the addon takes (as in Name-Realm, 40 bytes at most): %r" % (name,))
        if r.get("kind") not in REALM_KINDS: sys.exit("a realm's kind is one of %s, not %r" % (", ".join(REALM_KINDS), r.get("kind")))
        if r.get("region") not in REGIONS: sys.exit("a realm's region is NA or EU, not %r" % (r.get("region"),))
        if name.lower() in seen: sys.exit("a realm twice: %r" % name)
        seen.add(name.lower())
        out.setdefault(r["region"], []).append((name, r["kind"]))
        if len(out[r["region"]]) > MAX_REALMS_EACH: sys.exit("more than %d realms in %s" % (MAX_REALMS_EACH, r["region"]))
    return out

# (1.4.6) A realm belongs to the list's group when the group names it, or when the group is a
# WoW: Forever family ("ForeverPvE", "ForeverPvP": every CAMWOW sub-realm of that ruleset).
def forever_family(realm):
    m = re.match(r"^CAMWOW[A-Z]{2}\d+Realm\d+([A-Za-z]+)$", realm or "")
    return "Forever" + m.group(1) if m else None
def in_group(home, realm):
    return (not realm) or home in realm.split("+") or forever_family(home) == realm

# Moving the list to another realm group (--group): every name that carries a realm of another
# group, listed at once (each would be refused one by one below), with what takes it off.
def group_conflicts(data, realm):
    if not realm: return
    realms, bad = set(realm.split("+")), []
    def family(r):
        m = re.match(r"^CAMWOW[A-Z]{2}\d+Realm\d+([A-Za-z]+)$", r or "")
        return "Forever" + m.group(1) if m else None
    def look(name, how):
        if isinstance(name, dict): name = name.get("name")
        if isinstance(name, str):
            home = name.strip().partition("-")[2]
            if home and not in_group(home, realm): bad.append("%s (%s)" % (name.strip(), how))
    def items(v): return v if isinstance(v, list) else []
    for what in ("steward", "arbiter", "apostle", "author"):
        for n in items(data.get(what + ("s" if what != "author" else ""))): look(n, "%s --remove" % what)
    for f, n in (data.get("king") if isinstance(data.get("king"), dict) else {}).items(): look(n, "king --remove %s" % f)
    for f, n in (data.get("queen") if isinstance(data.get("queen"), dict) else {}).items(): look(n, "queen --remove %s" % f)
    for f, n in (data.get("speedrunner") if isinstance(data.get("speedrunner"), dict) else {}).items(): look(n, "speedrunner --remove %s" % f)
    for f, ns_ in (data.get("quaestor") if isinstance(data.get("quaestor"), dict) else {}).items():
        for n in (ns_ if isinstance(ns_, list) else [ns_]):
            look(n, "quaestor --remove \"%s\"" % (n.strip() if isinstance(n, str) else n))
    for f, ns_ in (data.get("treasurer") if isinstance(data.get("treasurer"), dict) else {}).items():
        for n in (ns_ if isinstance(ns_, list) else [ns_]): look(n, "treasurer --remove %s" % f)
    lead = data.get("leadership")
    for g in items(lead.get("guilds") if isinstance(lead, dict) else None):
        if isinstance(g, dict):
            for n in [g.get("leader")] + items(g.get("officers")): look(n, "the leadership entry of %s" % g.get("guild"))
    if bad:
        sys.exit(("of another realm group than the list's (%s): no client there would take them. Nothing was signed.\n"
            "Take each off (the command in brackets), or sign for its group with --group:\n  %s") % (realm, "\n  ".join(bad)))

def read_council(data):
    fields(data, "the council", ("realm", "public", "departments", "members", "stewards", "guilds", "arbiters", "apostles", "leadership",
        "king", "queen", "treasurer", "author", "realms", "speedrunner", "quaestor", "program", "contributions"))
    realm = data.get("realm", REALM)
    if not isinstance(realm, str): sys.exit("not a realm group the addon takes: %r" % (realm,))
    group_conflicts(data, realm)
    public = data.get("public", False)
    if not isinstance(public, bool): sys.exit("public is true or false, not %r" % (public,))
    loose = people(data.get("members"), "members")
    listed = data.get("departments") or []
    if not isinstance(listed, list): sys.exit("departments is not a list")
    if len(listed) > MAX_DEPTS: sys.exit("%d departments: the addon takes %d" % (len(listed), MAX_DEPTS))
    depts, seen = [], set()
    for d in listed:
        fields(d, "a department", ("name", "icon", "members"))
        name = text_field(d.get("name"), "department", MAX_DEPT, True)
        if name.lower() in seen: sys.exit("a department twice: %r" % name)
        seen.add(name.lower())
        depts.append((name, icon_field(d.get("icon"), name), people(d.get("members"), name)))
    leaders_epoch, leaders_factions, leaders, issued, expires = read_leadership(data.get("leadership"), realm)
    pins = {"king": read_king(data.get("king"), realm), "queen": read_queen(data.get("queen"), realm),
        "treasurer": read_treasurer(data.get("treasurer"), realm),
        "author": read_author(data.get("author"), realm), "realms": read_realms(data.get("realms")),
        "speedrunner": read_speedrunner(data.get("speedrunner"), realm), "quaestor": read_quaestor(data.get("quaestor"), realm)}
    return (realm, public, loose, depts, read_stewards(data.get("stewards"), realm), read_guilds(data.get("guilds")),
        read_arbiters(data.get("arbiters"), realm), leaders_epoch, leaders_factions, leaders, issued, expires,
        read_apostles(data.get("apostles"), realm), pins)

def load_council(path):
    try:
        with open(path, encoding="utf-8") as f: data = json.load(f)
    except (OSError, ValueError) as e: sys.exit("cannot read the council file %s: %s" % (path, e))
    return data

# The signer's attestation that the named native owner is an approved caretaker, the
# other named character is the official GM, and the Council's manual checks are done.
def program_entries(v, realm):
    if v is None: return []
    if not isinstance(v, list): sys.exit("program is a list of faction and region policies")
    entries, scopes = [], set()
    for policy in v:
        fields(policy, "a guild program policy", ("faction", "region", "mode", "issued", "expires", "guilds"))
        faction = faction_of(policy.get("faction"), "a guild program policy")
        region = policy.get("region")
        if not realm or not isinstance(region, str) or not re.fullmatch(r"[A-Z]{2}" if realm.startswith("Forever") else "-", region):
            sys.exit("program needs an explicit realm group and its region (two uppercase letters on Forever, '-' elsewhere)")
        if (faction, region) in scopes: sys.exit("a guild program scope twice")
        scopes.add((faction, region))
        mode = policy.get("mode")
        issued, expires = policy.get("issued"), policy.get("expires")
        if mode not in ("enforce", "off"): sys.exit("program mode is enforce or off")
        if type(issued) is not int or type(expires) is not int or issued < 1577836800 or not 0 < expires - issued <= MAX_PROGRAM_LIFETIME:
            sys.exit("program needs valid issued and expires Unix times no more than 31 days apart")
        guilds = policy.get("guilds")
        if not isinstance(guilds, list) or len(guilds) > MAX_PROGRAM_GUILDS or (mode == "off" and guilds):
            sys.exit("program needs a bounded guild list (empty in off mode)")
        rows, names, people_set = [], set(), set()
        for row in guilds:
            fields(row, "a guild program enrollment", ("guild", "caretaker", "official", "officialRankIndex", "primary"))
            guild = guild_name(row.get("guild"))
            if guild.casefold() in names: sys.exit("a guild program guild twice")
            names.add(guild.casefold())
            caretaker = pin_name(row.get("caretaker"), "program caretaker", realm)
            official = pin_name(row.get("official"), "program official GM", realm)
            for name in (caretaker, official):
                home = name.partition("-")[2]
                if region != "-" and not home.startswith("CAMWOW" + region):
                    sys.exit("a guild program identity is outside the policy's region")
                if name.casefold() in people_set: sys.exit("a guild program identity twice")
                people_set.add(name.casefold())
            rank = row.get("officialRankIndex", 1)
            if type(rank) is not int or rank != 1: sys.exit("program officialRankIndex must be native index 1 (the second slot)")
            primary = row.get("primary", False)
            if type(primary) is not bool: sys.exit("program primary must be true or false")
            rows.append("%s=%s,%s,1%s" % (guild, caretaker, official, "p" if primary else ""))
        entries.append("^program^%s^%s^%s^%d^%d^%s" % (faction, region, mode, issued, expires, "!".join(sorted(rows)) or "-"))
    return sorted(entries)

# A separate decision switches the enrolled guilds to voluntary contributions.
def contribution_entries(v, realm):
    if v is None: return []
    if not isinstance(v, list): sys.exit("contributions is a list of faction and region policies")
    entries, scopes = [], set()
    for policy in v:
        fields(policy, "a contributions policy", ("faction", "region", "mode", "issued", "expires"))
        faction = faction_of(policy.get("faction"), "a contributions policy")
        region = policy.get("region")
        if not realm or not realm.startswith("Forever") or not isinstance(region, str) or not re.fullmatch(r"[A-Z]{2}", region):
            sys.exit("contributions needs an explicit Forever realm group and region")
        if (faction, region) in scopes: sys.exit("a contributions scope twice")
        scopes.add((faction, region))
        mode = policy.get("mode")
        issued, expires = policy.get("issued"), policy.get("expires")
        if mode not in ("enforce", "off"): sys.exit("contributions mode is enforce or off")
        if type(issued) is not int or type(expires) is not int or issued < 1577836800 or not 0 < expires - issued <= MAX_PROGRAM_LIFETIME:
            sys.exit("contributions needs valid issued and expires Unix times no more than 31 days apart")
        entries.append("^contributions^%s^%s^%s^%d^%d^-" % (faction, region, mode, issued, expires))
    return sorted(entries)

# Both lists from the council file: the names (HS1) and, one second newer, the titles (HT1).
def sign_council(path):
    return sign_council_data(load_council(path))

def sign_authority(at, realm, epoch, factions, leaders, issued, expires, key):
    """Return independently signed HA1 parts, split only between complete guild entries."""
    out = []
    for faction in factions or []:
        entries = ["%s=%s" % (guild, ",".join(names)) for guild, names in leaders.get(faction, [])]
        full = "!".join(entries) or "-"
        root = hashlib.sha256(full.encode()).hexdigest()
        bodies = []
        if full == "-":
            bodies = [full]
        else:
            current = []
            for entry in entries:
                candidate = "!".join(current + [entry])
                if len(candidate.encode()) > MAX_AUTH_BODY:
                    if not current: sys.exit("one leadership guild entry exceeds %d bytes" % MAX_AUTH_BODY)
                    bodies.append("!".join(current)); current = [entry]
                else:
                    current.append(entry)
            if current: bodies.append("!".join(current))
        if len(bodies) > MAX_AUTH_PARTS:
            sys.exit("leadership needs %d signed parts; the addon takes %d" % (len(bodies), MAX_AUTH_PARTS))
        for index, body in enumerate(bodies, 1):
            text = "HA1~%d~%s~%s~enforce~%d~%d~%d~%s~%d~%d~%s" % (
                at, realm, faction, epoch, issued, expires, root, index, len(bodies), body)
            # H2~ plus chunk headers must stay under Codec's 30 * 220 logical payload bound.
            if len(text.encode()) + 1 + SIG_LEN > 6200:
                sys.exit("a signed authority part exceeds 6200 bytes")
            out.append(text + "~" + signature(text, key))
    return out

def sign_council_data(data):
    if GROUP is not None: data["realm"] = GROUP # (--group: saved with the council file by its caller)
    realm, public, loose, depts, stewards, guilds, arbiters, leaders_epoch, leaders_factions, leaders, leaders_issued, leaders_expires, apostles, pins = read_council(data)
    names = [m[0] for m in loose] + [m[0] for d in depts for m in d[2]]
    check(names, realm)
    program = program_entries(data.get("program"), realm)
    with open(KEY) as f: key = json.load(f)
    at = next_at(key)
    names_text = "HS1~%d~%s~%s" % (at, realm, ",".join(names))
    entries = ["^^" + ",".join("%s=%s" % m for m in loose)] if loose else []
    entries += ["%s^%s^%s" % (name, icon, ",".join("%s=%s" % m for m in members)) for name, icon, members in depts]
    # The King's Stewards after the departments: an entry per faction with three "^".
    entries += ["^steward^%s^%s" % (faction, ",".join(stewards[faction])) for faction in FACTIONS if stewards.get(faction)]
    # The approved guilds (1.1) after them, the same way.
    entries += ["^guilds^%s^%s" % (faction, ",".join(guilds[faction])) for faction in FACTIONS if guilds.get(faction)]
    # The arena's signed arbiters (1.2) after them, the same way.
    entries += ["^arbiter^%s^%s" % (faction, ",".join(arbiters[faction])) for faction in FACTIONS if arbiters.get(faction)]
    # The Church's Twelve Apostles (1.1.6) after them, the same way.
    entries += ["^apostles^%s^%s" % (faction, ",".join(apostles[faction])) for faction in FACTIONS if apostles.get(faction)]
    # The launch identities after them, the same way: the King, the Queen (presentation only), the Treasurer and the author of
    # each side, then what each realm is, per region.
    entries += ["^king^%s^%s" % (faction, pins["king"][faction]) for faction in FACTIONS if pins["king"].get(faction)]
    entries += ["^queen^%s^%s" % (faction, pins["queen"][faction]) for faction in FACTIONS if pins["queen"].get(faction)]
    entries += ["^treasurer^%s^%s" % (faction, ",".join(pins["treasurer"][faction])) for faction in FACTIONS if pins["treasurer"].get(faction)]
    entries += ["^author^%s^%s" % (faction, ",".join(pins["author"][faction])) for faction in FACTIONS if pins["author"].get(faction)]
    # (1.5.5) The Olympus Speedrunner of each side, after the author's characters.
    entries += ["^speedrunner^%s^%s" % (faction, pins["speedrunner"][faction]) for faction in FACTIONS if pins.get("speedrunner", {}).get(faction)]
    # (1.5.5) The Quaestors of each side, after the Speedrunner.
    entries += ["^quaestor^%s^%s" % (faction, ",".join(pins["quaestor"][faction])) for faction in FACTIONS if pins.get("quaestor", {}).get(faction)]
    entries += ["^realms^%s^%s" % (region, ",".join("%s=%s" % r for r in pins["realms"][region])) for region in REGIONS if pins["realms"].get(region)]
    entries += program
    entries += contribution_entries(data.get("contributions"), realm)
    titles_text = "HT1~%d~%s~%d~%s" % (at + 1, realm, 1 if public else 0, ";".join(entries))
    fits(names_text, MAX_BLOB, "the name list")
    fits(titles_text, MAX_TITLES_BLOB, "the titles list")
    authority = sign_authority(at + 2, realm, leaders_epoch, leaders_factions, leaders, leaders_issued, leaders_expires, key) if leaders_factions else []
    signed = names_text + "~" + signature(names_text, key), titles_text + "~" + signature(titles_text, key), authority
    key["last_at"] = at + (2 if authority else 1)
    save_key(key)
    return signed

# A Lua string literal of s, byte for byte: Lua 5.1 has no \u escapes (an accented name
# written as JSON's "\u00e0" would reach the game as "u00e0", and its signature fail).
def lua_string(s):
    return '"' + "".join(chr(b) if 32 <= b < 127 and chr(b) not in '"\\' else "\\%03d" % b for b in s.encode()) + '"'

# (1.4.5) One file, several realm groups: beside the lists just signed (ns.COUNCIL_SIGNED and
# ns.COUNCIL_TITLES, as ever), the file carries every group's last lists (ns.COUNCIL_BY_GROUP, the
# group of each HS1 blob as its key), kept in a sidecar next to the file (<OUT>.groups.json), so the
# dev's client takes the lists of the group it is on (Workshop.CouncilLogin): his PvP character beside
# his PvE one. Signing a group replaces that group's entry alone.
def write_out(names, titles=None, authority=None):
    if os.path.dirname(OUT): os.makedirs(os.path.dirname(OUT), exist_ok=True)
    side = OUT + ".groups.json"
    groups = {}
    if os.path.exists(side):
        try: groups = json.load(open(side))
        except Exception: groups = {}
        if not isinstance(groups, dict): groups = {}
    group = names.split("~")[2] if names.count("~") >= 2 else ""
    if group: groups[group] = {"names": names, "titles": titles or None}
    with open(side, "w") as f: json.dump(groups, f, indent=1)
    with open(OUT, "w") as f:
        f.write("-- Local only: the High Council's lists, signed. Never commit or publish this file.\n")
        f.write("local _, ns = ...\nns.COUNCIL_SIGNED = %s\n" % lua_string(names))
        if titles: f.write("ns.COUNCIL_TITLES = %s\n" % lua_string(titles))
        if authority:
            f.write("ns.COUNCIL_AUTHORITY = {\n")
            for blob in authority: f.write(" %s,\n" % lua_string(blob))
            f.write("}\n")
        if len(groups) > 1:
            f.write("ns.COUNCIL_BY_GROUP = {\n")
            for g in sorted(groups):
                e = groups[g]
                f.write(" [%s] = { %s, %s },\n" % (lua_string(g), lua_string(e["names"]), lua_string(e["titles"]) if e.get("titles") else "nil"))
            f.write("}\n")

# The council file rewritten whole or not at all, readable by its owner as before.
def save_council(path, data):
    tmp = path + ".tmp"
    if os.path.exists(tmp): os.unlink(tmp)
    mode = os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o600
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)

# steward <Name-Realm> [faction] | steward --remove <Name-Realm>: the council file's "stewards"
# changed, the council signed from it at once (nothing written if anything is refused).
def steward(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = steward_name(args[0]), args[1] if len(args) == 2 else "Alliance"
    if faction not in FACTIONS: sys.exit("a Steward's faction is Alliance or Horde, not %r" % faction)
    data = load_council(path)
    listed = data.get("stewards") or []
    if not isinstance(listed, list): sys.exit("stewards is not a list")
    def who(s): return (s.get("name") if isinstance(s, dict) else s) or ""
    kept = [s for s in listed if not (isinstance(who(s), str) and who(s).strip().lower() == name.lower())]
    if remove and len(kept) == len(listed): sys.exit("not a Steward in %s: %r" % (path, name))
    if not remove:
        if len(kept) != len(listed): sys.exit("already a Steward: %r" % name)
        kept.append(name if faction == "Alliance" else {"name": name, "faction": faction})
    data["stewards"] = kept
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# guild <Guild Name> [faction] | guild --remove <Guild Name>: the council file's "guilds" changed,
# the council signed from it at once (nothing written if anything is refused).
def guild(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = guild_name(args[0]), args[1] if len(args) == 2 else "Alliance"
    if faction not in FACTIONS: sys.exit("a guild's faction is Alliance or Horde, not %r" % faction)
    data = load_council(path)
    listed = data.get("guilds") or []
    if not isinstance(listed, list): sys.exit("guilds is not a list")
    def who(g): return (g.get("name") if isinstance(g, dict) else g) or ""
    def side(g): return (g.get("faction", "Alliance") if isinstance(g, dict) else "Alliance")
    same = lambda g: isinstance(who(g), str) and who(g).strip().casefold() == name.casefold() and (remove or side(g) == faction)
    kept = [g for g in listed if not same(g)]
    if remove and len(kept) == len(listed): sys.exit("not an approved guild in %s: %r" % (path, name))
    if not remove:
        if len(kept) != len(listed): sys.exit("already approved: %r" % name)
        kept.append(name if faction == "Alliance" else {"name": name, "faction": faction})
    data["guilds"] = kept
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# arbiter [--audit] <Name-Realm> [faction] | arbiter --remove <Name-Realm>: the council file's
# "arbiters" changed (1.2), the council signed from it at once (nothing written if refused).
def arbiter(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    audit = not remove and bool(args) and args[0] == "--audit"
    if audit: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = steward_name(args[0]), args[1] if len(args) == 2 else "Alliance"
    if faction not in FACTIONS: sys.exit("an arbiter's faction is Alliance or Horde, not %r" % faction)
    data = load_council(path)
    listed = data.get("arbiters") or []
    if not isinstance(listed, list): sys.exit("arbiters is not a list")
    def who(a): return (a.get("name") if isinstance(a, dict) else a) or ""
    kept = [a for a in listed if not (isinstance(who(a), str) and who(a).strip().lower() == name.lower())]
    if remove and len(kept) == len(listed): sys.exit("not an arbiter in %s: %r" % (path, name))
    if not remove:
        if len(kept) != len(listed): sys.exit("already an arbiter: %r" % name)
        if faction == "Alliance" and not audit: kept.append(name)
        else:
            entry = {"name": name}
            if faction != "Alliance": entry["faction"] = faction
            if audit: entry["audit"] = True
            kept.append(entry)
    data["arbiters"] = kept
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# apostle <Name-Realm> [faction] | apostle --remove <Name-Realm>:
# the council file's "apostles" changed (1.1.6), the council signed from it at once (nothing written
# if anything is refused). The Head is canonical and cannot be nominated.
def apostle(args, path=COUNCIL):
    if args and args[0] == "--head": sys.exit("Asmongold is Head of the Church; this position cannot be nominated")
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = steward_name(args[0]), args[1] if len(args) == 2 else "Alliance"
    if faction not in FACTIONS: sys.exit("an apostle's faction is Alliance or Horde, not %r" % faction)
    data = load_council(path)
    listed = data.get("apostles") or []
    if not isinstance(listed, list): sys.exit("apostles is not a list")
    def who(a): return (a.get("name") if isinstance(a, dict) else a) or ""
    short = name.partition("-")[0].lower()
    kept = [a for a in listed if not (isinstance(who(a), str) and who(a).strip().partition("-")[0].lower() == short)]
    if remove and len(kept) == len(listed): sys.exit("not an apostle in %s: %r" % (path, name))
    entry = name if faction == "Alliance" else {"name": name, "faction": faction}
    if not remove:
        if len(kept) != len(listed): sys.exit("already an apostle: %r" % name)
        kept.append(entry)
    data["apostles"] = kept
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# Signed from the council file as changed, written out, and the file saved: nothing is written
# when anything is refused (sign_council_data exits first).
def finish(data, path):
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# king <Name-Realm> [faction] | king --remove [faction] (1.3.4): that side's King on the list's group.
def king(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if (remove and len(args) > 1) or (not remove and len(args) not in (1, 2)): sys.exit(__doc__)
    faction = faction_of((args[0] if args else "Alliance") if remove else (args[1] if len(args) == 2 else "Alliance"), "a King")
    data = load_council(path)
    kings = data.get("king") or {}
    if not isinstance(kings, dict): sys.exit("king is not an object in %s" % path)
    if remove:
        if faction not in kings: sys.exit("no %s King in %s" % (faction, path))
        del kings[faction]
    else:
        kings[faction] = pin_name(args[0], "the %s King" % faction, None)
    if kings: data["king"] = kings
    else: data.pop("king", None)
    return finish(data, path)

# queen <Name-Realm> [faction] | queen --remove [faction]: that side's signed
# presentation identity. Nothing in the addon treats this field as authority.
def queen(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if (remove and len(args) > 1) or (not remove and len(args) not in (1, 2)): sys.exit(__doc__)
    faction = faction_of((args[0] if args else "Alliance") if remove else (args[1] if len(args) == 2 else "Alliance"), "a Queen")
    data = load_council(path)
    queens = data.get("queen") or {}
    if not isinstance(queens, dict): sys.exit("queen is not an object in %s" % path)
    if remove:
        if faction not in queens: sys.exit("no %s Queen in %s" % (faction, path))
        del queens[faction]
    else:
        queens[faction] = pin_name(args[0], "the %s Queen" % faction, None)
    if queens: data["queen"] = queens
    else: data.pop("queen", None)
    return finish(data, path)

# speedrunner <Name-Realm> [faction] | speedrunner --remove [faction] (1.5.5): that side's Olympus Speedrunner,
# the level race's gold comet and its title. No authority of any kind.
def speedrunner(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if (remove and len(args) > 1) or (not remove and len(args) not in (1, 2)): sys.exit(__doc__)
    faction = faction_of((args[0] if args else "Alliance") if remove else (args[1] if len(args) == 2 else "Alliance"), "a Speedrunner")
    data = load_council(path)
    named = data.get("speedrunner") or {}
    if not isinstance(named, dict): sys.exit("speedrunner is not an object in %s" % path)
    if remove:
        if faction not in named: sys.exit("no %s Speedrunner in %s" % (faction, path))
        del named[faction]
    else:
        named[faction] = pin_name(args[0], "the %s Speedrunner" % faction, None)
    if named: data["speedrunner"] = named
    else: data.pop("speedrunner", None)
    return finish(data, path)

# quaestor <Name-Realm> [faction] | quaestor --remove <Name-Realm> (1.5.5): one of that side's Quaestors, the
# Treasurer's executors (MAX_PINS["quaestor"] a side), added, or taken off whichever side names him.
def quaestor(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    faction = faction_of(args[1] if len(args) == 2 else "Alliance", "a Quaestor")
    name = pin_name(args[0], "a %s Quaestor" % faction, None)
    data = load_council(path)
    listed = data.get("quaestor") or {}
    if not isinstance(listed, dict): sys.exit("quaestor is not an object in %s" % path)
    def names_of(f):
        v = listed.get(f) or []
        return [v] if isinstance(v, str) else (v if isinstance(v, list) else [])
    def same(n): return isinstance(n, str) and n.strip().lower() == name.lower()
    if remove:
        found = False
        for f in list(listed):
            kept = [n for n in names_of(f) if not same(n)]
            if len(kept) != len(names_of(f)):
                found = True
                if kept: listed[f] = kept
                else: del listed[f]
        if not found: sys.exit("not a Quaestor in %s: %r" % (path, name))
    else:
        if any(same(n) for f in FACTIONS for n in names_of(f)): sys.exit("already a Quaestor: %r" % name)
        named = names_of(faction)
        if len(named) >= MAX_PINS["quaestor"]:
            sys.exit("the %s has %d Quaestors already: take one off first (quaestor --remove \"<Name-Realm>\")" % (faction, len(named)))
        listed[faction] = named + [name]
    if listed: data["quaestor"] = listed
    else: data.pop("quaestor", None)
    return finish(data, path)

# treasurer "<Treasurer-Realm>[,<Mail-Realm>,...]" [faction] | treasurer --remove [faction] (1.3.4):
# that side's Treasurer, then his mail characters (where the dues' mail goes), the whole list each time.
def treasurer(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if (remove and len(args) > 1) or (not remove and len(args) not in (1, 2)): sys.exit(__doc__)
    faction = faction_of((args[0] if args else "Alliance") if remove else (args[1] if len(args) == 2 else "Alliance"), "a Treasurer")
    data = load_council(path)
    listed = data.get("treasurer") or {}
    if not isinstance(listed, dict): sys.exit("treasurer is not an object in %s" % path)
    if remove:
        if faction not in listed: sys.exit("no %s Treasurer in %s" % (faction, path))
        del listed[faction]
    else:
        names = [n.strip() for n in args[0].split(",") if n.strip()]
        if not names: sys.exit(__doc__)
        listed[faction] = [pin_name(n, "the %s Treasurer" % faction, None) for n in names]
    if listed: data["treasurer"] = listed
    else: data.pop("treasurer", None)
    return finish(data, path)

# author <Name-Realm> [faction] | author --remove <Name-Realm> (1.3.4): one of the author's own characters.
def author(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = pin_name(args[0], "the author", None), faction_of(args[1] if len(args) == 2 else "Alliance", "an author's character")
    data = load_council(path)
    listed = data.get("author") or []
    if not isinstance(listed, list): sys.exit("author is not a list in %s" % path)
    def who(a): return (a.get("name") if isinstance(a, dict) else a) or ""
    kept = [a for a in listed if not (isinstance(who(a), str) and who(a).strip().lower() == name.lower())]
    if remove and len(kept) == len(listed): sys.exit("not an author's character in %s: %r" % (path, name))
    if not remove:
        if len(kept) != len(listed): sys.exit("already an author's character: %r" % name)
        kept.append(name if faction == "Alliance" else {"name": name, "faction": faction})
    if kept: data["author"] = kept
    else: data.pop("author", None)
    return finish(data, path)

# realm <Realm> <kind> <region> | realm --remove <Realm> (1.3.4): what a realm is (ns.RealmInfo);
# a realm named again is changed.
def realm_entry(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if (remove and len(args) != 1) or (not remove and len(args) != 3): sys.exit(__doc__)
    name = args[0].strip()
    if not realm_ok(name): sys.exit("not a realm the addon takes (as in Name-Realm, 40 bytes at most): %r" % name)
    data = load_council(path)
    listed = data.get("realms") or []
    if not isinstance(listed, list): sys.exit("realms is not a list in %s" % path)
    kept = [r for r in listed if not (isinstance(r, dict) and isinstance(r.get("name"), str) and r["name"].strip().lower() == name.lower())]
    if remove and len(kept) == len(listed): sys.exit("not a realm in %s: %r" % (path, name))
    if not remove: kept.append({"name": name, "kind": args[1], "region": args[2]})
    if kept: data["realms"] = kept
    else: data.pop("realms", None)
    return finish(data, path)

# A Lua string literal as lua_string writes it (plain bytes and \ddd), back to its text.
def lua_unstring(s):
    out, i = bytearray(), 0
    while i < len(s):
        if s[i] == "\\":
            out.append(int(s[i + 1:i + 4])); i += 4
        else:
            out += s[i].encode(); i += 1
    return out.decode()

def verified(text, sig, n):
    if len(sig) != SIG_LEN or re.fullmatch(r"[0-9a-fA-F]+", sig) is None:
        return False
    h = hashlib.sha256(text.encode()).digest()
    em = b"\x00\x01" + b"\xff" * (256 - 3 - len(PREFIX) - len(h)) + b"\x00" + PREFIX + h
    return pow(int(sig, 16), 3, n) == int.from_bytes(em, "big")

# check [CouncilList.lua]: what a written file holds, each list's signature checked with the key.
def check_out(path=OUT):
    try:
        with open(path, encoding="utf-8") as f: lua = f.read()
    except OSError as e: sys.exit("cannot read %s: %s" % (path, e))
    with open(KEY) as f: n = int(json.load(f)["n"], 16)
    lists = {k: lua_unstring(v) for k, v in re.findall(r'^ns\.(COUNCIL_SIGNED|COUNCIL_TITLES) = "((?:[^"\\]|\\[0-9]{3})*)"$', lua, re.M)}
    authority = []
    authority_declared = re.search(r'^ns\.COUNCIL_AUTHORITY\s*=', lua, re.M) is not None
    authority_block = re.search(r'^ns\.COUNCIL_AUTHORITY = \{\n(.*?)^\}$', lua, re.M | re.S)
    if authority_block:
        authority = [lua_unstring(v) for v in re.findall(r'^ "((?:[^"\\]|\\[0-9]{3})*)",$', authority_block.group(1), re.M)]
        written = [line for line in authority_block.group(1).splitlines() if line.strip()]
        if len(written) != len(authority):
            sys.exit("%s holds a malformed signed authority table" % path)
    elif authority_declared:
        sys.exit("%s holds a malformed signed authority table" % path)
    if "COUNCIL_SIGNED" not in lists: sys.exit("%s holds no name list" % path)
    bad = False
    for kind in ("COUNCIL_SIGNED", "COUNCIL_TITLES"):
        blob = lists.get(kind)
        if blob is None: continue
        text, _, sig = blob.rpartition("~")
        good = verified(text, sig, n)
        bad = bad or not good
        parts = text.split("~")
        print("%s: %s, time %s, realm group %s" % ("names" if kind == "COUNCIL_SIGNED" else "titles",
            "signature good" if good else "SIGNATURE BAD", parts[1], parts[2] or "(any)"))
        if kind == "COUNCIL_SIGNED":
            print("  names:", parts[3] or "-")
            continue
        print("  public:", parts[3] == "1")
        stewards, guilds, arbiters, leaders, apostles = {}, {}, {}, {}, {}
        pinned = {"king": {}, "queen": {}, "treasurer": {}, "author": {}, "realms": {}, "speedrunner": {}, "quaestor": {}}
        for entry in parts[4].split(";"):
            if entry.startswith("^steward^"):
                _, _, faction, names = entry.split("^", 3)
                stewards[faction] = names
            elif entry.startswith("^guilds^"):
                _, _, faction, names = entry.split("^", 3)
                guilds[faction] = names
            elif entry.startswith("^arbiter^"):
                _, _, faction, names = entry.split("^", 3)
                arbiters[faction] = names
            elif entry.startswith("^apostles^"):
                _, _, faction, names = entry.split("^", 3)
                apostles[faction] = names
            elif entry.startswith(("^king^", "^queen^", "^treasurer^", "^author^", "^realms^", "^speedrunner^", "^quaestor^")):
                _, kind, slot, names = entry.split("^", 3)
                pinned[kind][slot] = names
            elif entry.startswith("^leaders^"):
                _, _, faction, mode, epoch, issued, expires, names = entry.split("^", 7)
                leaders[faction] = "%s (mode %s, epoch %s, issued %s, expires %s)" % (names, mode, epoch, issued, expires)
            elif entry:
                part = entry.split("^")
                print("  %s: %s" % (part[0] or "(outside any department)", part[-1] or "-"))
        for faction in FACTIONS:
            print("  the %s King's Steward: %s" % (faction, stewards.get(faction) or "none"))
        for faction in FACTIONS:
            print("  the %s's approved guilds: %s" % (faction, guilds.get(faction) or "none"))
        for faction in FACTIONS:
            print("  the %s's arena arbiters (+a: auditor): %s" % (faction, arbiters.get(faction) or "none"))
        for faction in FACTIONS:
            print("  the %s's signed leadership: %s" % (faction, leaders.get(faction) or "none"))
        for faction in FACTIONS:
            print("  the %s's Church Apostles (* the Head): %s" % (faction, apostles.get(faction) or "none"))
        for faction in FACTIONS:
            print("  the %s King (signed): %s" % (faction, pinned["king"].get(faction) or "none (the code's pin, on the beta's group alone)"))
            print("  the %s Queen (signed, presentation only): %s" % (faction, pinned["queen"].get(faction) or "none"))
            print("  the %s Treasurer, then his mail characters (signed): %s" % (faction,
                pinned["treasurer"].get(faction) or "none (the code's pins, on the beta's group alone)"))
            print("  the %s author's characters (signed): %s" % (faction, pinned["author"].get(faction) or "none"))
            print("  the %s Olympus Speedrunner (signed, a title and a frame alone): %s" % (faction, pinned["speedrunner"].get(faction) or "none"))
            print("  the %s Quaestors (signed, the Treasurer's executors: his dragon, a title and a relay, none of his powers): %s" % (faction,
                pinned["quaestor"].get(faction) or "none"))
        for region in REGIONS:
            print("  the realms of %s: %s" % (region, pinned["realms"].get(region) or "none"))
    sets = {}
    for blob in authority:
        text, _, sig = blob.rpartition("~")
        good = verified(text, sig, n)
        bad = bad or not good
        parts = text.split("~", 11)
        if len(parts) != 12 or parts[0] != "HA1":
            print("authority: malformed"); bad = True; continue
        _, at, realm, faction, mode, epoch, issued, expires, root, index, count, body = parts
        try:
            at_n, epoch_n, issued_n, expires_n, index_n, count_n = map(
                int, (at, epoch, issued, expires, index, count))
        except ValueError:
            print("authority: malformed numbers"); bad = True; continue
        shape = (mode == "enforce" and faction in FACTIONS and at_n >= 1577836800
            and 1 <= epoch_n <= MAX_LEADERS_EPOCH and issued_n >= 1577836800
            and issued_n < expires_n and expires_n - issued_n <= 31 * 86400
            and re.fullmatch(r"[0-9a-f]{64}", root) is not None
            and 1 <= count_n <= MAX_AUTH_PARTS and 1 <= index_n <= count_n
            and 0 < len(body.encode()) <= MAX_AUTH_BODY
            and (body != "-" or (index_n == 1 and count_n == 1)))
        if not shape:
            print("authority %s: malformed" % (faction or "?")); bad = True; continue
        key = (at, realm, faction, epoch, issued, expires, root, count)
        bodies = sets.setdefault(key, {})
        if index_n in bodies:
            print("authority %s: duplicate part %d" % (faction, index_n)); bad = True; continue
        bodies[index_n] = body
        print("authority %s %s/%s: %s" % (faction, index, count, "signature good" if good else "SIGNATURE BAD"))
    for key, bodies in sets.items():
        at, realm, faction, epoch, issued, expires, root, count = key
        count = int(count)
        if len(bodies) != count or any(i not in bodies for i in range(1, count + 1)):
            print("authority %s: PARTIAL" % faction); bad = True; continue
        full = bodies[1] if count == 1 and bodies[1] == "-" else "!".join(bodies[i] for i in range(1, count + 1))
        digest = hashlib.sha256(full.encode()).hexdigest()
        good = digest == root
        bad = bad or not good
        print("authority %s: %d part(s), epoch %s, digest %s, %d bytes" % (
            faction, count, epoch, "good" if good else "BAD", len(full.encode())))
    if bad: sys.exit("a signature does not hold with %s" % KEY)

# --group "<Realm>+<Realm>", anywhere among a signing command's arguments: the realm group the
# lists are for (the council file's "realm", saved with it). Realms as names carry them.
def take_group(argv):
    global GROUP
    if "--group" not in argv: return argv
    i = argv.index("--group")
    if i + 1 >= len(argv): sys.exit("--group needs the realm group: --group \"<Realm>+<Realm>\"")
    group = argv[i + 1].strip()
    if not group or not all(realm_ok(r) for r in group.split("+")) or len(set(r.lower() for r in group.split("+"))) != len(group.split("+")):
        sys.exit("not a realm group the addon takes (realms as names carry them, joined by +): %r" % group)
    GROUP = group
    return argv[:i] + argv[i + 2:]

# What the new launch subcommands print: the council file and the lists written, and the titles
# list whole, for pasting in game with /oly approved paste.
def show_signed(signed):
    names, titles = signed[:2]
    print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
    print("and:", titles[:-SIG_LEN - 1])
    print("to paste in game with /oly approved paste:")
    print(titles)

if __name__ == "__main__":
    sys.argv = take_group(sys.argv)
    if GROUP is not None and (len(sys.argv) < 2 or sys.argv[1] not in ("council", "steward", "guild", "arbiter", "apostle",
            "king", "queen", "speedrunner", "quaestor", "treasurer", "author", "realm")):
        sys.exit("--group goes with a command that signs the council (council, steward, guild, arbiter, apostle, king, queen, speedrunner, quaestor, treasurer, author, realm)")
    if len(sys.argv) >= 2 and sys.argv[1] == "keygen": keygen()
    elif len(sys.argv) >= 3 and sys.argv[1] == "sign":
        text, sig = sign(sys.argv[2], *sys.argv[3:4])
        write_out(text + "~" + sig)
        print(OUT, "written:", text)
    elif len(sys.argv) == 3 and sys.argv[1] == "seal":
        print(seal(sys.argv[2]))
    elif len(sys.argv) in (2, 3) and sys.argv[1] == "council":
        path = sys.argv[2] if len(sys.argv) == 3 else COUNCIL
        data = load_council(path)
        names, titles, authority = sign_council_data(data)
        write_out(names, titles, authority)
        if GROUP is not None: save_council(path, data) # (the new realm group kept for the next signing)
        print(OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
        if authority: print("and %d signed authority part(s)" % len(authority))
    elif len(sys.argv) >= 3 and sys.argv[1] == "steward":
        signed = steward(sys.argv[2:]); names, titles = signed[:2]
        print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
    elif len(sys.argv) >= 3 and sys.argv[1] == "guild":
        signed = guild(sys.argv[2:]); names, titles = signed[:2]
        print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
        # Whole, for the first member of an approved guild to paste in game (/oly approved paste).
        print("to paste in game with /oly approved paste:")
        print(titles)
    elif len(sys.argv) >= 3 and sys.argv[1] == "arbiter":
        signed = arbiter(sys.argv[2:]); names, titles = signed[:2]
        print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
    elif len(sys.argv) >= 3 and sys.argv[1] == "apostle":
        signed = apostle(sys.argv[2:]); names, titles = signed[:2]
        print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
    elif len(sys.argv) >= 2 and sys.argv[1] == "king": show_signed(king(sys.argv[2:]))
    elif len(sys.argv) >= 2 and sys.argv[1] == "queen": show_signed(queen(sys.argv[2:]))
    elif len(sys.argv) >= 2 and sys.argv[1] == "speedrunner": show_signed(speedrunner(sys.argv[2:]))
    elif len(sys.argv) >= 3 and sys.argv[1] == "quaestor": show_signed(quaestor(sys.argv[2:]))
    elif len(sys.argv) >= 2 and sys.argv[1] == "treasurer": show_signed(treasurer(sys.argv[2:]))
    elif len(sys.argv) >= 3 and sys.argv[1] == "author": show_signed(author(sys.argv[2:]))
    elif len(sys.argv) >= 3 and sys.argv[1] == "realm": show_signed(realm_entry(sys.argv[2:]))
    elif len(sys.argv) in (2, 3) and sys.argv[1] in ("check", "--check"):
        check_out(sys.argv[2] if len(sys.argv) == 3 else OUT)
    else: sys.exit(__doc__)
