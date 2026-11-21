-- Realm recovery from an existing self claim, using the same signer and claim
-- reader that real Arena clients use. Every character and key here is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local M = assert(loadfile(H.ROOT .. "tests/arena/lib/money-world.lua"))(H)

test("realm identity own claim: an unknown native server recovers only this character's existing signed realm", function()
	local world = World.New()
	local realm, guid = "CAMWOWEU1Realm9PvP", "Player-8999-00000001"
	local client = M.Client(world, "Lida Fenn", { realm = realm, guid = guid })
	client.Debts.ClaimParts()
	local claim = client.db.arenaKey.claims[guid]
	assert(claim and claim.name == client.name)
	client.globals.GetRealmName, client.globals.GetNormalizedRealmName = function() return "" end, function() return "" end
	client.globals.UnitFullName = function() return "Lida", "Fenn" end
	client.globals.WOW_PROJECT_ID = 18
	client.ns.FOREVER_REALMS_BY_ID = {}
	client.ns.realm, client.ns.group, client.ns.me = "?", "?", "Lida Fenn"
	world:As(client, function()
		eq(client.ns.CurrentRealm(), realm)
		eq(client.ns.GroupOf(client.ns.CurrentRealm()), "ForeverPvP")
		eq(client.db.arenaKey.claims[guid], claim, "reading recovery evidence never replaces the original claim")
		eq(client.db.nativeRealmNames, nil, "the prior claim is not stored as a new native observation")
	end)
	client.globals.WOW_PROJECT_ID = 1
	world:As(client, function() eq(client.ns.CurrentRealm(), "?", "a different game project cannot inherit Forever authority") end)
	M.NoErrors(world)
end)

test("realm identity own claim: a changed signature, another character and missing evidence cannot recover a realm", function()
	local world = World.New()
	local realm, guid = "CAMWOWUS1Realm9RP", "Player-8999-00000002"
	local client = M.Client(world, "Parric Stowe", { realm = realm, guid = guid })
	client.Debts.ClaimParts()
	client.globals.GetRealmName, client.globals.GetNormalizedRealmName = function() return "" end, function() return "" end
	client.globals.UnitFullName = function() return "Parric", "Stowe" end
	client.globals.WOW_PROJECT_ID = 18
	client.ns.FOREVER_REALMS_BY_ID = {}
	client.ns.realm, client.ns.group, client.ns.me = "?", "?", "Parric Stowe"
	world:As(client, function()
		local key, debts = client.db.arenaKey, client.ns.Debts
		local claim = key.claims[guid]
		eq(client.ns.CurrentRealm(), realm)
		local signature = claim.sig
		claim.sig = (signature:sub(1, 1) == "A" and "B" or "A") .. signature:sub(2)
		eq(client.ns.CurrentRealm(), "?", "an edited signature invalidates the memoized recovery")
		claim.name = "Wenna Crale-" .. realm
		claim.sig = debts.B64(client.ns.Ed25519.Sign(debts.UnB64(key.seed), "OLYA1|" .. guid .. "|" .. claim.name, debts.UnB64(key.pk)))
		eq(debts.OwnClaimName(), claim.name, "the claim's signature is genuine")
		eq(client.ns.CurrentRealm(), "?", "a valid signature for a different native character grants nothing")
		key.claims[guid] = nil
		eq(client.ns.CurrentRealm(), "?")
		client.db.arenaKey = nil
		eq(client.ns.CurrentRealm(), "?")
		eq(client.db.arenaKey, nil, "recovery never creates a replacement key")
	end)
	M.NoErrors(world)
end)
