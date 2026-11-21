-- Roster.GuidOf (Olympus Link): a fresh, complete own-guild snapshot's GUID, found by name
-- the way RankOf finds his rank. The roster's 17th return is the GUID.
local ns, test, eq = ...

local GUID_A, GUID_B = "Player-4613-005A70D8", "Player-4613-0000BEEF"

local function WithRoster(guild, rows, body)
	local saved = { total = GetNumGuildMembers, info = GetGuildRosterInfo, guild = GetGuildInfo,
		realm = ns.realm, group = ns.group, faction = ns.faction, me = ns.me, split = ns.splitNames,
		now = ns.Now, secret = issecretvalue }
	local ok, err = pcall(function()
		ns.realm, ns.group, ns.splitNames = "CAMWOWUS2Realm1PvE", "ForeverPvE", true
		ns.faction = ns.Faction() -- the login sets this before security-sensitive roster consumers run
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
	ns.faction, ns.Now = saved.faction, saved.now
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

test("Roster.GuidOf: changing guild refuses the retained snapshot before another scan", function()
	WithRoster("OLYMPUS GODS", { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B } }, function()
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_B)
		GetGuildInfo = function() return "ANOTHER GUILD", "Member", 3 end
		eq(ns.Roster.GuidOf("Hater Fistinator"), nil, "the old guild cannot lend its GUID to a new guild")
	end)
end)

test("Roster.GuidOf: leaving guild refuses the retained snapshot even after a no-guild scan", function()
	WithRoster("OLYMPUS GODS", { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B } }, function()
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_B)
		GetGuildInfo = function() return nil end
		eq(ns.Roster.GuidOf("Hater Fistinator"), nil, "leaving the guild refuses even before a scan")
		eq(ns.Roster.Scan(), nil, "no-guild scans leave the cached rows in memory")
		eq(ns.Roster.GuidOf("Hater Fistinator"), nil, "a retained GUID cannot prove membership without a guild")
	end)
end)

test("Roster.GuidOf: an incomplete scan refuses both retained and newly scanned GUIDs", function()
	local rows = { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B } }
	WithRoster("OLYMPUS GODS", rows, function()
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_B)
		rows[2] = nil
		GetNumGuildMembers = function() return 2, 2 end
		ns.Roster.Scan()
		eq(ns.Roster.complete, false, "the server has not filled the second row")
		eq(ns.Roster.GuidOf("Hater Fistinator"), nil, "the absent row's retained GUID is refused")
		eq(ns.Roster.GuidOf("Wazizo Thelongone"), nil, "a partial snapshot cannot authorize even a row it saw")
		rows[2] = { "Hater Fistinator", GUID_A }
		ns.Roster.Scan()
		eq(ns.Roster.complete, true)
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_A, "the completed scan returns the exact current GUID")
	end)
end)

test("Roster.GuidOf: a snapshot expires after the authority limit and a fresh scan restores the current GUID", function()
	local rows = { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B } }
	WithRoster("OLYMPUS GODS", rows, function()
		local now = ns.Now()
		ns.Now = function() return now end
		ns.Roster.Scan()
		now = now + ns.Roster.AUTHORITY_FRESH
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_B, "the existing freshness boundary is inclusive")
		now = now + 1
		eq(ns.Roster.GuidOf("Hater Fistinator"), nil, "the expired snapshot's GUID is refused")
		rows[2][2] = GUID_A
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_A, "only a new scan restores the exact current GUID")
	end)
end)

test("Roster.GuidOf: a realm-group change refuses the retained own-guild snapshot", function()
	WithRoster("OLYMPUS GODS", { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B } }, function()
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_B)
		local group = ns.group
		ns.group = "AnotherGroup"
		eq(ns.Roster.GuidOf("Hater Fistinator"), nil, "the old group cannot authorize the new group")
		ns.group = group
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_B, "the unchanged, still-fresh native snapshot is usable in its original scope")
	end)
end)

test("Roster.GuidOf: a faction change refuses the retained own-guild snapshot", function()
	WithRoster("OLYMPUS GODS", { { "Wazizo Thelongone", GUID_A }, { "Hater Fistinator", GUID_B } }, function()
		ns.Roster.Scan()
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_B)
		local faction = ns.faction
		ns.faction = "AnotherFaction"
		eq(ns.Roster.GuidOf("Hater Fistinator"), nil, "the old faction cannot authorize the new faction")
		ns.faction = faction
		eq(ns.Roster.GuidOf("Hater Fistinator"), GUID_B, "the unchanged, still-fresh native snapshot is usable in its original scope")
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
