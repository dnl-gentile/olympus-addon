-- The census ask (CG~<v>~Q~...) is the recovery path: a client whose snapshot went stale asks,
-- and whoever holds a fuller census answers with one. AnswerAsk's throttle, GLOBAL_ANSWER_GAP
-- (180 s), was keyed to globalLastSent -- which a relay's own periodic broadcast also stamps,
-- every Relay.GLOBAL_EVERY (120 s). 120 < 180, so on a relay the gate never opened: no relay
-- could ever answer an ask, the member-answer path is not fanned out on Forever (Relay.NO_FORWARD
-- holds CG), and a client that fell behind stayed behind. Measured on live 1.5.4: 170 rows, one
-- sender, nothing newer than 27 h, and "census asked 2 ... answered 0" in /oly bug.
local ns, test, eq, extra = ...

test("a relay answers a census ask while its own broadcast cadence is running", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end

		local O, deliver, sent, _, pump = extra.RelayWorld("Relayone Signed-Realm", "Olympus II")
		local relay = O.Relay.Pick()
		deliver("WHISPER", relay .. "-Realm", "RY~")
		O.group, O.faction, O.db = "ForeverPvE", "Alliance", {}
		O.rdb.guilds, O.rdb.seen = {}, {}
		O.Church = { IsLedgerRelay = function() return true end } -- this client is a signed relay
		O.QuietPresence = function() return false end
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", O)
		O.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, t = O.clock, from = "CAMWOWUS1Realm7PvE" }

		local function Snapshots(since)
			local n = 0
			for i = (since or 0) + 1, #sent do
				local m = sent[i].msg
				if m:find("CG~", 1, true) and m:find("~S~", 1, true) then n = n + 1 end
			end
			return n
		end

		-- The relay's own fan-out, as Relay.SendGlobal drives it every GLOBAL_EVERY.
		assert(O.Data.SendGlobalCensus(), "the relay broadcasts its snapshot")
		pump(100)
		assert(Snapshots() > 0, "the broadcast leaves the client")
		local before = #sent

		-- Two minutes on -- inside GLOBAL_ANSWER_GAP, and exactly where the next broadcast falls
		-- due -- a client whose own census is empty asks for one.
		O.clock = O.clock + O.Relay.GLOBAL_EVERY

		local later, realAfter = {}, O.After
		O.After = function(_, _, fn) later[#later + 1] = fn end
		O.Data.ReceiveGlobalCensus("CHANNEL", "Behind Client-Realm",
			("CG~%d~Q~%d~0~0"):format(O.Data.GLOBAL_PROTOCOL, math.floor(O.clock)))
		O.After = realAfter

		eq(#later, 1, "the ask is taken and an answer scheduled")
		later[1]()
		pump(100)
		assert(Snapshots(before) > 0,
			"a relay must answer a census ask: the gap throttles answers, not the broadcast cadence")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo =
		saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

-- The throttle must still hold: a second ask moments after an answer is not answered again.
test("a relay does not answer a second ask inside GLOBAL_ANSWER_GAP", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end

		local O, deliver, sent, _, pump = extra.RelayWorld("Relaytwo Signed-Realm", "Olympus II")
		local relay = O.Relay.Pick()
		deliver("WHISPER", relay .. "-Realm", "RY~")
		O.group, O.faction, O.db = "ForeverPvE", "Alliance", {}
		O.rdb.guilds, O.rdb.seen = {}, {}
		O.Church = { IsLedgerRelay = function() return true end }
		O.QuietPresence = function() return false end
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", O)
		O.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, t = O.clock, from = "CAMWOWUS1Realm7PvE" }

		local function Ask()
			local later, realAfter = {}, O.After
			O.After = function(_, _, fn) later[#later + 1] = fn end
			O.Data.ReceiveGlobalCensus("CHANNEL", "Behind Client-Realm",
				("CG~%d~Q~%d~0~0"):format(O.Data.GLOBAL_PROTOCOL, math.floor(O.clock)))
			O.After = realAfter
			for _, fn in ipairs(later) do fn() end
			pump(100)
			return #later
		end

		eq(Ask(), 1, "the first ask is answered")
		O.clock = O.clock + 10
		eq(Ask(), 0, "a second ask ten seconds later is thrown away by the gap")
		O.clock = O.clock + O.Data.GLOBAL_ANSWER_GAP
		eq(Ask(), 1, "past the gap the recovery path opens again")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo =
		saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)
