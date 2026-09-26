#!/usr/bin/env python3
"""Signs the High Council list for the Olympus addon.

  python3 scripts/council-sign.py keygen                      # once: ~/.olympus/council-key.json
  python3 scripts/council-sign.py sign "Name One,Name Two"    # writes dist/CouncilList.lua

The private key never leaves ~/.olympus. The addon carries only the public key (Sign.lua) and
checks the signature: RSA-2048, e = 3, PKCS#1 v1.5 over SHA-256. CouncilList.lua holds the names:
it is copied to the author's own game only (never in the repository or the public zip).
"""
import hashlib, json, os, secrets, sys, time

KEY = os.path.expanduser("~/.olympus/council-key.json")
PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")
BASE, BITS = 1 << 24, 2048

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

def sign(names, realm="ClassicBetaPvP+ClassicBetaPvP2", at=None):
    key = json.load(open(KEY))
    n, d = int(key["n"], 16), int(key["d"], 16)
    names = ",".join(x.strip() for x in names.split(",") if x.strip())
    text = "HS1~%d~%s~%s" % (at or int(time.time()), realm, names)
    h = hashlib.sha256(text.encode()).digest()
    em = b"\x00\x01" + b"\xff" * (256 - 3 - len(PREFIX) - len(h)) + b"\x00" + PREFIX + h
    s = pow(int.from_bytes(em, "big"), d, n)
    return text, format(s, "0512x")

if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "keygen": keygen()
    elif len(sys.argv) >= 3 and sys.argv[1] == "sign":
        text, sig = sign(sys.argv[2])
        os.makedirs("dist", exist_ok=True)
        with open("dist/CouncilList.lua", "w") as f:
            f.write("-- Local only: the High Council list, signed. Never commit or publish this file.\n")
            f.write("local _, ns = ...\nns.COUNCIL_SIGNED = %s\n" % json.dumps(text + "~" + sig))
        print("dist/CouncilList.lua written:", text)
    else: sys.exit(__doc__)
