local H = ...
local test, eq = H.test, H.eq
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local function Entry(w, fid, gk)
	return { season = 1, fid = fid, t = w.clock - 10, cat = "A", bo = 1,
		gkA = "3e8.00000001", A = "Torvin Hale-Emberfall", gkB = "3e8.00000002", B = "Selka Drummond-Emberfall",
		sc = "1:0", w = "A", m = "K", dur = 40, gkArb = gk, fl = "prt" }
end
local function Relay(w, c, sender, e)
	local LG = c.ns.ArenaLedger
	local text = LG.Encode(e):match("^[^~]+~(.*)$")
	w:As(c, function() c.ns.Arena.Inject("CHANNEL", sender, "AB~L1~P~1~1~1~1~" .. text) end)
end
local function Empty(w, c)
	eq(w:As(c, c.ns.ArenaLedger.Book, "L", 1), nil, "no book allocation")
	eq(w:As(c, c.ns.ArenaLedger.CoreT, "L", "titles"), nil, "no title allocation")
end

test("ledger provenance: a clerk cannot allocate records for a known nonarbiter", function()
	local w, cast = W3.New()
	local c = cast.spectator
	W3.Companion(w, c)
	c.globals.GetPlayerInfoByGUID = function() return nil, nil, nil, nil, nil, cast.A.short, cast.A.realm end
	Relay(w, c, cast.arbiter.name, Entry(w, "F1zz", "3e8.abcdef01"))
	Empty(w, c)
	W3.NoErrors(w)
end)

test("ledger provenance: held fight arbiter identity defeats a clerk or staff relay with a conflicting GUID", function()
	for _, staff in ipairs({ false, true }) do
		local w, cast = W3.New()
		local c = cast.arbiter
		W3.Companion(w, c)
		local fid = assert(W3.M(w, c, "ArenaFights").New({ A = cast.A.name, B = cast.B.name, bo = 1 }))
		Relay(w, c, staff and H.World.NAMES.councillor or c.name, Entry(w, fid, "3e8.abcdef01"))
		Empty(w, c)
		W3.NoErrors(w)
	end
end)

test("ledger provenance: own known actor identity rejects an AE with an unknown conflicting GUID", function()
	local w, cast = W3.New()
	local c = cast.arbiter
	W3.Companion(w, c)
	local e = Entry(w, "F1zz", "3e8.abcdef01")
	w:As(c, function() c.ns.Arena.Inject("CHANNEL", c.name, "AE~L1~" .. c.ns.ArenaLedger.Encode(e)) end)
	Empty(w, c)
	W3.NoErrors(w)
end)

test("ledger provenance: trusted late unknown relays and unheld public AE remain accepted", function()
	local w, cast = W3.New()
	local c = cast.spectator
	W3.Companion(w, c)
	Relay(w, c, H.World.NAMES.councillor, Entry(w, "F1zz", "3e8.abcdef01"))
	local e = Entry(w, "F2zz", "3e8.abcdef02")
	w:As(c, function() c.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. c.ns.ArenaLedger.Encode(e)) end)
	eq(#w:As(c, c.ns.ArenaLedger.Entries), 2)
	W3.NoErrors(w)
end)
