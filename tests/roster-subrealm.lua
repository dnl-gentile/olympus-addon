-- Forever: the roster gives every member's name bare (the #76 dumps: "roster bare=43" across nine
-- servers), while a guildmate's whispers and relayed words come stamped "Name-<his sub-realm>".
local ns, test, eq = ...

test("Forever sub-realms: a guildmate stamped with another sub-realm of our family is still our guildmate; another family or a realm outside Forever is not", function()
	local saved = { total = GetNumGuildMembers, info = GetGuildRosterInfo, guild = GetGuildInfo,
		realm = ns.realm, group = ns.group, me = ns.me, split = ns.splitNames }
	local ok, err = pcall(function()
		ns.realm, ns.group, ns.splitNames = "CAMWOWUS2Realm1PvE", "ForeverPvE", true
		ns.me = "Wazizo Thelongone-CAMWOWUS2Realm1PvE"
		GetGuildInfo = function() return "OLYMPUS GODS", "Member", 3 end
		local rows = { { "Wazizo Thelongone", "Member", 3 }, { "Hater Fistinator", "Officer", 1 } }
		GetNumGuildMembers = function() return #rows, #rows end
		GetGuildRosterInfo = function(i)
			local r = rows[i]
			if r then return r[1], r[2], r[3], 60, "Warrior", "Stormwind City", "", "", true, 0, "WARRIOR" end
		end
		ns.Roster.Scan()

		local officer = "Hater Fistinator-CAMWOWUS2Realm7PvE"
		eq(ns.Roster.RankOf(officer), 1)
		eq(ns.Hop.Trusted(officer), true, "his layer hop offer is taken")
		eq(ns.Channels.VerifiedLevel(officer, "OLYMPUS GODS"), ns.Channels.LevelOf("OLYMPUS GODS", 1), "his guild chat is not forged")
		eq(ns.Roster.RankOf("Hater Fistinator-CAMWOWUS1Realm8PvP"), nil, "the PvP family is another family")
		eq(ns.Roster.RankOf("Hater Fistinator-Stormrage"), nil, "a realm outside Forever")

		-- His chat line shows his plain name, as the game's own chat does, not "Name-<his sub-realm>".
		local line = ns.Channels.FormatLine("A", officer, "OLYMPUS GODS", "WA", "inv", true)
		assert(line:find("Hater Fistinator]", 1, true) and not line:find("CAMWOW", 1, true), line)
	end)
	GetNumGuildMembers, GetGuildRosterInfo, GetGuildInfo = saved.total, saved.info, saved.guild
	ns.realm, ns.group, ns.me, ns.splitNames = saved.realm, saved.group, saved.me, saved.split
	ns.Roster.Scan() -- the harness's own roster for the tests after this one
	if not ok then error(err, 0) end
end)
