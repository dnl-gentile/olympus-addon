-- Roster.GuidOf (Olympus Link): the GUID the last scan gave for a member of our guild, found by name
-- the way RankOf finds his rank. The roster's 17th return is the GUID.
local ns, test, eq = ...

local GUID_A, GUID_B = "Player-4613-005A70D8", "Player-4613-0000BEEF"

local function WithRoster(guild, rows, body)
	local saved = { total = GetNumGuildMembers, info = GetGuildRosterInfo, guild = GetGuildInfo,
		realm = ns.realm, group = ns.group, me = ns.me, split = ns.splitNames, secret = issecretvalue }
	local ok, err = pcall(function()
		ns.realm, ns.group, ns.splitNames = "CAMWOWUS2Realm1PvE", "ForeverPvE", true
		ns.me = "Wazizo Thelongone-CAMWOWUS2Realm1PvE"
		GetGuildInfo = function() return guild, "Member", 3 end
		GetNumGuildMembers = function() return #rows, #rows end
		GetGuildRosterInfo = function(i)
			local r = rows[i]
			if r then return r[1], "Member", 3, 60, "Warrior", "Stormwind City", "", "", true, 0, "WARRIOR", 0, 0, false, false, 0, r[2] end
		end
		body()
	end)
	GetNumGuildMembers, GetGuildRosterInfo, GetGuildInfo = saved.total, saved.info, saved.guild
	ns.realm, ns.group, ns.me, ns.splitNames = saved.realm, saved.group, saved.me, saved.split
	issecretvalue = saved.secret
	ns.Roster.Scan() -- the harness's own roster for the tests after this one
	if not ok then error(err, 0) end
end

test("Roster.GuidOf: a member of our own sub-realm gives his scanned GUID; an absent name gives nil", function()
	WithRoster("OLYMPUS GODS", { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B } }, function()
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator-CAMWOWUS2Realm1PvE"), GUID_B)
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_B, "the short form of our own realm")
		eq(ns.Roster.GuidOf("Wazizo Thelongone-CAMWOWUS2Realm1PvE"), GUID_A)
		eq(ns.Roster.GuidOf("Nobody Here-CAMWOWUS2Realm1PvE"), nil, "not in the guild")
		eq(ns.Roster.GuidOf(nil), nil)
	end)
end)

test("Roster.GuidOf: a sister sub-realm of the family finds the same member; another family or a realm outside Forever does not", function()
	WithRoster("OLYMPUS GODS", { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B } }, function()
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator-CAMWOWUS2Realm7PvE"), GUID_B)
		eq(ns.Roster.GuidOf("Hater Fistinator-CAMWOWUS1Realm8PvP"), nil, "the PvP family is another family")
		eq(ns.Roster.GuidOf("Hater Fistinator-Stormrage"), nil, "a realm outside Forever")
	end)
end)

test("Roster.GuidOf: a secret or missing GUID gives nil, never the value", function()
	WithRoster("OLYMPUS GODS", { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B }, { "Quiet Soul", nil } }, function()
		issecretvalue = function(v) return v == GUID_B end
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator-CAMWOWUS2Realm1PvE"), nil, "secret value")
		eq(ns.Roster.GuidOf("Quiet Soul-CAMWOWUS2Realm1PvE"), nil, "no GUID given")
		eq(ns.Roster.GuidOf("Wazizo Thelongone-CAMWOWUS2Realm1PvE"), GUID_A)
	end)
end)

test("Roster.GuidOf: a new scan updates the answer, and a guild change clears it", function()
	local rows = { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B } }
	WithRoster("OLYMPUS GODS", rows, function()
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator-CAMWOWUS2Realm1PvE"), GUID_B)
		rows[2][2] = GUID_A
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator-CAMWOWUS2Realm1PvE"), GUID_A, "the index follows the scan")
		GetGuildInfo = function() return "ANOTHER GUILD", "Member", 3 end
		rows[1], rows[2] = { "Wazizo Thelongone", GUID_A }, { "Someone Else", GUID_B }
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator-CAMWOWUS2Realm1PvE"), nil, "he is not in the other guild")
		eq(ns.Roster.GuidOf("Someone Else-CAMWOWUS2Realm1PvE"), GUID_B)
	end)
end)
