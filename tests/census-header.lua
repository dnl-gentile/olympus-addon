-- Header presentation uses the same Data.Groups totals as the detailed census.
local ns, test, eq, extra = ...

test("census scope: header names the current ruleset and labels a quarantined snapshot without counting it", function()
	extra.WithUI(function()
		local UI = extra.LoadUI()
		local oldGroup, oldGroups = ns.group, ns.Data.Groups
		local ok, err = pcall(function()
			ns.group = "ForeverPvP"
			ns.Data.Groups = function() return { characters = 7149 } end
			local at = 1793966400
			local s = { characters = 182, total = 182, online = 8, newest = at, guilds = {},
				history = { characters = 13614, observed = at, unscoped = true } }
			local h = UI.CensusHeader(s, at + 60)
			eq(h.characters, 182)
			eq(h.secondary, ns.L.CENSUS_HEADER_ALL:format(ns.FormatNumber(7149)))
			eq(h.sub, ns.L.CENSUS_STATS_KIND_PVP .. " · " .. ns.L.CENSUS_HEADER_UNSCOPED:format(ns.FormatNumber(13614), date("%m/%d %H:%M", at)))
		end)
		ns.group, ns.Data.Groups = oldGroup, oldGroups
		if not ok then error(err, 0) end
	end)
end)

test("census header 1.5.2: current-server soldiers stay prominent, all-server total is secondary, people stay inside", function()
	extra.WithUI(function()
		local UI = extra.LoadUI()
		local oldGroups, oldRebuilding = ns.Data.Groups, ns.Data.Rebuilding
		local ok, err = pcall(function()
			local s = { characters = 1200, total = 1000, online = 40, newest = ns.Now(), guilds = {} }
			ns.Data.Groups = function(received)
				eq(received, s)
				return { characters = 3456, people = 2500 }
			end
			ns.Data.Rebuilding = function() return nil end
			local h = UI.CensusHeader(s)
			eq(h.characters, 1200)
			eq(h.secondary, ns.L.CENSUS_HEADER_ALL:format(ns.FormatNumber(3456)))
			assert(not h.secondary:find("2500", 1, true), "cross-server player estimates never replace soldiers")
			eq(h.note, nil)
		end)
		ns.Data.Groups, ns.Data.Rebuilding = oldGroups, oldRebuilding
		if not ok then error(err, 0) end
	end)
end)

test("census header: a retained total shows reports received from other guilds during login rebuild", function()
	extra.WithUI(function()
		local UI = extra.LoadUI()
		local oldGroup, oldGroups, oldLogin = ns.group, ns.Data.Groups, ns.Comm.loginAt
		local ok, err = pcall(function()
			local at = 1793966400
			local dateLabel = date("%m/%d %H:%M", at)
			ns.group = "ForeverPvP"
			ns.Comm.loginAt = at + 120
			ns.Data.Groups = function() return { characters = 5500 } end
			ns.rdb.guilds = {
				["Olympus Own"] = { t = at + 125, mine = true },
				["Olympus Saved"] = { t = at + 60 },
			}
			local s = { characters = 4000, total = 3600, guilds = {}, snapshot = { observed = at },
				live = { freshCharacters = 630, freshGuilds = 2 } }
			local scope = ns.L.CENSUS_STATS_KIND_PVP .. " · "
			local first = UI.CensusHeader(s, at + 130)
			eq(first.characters, 4000)
			eq(first.secondary, ns.L.CENSUS_HEADER_ALL:format(ns.FormatNumber(5500)))
			eq(first.sub, scope .. ns.L.CENSUS_HEADER_RECEIVING:format(dateLabel, 0))
			eq(first.note, ns.L.CENSUS_HEADER_RECEIVING_TIP:format(dateLabel))

			ns.rdb.guilds["Olympus Heard"] = { t = at + 135 }
			eq(UI.CensusHeader(s, at + 136).sub, scope .. ns.L.CENSUS_HEADER_RECEIVING:format(dateLabel, 1))
			ns.rdb.guilds["Olympus Heard"].t = at + 140
			eq(UI.CensusHeader(s, at + 141).sub, scope .. ns.L.CENSUS_HEADER_RECEIVING:format(dateLabel, 1))
			eq(UI.CensusHeader(s, at + 120 + ns.Data.REBUILD_FOR).sub,
				scope .. ns.L.CENSUS_HEADER_SAVED:format(dateLabel, ns.FormatNumber(630), 2))
		end)
		ns.group, ns.Data.Groups, ns.Comm.loginAt = oldGroup, oldGroups, oldLogin
		if not ok then error(err, 0) end
	end)
end)

