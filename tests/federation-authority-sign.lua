-- The production certificate parser checks the real CLI output with public
-- components from its disposable RSA key; no private exponent enters this VM.
local root, scratch = assert(arg[1]), assert(arg[2])
local function Noop() end
CreateFrame = function() return setmetatable({}, { __index = function() return Noop end }) end
StaticPopupDialogs, SlashCmdList = {}, {}
GetLocale = function() return "enUS" end
time, date = os.time, os.date
local ns = { Comm = { Handle = Noop } }
for _, file in ipairs({ "Locales", "Core", "Sign", "Ed25519" }) do
	assert(loadfile(root .. "/Olympus/" .. file .. ".lua"))("Olympus", ns)
end
local function Read(name)
	local f = assert(io.open(scratch .. "/" .. name, "rb"))
	local text = f:read("*a"); f:close(); return text
end
local public = assert(loadfile(scratch .. "/public-key.lua"))()
local certificate, revocation = Read("valid.txt"), Read("revoke.txt")
local GUILD, PERSON = "Olympus Azure", "Silver Rock-CAMWOWUS1Realm2PvE"
ns.db, ns.rdb, ns.realm, ns.group, ns.faction, ns.me = {}, {}, "CAMWOWUS1Realm2PvE", "ForeverPvE", "Alliance", PERSON
ns.Data = { ServerTime = function() return 1795000000 end }
ns.Debts = { Hex = ns.Ed25519.ToHex }
ns.FederationProgram = { BaseEnrolled = function(guild) return guild == GUILD end }
ns.IsHighCouncillor = function(name) return name == PERSON end
ns.IsAuthorName = function() return false end
ns.Fire, ns.On = Noop, Noop
ns.Comm = { RelayPieces = Noop, Handle = Noop }
assert(loadfile(root .. "/Olympus/FederationAuthority.lua"))("Olympus", ns)
local a = ns.FederationAuthority
assert(not a.ImportCertificate(certificate), "production author key must reject the disposable key")
ns.Sign.WithKey(public.n, public.mu, public.k, function()
	assert(a.ImportCertificate(certificate), "real CLI RSA signature and native scope accepted")
	local cert = assert(a.Certificate(certificate, 1795000000))
	assert(cert.issuer == PERSON and cert.role == "council" and #cert.key == 32)
	assert(not a.ImportCertificate(certificate:gsub("Silver Rock", "Silver Bird")), "changed subject rejected")
	assert(not a.ImportRevocation(revocation:gsub("FKR1~US:", "FKR1~EU:")), "foreign/tampered revocation rejected")
	assert(a.ImportRevocation(revocation), "real CLI author revocation accepted")
	assert(not a.Certificate(certificate, 1795000000), "revoked certificate rejected by production reader")
end)
print("federation authority signing round trip passed")
