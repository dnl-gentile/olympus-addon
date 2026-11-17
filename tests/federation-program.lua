local ns, test, eq = ...
local P, T = ns.FederationProgram, 1795000000
local REALM = "CAMWOWUS1Realm2PvE"
local GROUP = "ForeverPvE"
local CARETAKER = "Silver Rock-" .. REALM
local OFFICIAL = "Amber Vale-" .. REALM
local GUILD = "Olympus Azure"
local ROW = ("%s=%s,%s,1"):format(GUILD, CARETAKER, OFFICIAL)

local function World(run)
	local old = { ns.rdb, ns.realm, ns.group, ns.faction, ns.Data.ServerTime, ns.Sign.Verify, ns.Roster.Fresh, ns.Roster.RankOf, ns.Print }
	local allowed, time = {}, T
	ns.rdb, ns.realm, ns.group, ns.faction = {}, REALM, GROUP, "Alliance"
	ns.Data.ServerTime = function() return time end
	ns.Sign.Verify = function(text, sig) return allowed[text] == sig end
	local function Blob(revision, rows, mode, faction, region, group, signed)
		local body = ("^program^%s^%s^%s^%d^%d^%s"):format(faction or "Alliance", region or "US", mode or "enforce", T - 2, T + 10, rows or "-")
		local text = ("HT1~%d~%s~0~%s"):format(revision, group or GROUP, body)
		local sig = string.rep("a", 512)
		if signed ~= false then allowed[text] = sig end
		return text .. "~" .. sig
	end
	local function Install(blob)
		P.RememberPolicy()
		ns.rdb.councilTitles = { blob = blob }
		P.RememberPolicy()
	end
	local ok, err = pcall(run, Blob, Install, function(now) time = now end)
	ns.rdb, ns.realm, ns.group, ns.faction, ns.Data.ServerTime, ns.Sign.Verify, ns.Roster.Fresh, ns.Roster.RankOf, ns.Print = unpack(old, 1, 9)
	if not ok then error(err, 0) end
end

test("federation program: absent, forged and other realm, faction or region policy grants no guild", function()
	World(function(Blob, Install)
		eq(P.Active(), false)
		eq(P.IsEnrolled(GUILD), false)
		ns.rdb.councilTitles = { program = { [GUILD] = true } }
		eq(P.IsEnrolled(GUILD), false, "saved fields are not evidence")
		Install(Blob(T, ROW, nil, nil, nil, nil, false))
		eq(P.Active(), false, "invalid signature cannot activate")
		eq(P.IsEnrolled(GUILD), false)
		Install(Blob(T + 1, ROW, nil, nil, nil, "ForeverPvP"))
		eq(P.Active(), false)
		Install(Blob(T + 2, ROW, nil, "Horde"))
		eq(P.IsEnrolled(GUILD), false)
		Install(Blob(T + 3, ROW, nil, nil, "EU"))
		eq(P.IsEnrolled(GUILD), false)
	end)
end)

test("federation program: enrollment requires both exact scoped roles and a fresh native roster for local use", function()
	World(function(Blob, Install)
		Install(Blob(T, ROW))
		eq(P.Active(), true)
		eq(P.IsEnrolled("OLYMPUS AZURE"), true, "the exact guild ignoring case")
		eq(P.IsEnrolled("Olympus Azure Two"), false, "a similar guild cannot borrow approval")
		eq(P.Role(CARETAKER, GUILD), "caretaker")
		eq(P.Role(OFFICIAL, GUILD), "official")
		eq(P.Role("Silver Rock", GUILD), nil)
		eq(P.Role("Silver Rock-CAMWOWUS1Realm3PvE", GUILD), nil)
		ns.Roster.Fresh = function() return nil end
		eq(P.LocalEnrollment(), nil, "the roster has not completed")
		local roster, ranks = { guild = GUILD }, { [CARETAKER] = 0, [OFFICIAL] = 1 }
		ns.Roster.Fresh = function() return roster end
		ns.Roster.RankOf = function(name) return ranks[name] end
		eq(P.LocalEnrollment(), GUILD)
		ranks[OFFICIAL] = 2
		eq(P.LocalEnrollment(), nil, "the official must keep the second slot")
		ranks[CARETAKER], ranks[OFFICIAL] = 1, 0
		eq(P.LocalEnrollment(), nil, "fresh contradictory roster")
		roster.guild = "Olympus Azure Two"
		eq(P.LocalEnrollment(), nil, "a guild transfer stops use")
		ns.faction = "Horde"
		eq(P.IsEnrolled(GUILD), false, "changing faction invalidates the snapshot")
		ns.faction, ns.realm = "Alliance", "CAMWOWEU1Realm2PvE"
		eq(P.IsEnrolled(GUILD), false, "the same name on a European guild cannot borrow approval")
	end)
end)

