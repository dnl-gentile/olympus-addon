	local _, test, eq, extra = ...
	local ROOT = assert(extra and extra.ROOT, "site aggregate test root")
	local FILE = ROOT .. "OlympusSiteAggregate/SiteAggregate.lua"

	local function Base(now)
		return {
			schema = "olympus-census-checkpoint", version = 1,
			capturedAt = now - 100000, capturedAtServer = now, timeSource = "server",
			scope = { realm = "ClassicBetaPvP", realmGroup = "ClassicBetaPvP+ClassicBetaPvP2", faction = "Alliance" },
			guilds = { {
				name = "Olympus II", members = 900, online = 200, fresh = true, counted = true,
				observedAt = now - 100010, observedAtServer = now - 10,
				provenance = { source = "roster", disputed = false, reporters = 1,
					reporter = "PRIVATE REPORTER", guid = "Player-PRIVATE", key = "PRIVATE KEY" },
				leader = "PRIVATE LEADER", membersByName = { "PRIVATE MEMBER" }, linkedAlts = 88,
			} },
			summary = { members = 800, linkedAlts = 100 },
			chat = { "PRIVATE CHAT" }, keys = { "PRIVATE KEY" },
		}
	end

	local function With(fn)
		local saved = {
			bridge = OlympusBridge, aggregate = OlympusSiteAggregate, command = OlympusSiteAggregateCommand,
			compat = OlympusSiteAggregateCompatibility196,
			slash = SlashCmdList, slashName = SLASH_OLYMPUSSITEAGGREGATE1,
			frame = CreateFrame, inGuild = IsInGuild, guild = GetGuildInfo, server = GetServerTime,
			chat = DEFAULT_CHAT_FRAME,
		}
		local state = { now = 1900000000, guild = "Olympus II", inGuild = true, messages = {}, bridgeCalls = 0,
			slash = {} }
		state.checkpoint = Base(state.now)
		local onEvent, events, frame = nil, {}, nil
		OlympusSiteAggregate = nil
		OlympusSiteAggregateCommand = nil
		OlympusSiteAggregateCompatibility196 = nil
		SlashCmdList, SLASH_OLYMPUSSITEAGGREGATE1 = state.slash, nil
		CreateFrame = function()
			frame = {
				RegisterEvent = function(_, event) events[event] = true end,
				UnregisterEvent = function(_, event) events[event] = nil end,
				SetScript = function(_, kind, handler) if kind == "OnEvent" then onEvent = handler end end,
			}
			return frame
		end
		IsInGuild = function() return state.inGuild end
		GetGuildInfo = function(unit) if unit == "player" then return state.guild end end
		GetServerTime = function()
			if state.serverUnavailable then return nil end
			return state.now
		end
		DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) state.messages[#state.messages + 1] = line end }
		OlympusBridge = {
			CENSUS_CHECKPOINT_API_VERSION = 1,
			GetCensusCheckpoint = function()
				state.bridgeCalls = state.bridgeCalls + 1
				if state.bridgeError then error("checkpoint failed") end
				return state.checkpoint
			end,
		}
		local ok, err = pcall(function()
			-- The client's order: the file runs, the previous session's SavedVariables are
			-- restored, then ADDON_LOADED fires for this addon.
			assert(loadfile(FILE))()
			OlympusSiteAggregate = { stale = "must be withdrawn at load" }
			state.restored = OlympusSiteAggregate
			state.onEvent, state.events = function(_, ...) return onEvent(frame, ...) end, events
			state.onEvent(nil, "ADDON_LOADED", "Olympus")
			eq(OlympusSiteAggregate, state.restored, "another addon's load leaves it alone")
			state.onEvent(nil, "ADDON_LOADED", "OlympusSiteAggregate")
			fn(state)
		end)
		OlympusBridge, OlympusSiteAggregate = saved.bridge, saved.aggregate
		OlympusSiteAggregateCommand, OlympusSiteAggregateCompatibility196 = saved.command, saved.compat
		SlashCmdList, SLASH_OLYMPUSSITEAGGREGATE1 = saved.slash, saved.slashName
		CreateFrame, IsInGuild, GetGuildInfo, GetServerTime, DEFAULT_CHAT_FRAME = saved.frame, saved.inGuild, saved.guild, saved.server, saved.chat
		if not ok then error(err, 0) end
	end

	local function Export()
		assert(type(OlympusSiteAggregateCommand) == "function", "the gated slash command target")
		OlympusSiteAggregateCommand("export")
		return OlympusSiteAggregate
	end

	local function Contains(value, needle, seen)
		if type(value) == "string" then return value:find(needle, 1, true) ~= nil end
		if type(value) ~= "table" then return false end
		seen = seen or {}
		if seen[value] then return false end
		seen[value] = true
		for key, item in pairs(value) do
			if Contains(key, needle, seen) or Contains(item, needle, seen) then return true end
		end
		return false
	end

	test("site aggregate: only an explicit export writes a fresh server-clock own-roster allowlist", function()
		With(function(s)
			eq(OlympusSiteAggregate, nil, "a prior session's value is withdrawn once its SavedVariables load")
			eq(s.events.ADDON_LOADED, nil, "the load listener is released after its own addon")
			eq(s.bridgeCalls, 0, "loading performs no census read")
			eq(s.slash.OLYMPUSSITEAGGREGATE, nil, "the sidecar cannot bypass Core's gamepad slash gate")
			eq(SLASH_OLYMPUSSITEAGGREGATE1, nil, "Core alone owns the compatibility alias")
			eq(OlympusSiteAggregateCompatibility196, nil, "Prepare is not exposed to another addon")
			OlympusSiteAggregateCommand("")
			eq(OlympusSiteAggregate, nil); eq(s.bridgeCalls, 0, "help does not prepare")
			local out = assert(Export())
			eq(s.bridgeCalls, 1)
			eq(out.schema, "olympus-site-aggregate"); eq(out.version, 1); eq(out.producer, "1.3.2-site.1")
			eq(out.capturedAt, s.now)
			eq(out.realmGroup, "ClassicBetaPvP+ClassicBetaPvP2"); eq(out.faction, "Alliance")
			eq(out.guild.name, "Olympus II"); eq(out.guild.observedAt, s.now - 10)
			eq(out.guild.characters, 900); eq(out.guild.online, 200)
			-- The fixed .198 parser requires exactly these seven keys and producer. In particular,
			-- expiry is enforced by its source-age/review lifecycle, not an additive root field.
			local rootKeys = { schema = true, version = true, producer = true, capturedAt = true,
				realmGroup = true, faction = true, guild = true }
			for key in pairs(out) do assert(rootKeys[key], "unexpected root key " .. tostring(key)) end
			local guildKeys = { name = true, observedAt = true, characters = true, online = true }
			for key in pairs(out.guild) do assert(guildKeys[key], "unexpected guild key " .. tostring(key)) end
			for _, secret in ipairs({ "PRIVATE REPORTER", "Player-PRIVATE", "PRIVATE KEY", "PRIVATE LEADER",
				"PRIVATE MEMBER", "PRIVATE CHAT" }) do
				assert(not Contains(out, secret), "export leaked " .. secret)
			end
			assert(s.messages[#s.messages]:find("Nothing was uploaded", 1, true), "the result says it stayed local")
		end)
	end)

	test("site aggregate: positive counts and complementary remainders below five are masked before SavedVariables", function()
		With(function(s)
			local row = s.checkpoint.guilds[1]
			local cases = {
				{ 4, 4, "few", "unavailable" },
				{ 6, 2, 6, "unavailable" },
				{ 10, 3, 10, "few" },
				{ 10, 8, 10, "unavailable" },
				{ 10, 0, 10, 0 },
				{ 10, 5, 10, 5 },
				{ 10, 10, 10, 10 },
			}
			for _, c in ipairs(cases) do
				row.members, row.online = c[1], c[2]
				local out = assert(Export())
				eq(out.guild.characters, c[3], "characters for " .. c[1] .. "/" .. c[2])
				eq(out.guild.online, c[4], "online for " .. c[1] .. "/" .. c[2])
			end
		end)
	end)

	test("site aggregate: stale, local-clock, relayed, disputed and malformed sources fail closed and erase an armed value", function()
		local function Refused(change, label)
			With(function(s)
				change(s, s.checkpoint.guilds[1])
				OlympusSiteAggregate = { armed = true }
				eq(Export(), nil, label)
			end)
		end
		Refused(function(s) s.serverUnavailable = true end, "server clock missing")
		Refused(function(s) s.checkpoint.timeSource = "local"; s.checkpoint.capturedAtServer = nil end, "local checkpoint")
		Refused(function(s) s.checkpoint.capturedAtServer = s.now - 61 end, "stale checkpoint")
		Refused(function(s) s.checkpoint.capturedAtServer = s.now + 1 end, "future checkpoint")
		Refused(function(s, row)
			s.checkpoint.capturedAtServer = s.now - 1
			row.observedAtServer = s.now
		end, "observation after checkpoint")
		Refused(function(s, row) row.observedAtServer = s.now - 901 end, "stale roster")
		Refused(function(_, row) row.provenance.source = "relay" end, "relay")
		Refused(function(_, row) row.provenance.disputed = true end, "dispute")
		Refused(function(_, row) row.fresh = false end, "not fresh")
		Refused(function(_, row) row.counted = false end, "not counted")
		Refused(function(_, row) row.online = row.members + 1 end, "bad counts")
		Refused(function(_, row) row.members, row.online = 0, 0 end, "empty own roster")
		Refused(function(s) s.checkpoint.scope.faction = "Horde" end, "wrong faction")
		With(function(s)
			s.checkpoint.scope.faction = "Horde"
			eq(Export(), nil)
			assert(s.messages[#s.messages]:find("Only the Alliance Olympus", 1, true), "a Horde guild is told why")
		end)
		Refused(function(s) s.checkpoint.scope.realmGroup = "bad|group" end, "bad scope")
		Refused(function(s) s.checkpoint.guilds[2] = s.checkpoint.guilds[1] end, "duplicate own row")
		Refused(function(s) s.bridgeError = true end, "bridge error")
		Refused(function(s) s.inGuild = false end, "not in a guild")
		Refused(function(s) s.guild = "Other Guild" end, "not an exact allowed guild")
	end)

	test("site aggregate: exact guild scope is canonical, and a guild change withdraws the pending export", function()
		With(function(s)
			s.guild = "OLYMPUS II"
			local out = assert(Export())
			eq(out.guild.name, "Olympus II")
			assert(s.events.PLAYER_GUILD_UPDATE and s.events.GUILD_ROSTER_UPDATE, "membership events registered")
			s.onEvent(nil, "GUILD_ROSTER_UPDATE")
			assert(OlympusSiteAggregate, "a same-guild roster refresh keeps it")
			s.guild = "Olympus III"
			s.onEvent(nil, "PLAYER_GUILD_UPDATE")
			eq(OlympusSiteAggregate, nil, "a changed guild withdraws it")
			assert(s.messages[#s.messages]:find("guild changed", 1, true))
		end)
	end)

	test("site aggregate: clear is explicit and no other command creates or uploads a value", function()
		With(function(s)
			assert(Export())
			OlympusSiteAggregateCommand("clear")
			eq(OlympusSiteAggregate, nil)
			local calls = s.bridgeCalls
			OlympusSiteAggregateCommand("publish")
			eq(OlympusSiteAggregate, nil); eq(s.bridgeCalls, calls, "unknown commands do no work")
		end)
	end)
