-- Check output from the operator's signer against the production addon reader.
local root, scratch = arg[1], arg[2]
local function Read(file)
	local handle = assert(io.open(scratch .. "/" .. file, "r"))
	local text = handle:read("*a")
	handle:close()
	return text
end

local function Noop() end
CreateFrame = function() return setmetatable({}, { __index = function() return Noop end }) end
StaticPopupDialogs, SlashCmdList = {}, {}
GetLocale = function() return "enUS" end
time, date = os.time, os.date
local ns = {}
for _, file in ipairs({ "Locales", "Core", "Sign", "Locales/FugitivesText", "FederationFugitives" }) do
	assert(loadfile(root .. "/Olympus/" .. file .. ".lua"))("Olympus", ns)
end
local f, guild = ns.FederationFugitives, "Olympus Willow"
local first = "Ámber Vale-CAMWOWUS1Realm2PvE"
local second = "Silver Rock-CAMWOWUS2Realm5PvE"
local now = 1800010000
ns.db, ns.realm, ns.group, ns.faction = {}, "CAMWOWUS1Realm2PvE", "ForeverPvE", "Alliance"
ns.Data = { ServerTime = function() return now end }
ns.Alts = { Linked = function() return {} end }
ns.FederationProgram = { IsEnrolled = function(name) return name == guild end }
ns.After, ns.Print = Noop, Noop

local key = Read("council-key.json")
local n, mu = key:match('"n"%s*:%s*"0x(%x+)"'), key:match('"mu"%s*:%s*"0x(%x+)"')
local k = tonumber(key:match('"k"%s*:%s*(%d+)'))
assert(n and mu and k, "the disposable test key has public components")

local initial, replace, clear = Read("initial.txt"), Read("replacement.txt"), Read("clear.txt")
assert(not f.Paste(initial), "the author key must reject the disposable key's list")
ns.Sign.WithKey(n, mu, k, function()
	assert(not f.Paste((initial:gsub("Silver Rock", "Ash Fall"))), "reject signed list altered in transit")
	assert(f.Paste(initial) and f.IsListed(first, guild) and f.IsListed(second, guild), "accept the initial scoped list")
	assert(f.Paste(replace) and not f.IsListed(first, guild) and f.IsListed(second, guild), "omission removes a character")
	assert(f.Paste(clear) and not f.IsListed(second, guild), "empty signed list clears the scope")
	assert(not f.Paste(initial), "a previous list cannot restore a cleared decision")
end)
print("federation fugitive signing round trip passed")