test("federation program: expiry and disappearance keep the policy active but remove all grants", function()
	World(function(Blob, Install, Move)
		Install(Blob(T, ROW))
		eq(P.IsEnrolled(GUILD, T + 9), true)
		Move(T + 10)
		eq(P.Active(), true)
		eq(P.IsEnrolled(GUILD), false)
		eq(P.IsEnrolled(GUILD, T), false, "expiry cannot be bypassed by choosing an earlier time")
		Install("HT1~1795000001~ForeverPvE~0~^^~" .. string.rep("b", 512))
		eq(P.Active(), true)
		eq(P.IsEnrolled(GUILD, T), false, "a departed grant cannot be recovered by choosing an old time")
		Install(Blob(T + 2, nil, "off", nil, nil, nil, false))
		eq(P.Active(), true, "a forged off record does not reopen access")
		Install(Blob(T - 1, nil, "off"))
		eq(P.Active(), true, "an older signed off record does not reopen access")
		Install(Blob(T + 3, nil, "off"))
		eq(P.Active(), false)
		eq(P.IsEnrolled(GUILD), false)
	end)
end)

test("federation program: signed malformed grants keep the rollout active without lending privileges", function()
	World(function(Blob, Install)
		Install(Blob(T, ROW .. "!" .. ROW))
		eq(P.Active(), true)
		eq(P.IsEnrolled(GUILD), false, "duplicated enrollment")
		Install(Blob(T + 1, (ROW:gsub("CAMWOWUS", "CAMWOWEU"))))
		eq(P.IsEnrolled(GUILD), false, "cross-region owners")
		Install(Blob(T + 2, (ROW:gsub(",1$", ",0"))))
		eq(P.IsEnrolled(GUILD), false, "the official cannot claim native owner rank")
	end)
end)


test("federation program: third-slot grants fail and caretaker contact needs a confirmed current roster", function()
	World(function(Blob, Install, Move)
		Install(Blob(T, (ROW:gsub(",1$", ",2"))))
		eq(P.Active(), true)
		eq(P.IsEnrolled(GUILD), false, "a third-slot attestation grants neither guild nor role")
		eq(P.Role(OFFICIAL, GUILD), nil)
		Install(Blob(T + 1, ROW))
		local output
		ns.Print = function(message) output = message end
		ns.Roster.Fresh = function() return nil end
		SlashCmdList.OLYMPUS("caretaker")
		eq(output, ns.L.FEDERATION_CARETAKER_UNAVAILABLE)
		ns.Roster.Fresh = function() return { guild = GUILD } end
		ns.Roster.RankOf = function(name) return ({ [CARETAKER] = 0, [OFFICIAL] = 1 })[name] end
		SlashCmdList.OLYMPUS("caretaker")
		eq(output, ns.L.FEDERATION_CARETAKER:format(CARETAKER))
		Move(T + 10)
		SlashCmdList.OLYMPUS("caretaker")
		eq(output, ns.L.FEDERATION_CARETAKER_UNAVAILABLE)
	end)
end)