test("census header: retained count shows its original date and live partial population after the rebuild timer", function()
	extra.WithUI(function()
		local UI = extra.LoadUI()
		local oldGroups, oldRebuilding = ns.Data.Groups, ns.Data.Rebuilding
		local ok, err = pcall(function()
			local at = 1793966400
			local s = { characters = 4000, total = 3600, online = 10, newest = at,
				guilds = {}, snapshot = { observed = at }, live = { guilds = 2, freshGuilds = 1, freshCharacters = 630 } }
			ns.Data.Groups = function() return { characters = 5500 } end
			ns.Data.Rebuilding = function() return nil end
			local h = UI.CensusHeader(s, at + 600)
			eq(h.characters, 4000)
			eq(h.sub, ns.L.CENSUS_HEADER_SAVED:format(date("%m/%d %H:%M", at), ns.FormatNumber(630), 1))
			eq(h.note, ns.L.CENSUS_HEADER_SAVED_TIP:format(date("%m/%d %H:%M", at)))
			s.live.freshCharacters = 620
			local updated = UI.CensusHeader(s, at + 601)
			eq(updated.characters, 4000)
			eq(updated.sub, ns.L.CENSUS_HEADER_SAVED:format(date("%m/%d %H:%M", at), ns.FormatNumber(620), 1))
			s.history, s.snapshot, s.characters, s.total = { observed = at, characters = 4000 }, nil, 100, 100
			h = UI.CensusHeader(s, at + 2 * 86400)
			eq(h.characters, 100, "expired saved history is not asserted as the live total")
			eq(h.sub, ns.L.CENSUS_HEADER_HISTORY:format(ns.FormatNumber(4000), date("%m/%d %H:%M", at)))
		end)
		ns.Data.Groups, ns.Data.Rebuilding = oldGroups, oldRebuilding
		if not ok then error(err, 0) end
	end)
end)

test("census connection: reports from the local guild do not mask missing remote data", function()
	local C, V, savedRelay = ns.Comm, ns.Views, ns.Relay
	local savedLane = C.LaneStats
	local R = {}
	ns.Relay = R
	local ok, err = pcall(function()
		local at = ns.Now()
		local s = { guilds = { { g = { mine = true }, observed = at } } }
		R.On = function() return false end
		eq(V.CensusConnectionLine(s), nil)
		R.On = function() return true end
		R.Pick = function() return nil, false end
		C.LaneStats = function() return { lane = 9, dominant = 7, mismatch = true } end
		local line = V.CensusConnectionLine(s)
		assert(line.text:find(ns.L.CENSUS_REMOTE_NONE, 1, true))
		assert(line.text:find(ns.L.CENSUS_RELAY_NONE, 1, true))
		assert(line.text:find(ns.L.CENSUS_LANE_MISMATCH:format(7), 1, true))
		R.Pick = function() return "Relay", true end
		s.guilds[2] = { g = {}, observed = at - 60 }
		line = V.CensusConnectionLine(s)
		assert(line.text:find(ns.L.CENSUS_RELAY_READY, 1, true))
		assert(line.text:find(ns.L.CENSUS_REMOTE_AGE:format(ns.Ago(at - 60)), 1, true))
	end)
	ns.Relay, C.LaneStats = savedRelay, savedLane
	if not ok then error(err, 0) end
end)
