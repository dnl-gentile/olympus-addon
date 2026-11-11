-- 1.5.5 (the dev, 2026-11-10: "only half the chat messages arrive"): every Olympus chat line reaches
-- every member once, through a busy relay, under any of a guildmate's stamps, and a secret chat
-- event never errors. Forged lines are still dropped.
local ns, test, eq, extra = ...

-- A relay with `n` reporters registered (each its own guild), its clock and timers run by hand.
local function BusyRelay(n)
	local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
	local timers = {}
	R.After = function(_, _, fn) timers[#timers + 1] = fn end
	for i = 1, n do
		R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
	end
	-- (`each`, when given, after every pump.)
	local function Run(pumps, each)
		for _ = 1, pumps do
			R.clock = R.clock + 1.2 -- (one pump each SEND_INTERVAL)
			R.Comm.Pump()
			local due = timers; timers = {}
			for _, fn in ipairs(due) do fn() end
			if each then each() end
		end
	end
	return R, sent, Run
end

-- The test lines: line k, by the speaker k, as the relay takes it in.
local function Line(k) return ("M1~A~Olympus Guild%d~%d~WA~hello army, line %d"):format(k, 100 + k, k) end
local function Say(R, k) R.Relay.HandleIn("WHISPER", ("Speaker Number%d-CAMWOWUS2Realm3PvE"):format(k), "RL~L~" .. Line(k)) end

-- The chat lines (M1 bodies) each reporter was whispered, by reporter number.
local function LinesByReporter(R, sent, n)
	local got = {}
	for i = 1, n do got[i] = {} end
	for _, s in ipairs(sent) do
		local i = s.target and tonumber(s.target:match("^Rep Number(%d+)"))
		local body = i and s.msg:match("^RM~L~[^~]+~(M1~.*)$")
		if body then got[i][body] = (got[i][body] or 0) + 1 end
	end
	return got
end

local function WithMember(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		fn()
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end

-- (The check of the lane: this test's title said the census words keep coming, and nothing looked.
-- They did not: the lane's burst of 60 took every whisper for its first minute and a half.)
test("chat delivery (1.5.5): a burst of Olympus chat lines through a relay with 46 reporters reaches every reporter, each line once, while census words keep their share of the relay's whispers", function()
	WithMember(function()
		local n = 46
		local R, sent, Run = BusyRelay(n)
		-- The census words sent to reporters while chat lines still waited in the lane, and how long.
		local census, waited, seen = 0, 0, 0
		local function Watch()
			local busy = R.Relay.ChatWaiting() > 0
			if busy then waited = waited + 1.2 end
			for i = seen + 1, #sent do
				if busy and sent[i].msg:find("^RM~P~[^~]+~X1~") then census = census + 1 end
			end
			seen = #sent
		end
		for k = 1, 4 do
			Say(R, k)
			-- Other clients' census words between the lines (the trickle's, keyed: a newer one replaces).
			R.Relay.HandleIn("WHISPER", ("Reporter Census%d-CAMWOWUS2Realm5PvE"):format(k), ("RL~P~X1~census %d"):format(k))
			Run(2, Watch)
		end
		Run(3000, Watch)
		local got = LinesByReporter(R, sent, n)
		local missing, twice = 0, 0
		for i = 1, n do
			for k = 1, 4 do
				local c = got[i][Line(k)] or 0
				if c == 0 then missing = missing + 1 elseif c > 1 then twice = twice + 1 end
			end
		end
		eq(missing, 0, "no chat line lost for any reporter's guild")
		eq(twice, 0, "and none sent twice")
		-- The relay sends PUMP_PARTS_RELAY whispers a pump (200 a minute); the lane takes CHAT_PER_MIN.
		local share = R.Comm.PUMP_PARTS_RELAY * 60 / 1.2 - R.Relay.CHAT_PER_MIN
		assert(waited >= 30, "the burst kept the lane busy a while: " .. waited)
		assert(census >= math.floor(waited / 60 * share / 2),
			("census words kept at least half their %d a minute while chat waited: %d in %ds"):format(share, census, waited))
	end)
end)

-- (The check of the lane: a whisper waits in the lane up to CHAT_LANE_TTL, and was sent to whom it was
-- queued for whatever happened meanwhile.)
test("chat delivery (1.5.5): a waiting chat whisper goes to its guild's reporter as the relay holds him when it is sent: none to one quarantined, denied or expired meanwhile, the guildmate who took a reporter's place gets it, our own client hands it to the guild, none to a relay left out; skipped, never lost", function()
	WithMember(function()
		local n = 12
		local R, sent, Run = BusyRelay(n)
		-- Every registration renewed but Rep Number12's: his runs out (REPORTER_FOR) a second after the
		-- lines come, before the second goes.
		R.clock = R.clock + R.Relay.REPORTER_FOR - 1
		for i = 1, n - 1 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		-- In the mesh, the other signed relay answers and joins before chat crosses (RX).
		local other = "Max Ran-CAMWOWUS2Realm1PvE"
		R.Relay.HandleAck("WHISPER", other, "RY~")
		eq(R.Relay.HandleMesh("WHISPER", other, "RJ~1~0~0"), true, "the other relay joined")
		eq(R.Relay.MeshPeer(other), true, "a live mesh peer before the lines queue")
		for k = 1, 6 do Say(R, k) end
		local before = #sent
		assert(R.Relay.ChatWaiting() >= 5 * (n + 1), "lines 2 to 6 wait in the lane: " .. R.Relay.ChatWaiting())
		-- Meanwhile (the lines after the first still waiting): Rep Number1 marked a modified build, Rep
		-- Number2 denied, Guild 3's reporter now a guildmate, Guild 4's our own client, the other
		-- relay offline (the server's word).
		R.Builds = { Quarantined = function(name) return ns.ShortName(name) == "Rep Number1" end }
		R.Relay.SetDenied({ ["rep number2"] = true })
		R.Relay.HandleIn("WHISPER", "Rep Guildmate-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild 3")
		R.Relay.HandleIn("WHISPER", "Hildryn Payne-CAMWOWUS2Realm1PvE", "RL~P~RR~Guild 4")
		R.Relay.LeaveOut("Max Ran", "offline")
		Run(400)
		eq(R.Relay.ChatWaiting(), 0)
		-- What lines 2 to 6 became, by addressee.
		local to, guild = {}, 0
		for i = before + 1, #sent do
			local s = sent[i]
			local k = tonumber(s.msg:match("^R[MXG]~L~[^~]+~M1~A~Olympus Guild(%d+)~"))
			if k and k >= 2 then
				if s.dist == "GUILD" then guild = guild + 1
				else
					local who = ns.ShortName(s.target)
					to[who] = (to[who] or 0) + 1
				end
			end
		end
		eq(to["Rep Number1"], nil, "none to a reporter quarantined meanwhile")
		eq(to["Rep Number2"], nil, "none to one denied meanwhile")
		eq(to["Rep Number3"], nil); eq(to["Rep Guildmate"], 5, "his guild's new reporter: each line once")
		eq(to["Rep Number4"], nil); eq(guild, 5, "our own client its guild's reporter now: each line handed to the guild once")
		eq(to["Rep Number12"], nil, "none to one whose registration ran out")
		eq(to["Max Ran"], nil, "none across to a relay left out")
		for i = 5, n - 1 do eq(to["Rep Number" .. i], 5, "Rep Number" .. i .. ": each line once") end
		eq(R.Relay.Stats().chatLost, 0, "nothing counted lost")
		assert(R.Relay.Stats().chatSkipped >= 4 * 5, "skipped and counted: " .. R.Relay.Stats().chatSkipped)
	end)
end)

-- (The check of the lane: an error in there left it feeding for good, every later word stopped.)
test("chat delivery (1.5.5): a whisper whose send throws is lost alone and counted; the lane goes on and the next line reaches every reporter", function()
	local savedCapture = ns.CaptureError
	local errors = {}
	local ok, err = pcall(function()
		ns.CaptureError = function(where, e) errors[#errors + 1] = where .. ": " .. tostring(e) end
		WithMember(function()
			local n = 12
			local R, sent, Run = BusyRelay(n)
			local whisper, throws = R.Comm.Whisper, 0
			R.Comm.Whisper = function(...)
				if throws < R.Relay.CHAT_INFLIGHT + 2 then
					throws = throws + 1
					error("a send that throws")
				end
				return whisper(...)
			end
			for k = 1, 3 do pcall(Say, R, k) end
			Run(300)
			eq(throws, R.Relay.CHAT_INFLIGHT + 2)
			local got, delivered = LinesByReporter(R, sent, n), 0
			for i = 1, n do
				for k = 1, 3 do
					local c = got[i][Line(k)] or 0
					delivered = delivered + c
					assert(c <= 1, "none twice")
				end
			end
			eq(delivered, 3 * n - throws, "every whisper but those that threw")
			eq(R.Relay.Stats().chatLost, throws, "those counted lost")
			eq(R.Relay.ChatWaiting(), 0, "nothing left waiting")
			Say(R, 4)
			Run(100)
			got = LinesByReporter(R, sent, n)
			for i = 1, n do eq(got[i][Line(4)], 1, "the next line reaches Rep Number" .. i) end
			assert(#errors >= throws, "each error captured: " .. #errors)
		end)
	end)
	ns.CaptureError = savedCapture
	if not ok then error(err, 0) end
end)

-- (The check of the lane: the author's relay has 92 reporters, not the 46 its numbers were made for.)
test("chat delivery (1.5.5): at 92 reporters, ten lines at once: the first eight reach every reporter, the ninth is the first to wait past CHAT_LANE_TTL; every whisper is sent once or counted lost, none late", function()
	WithMember(function()
		local n = 92
		local R, sent, Run = BusyRelay(n)
		local t0, most, late, seen = R.clock, 0, 0, 0
		local function Watch()
			most = math.max(most, R.Relay.ChatWaiting())
			for i = seen + 1, #sent do
				-- (Each pump hands Comm at most CHAT_INFLIGHT more: they leave within two pumps.)
				if sent[i].msg:find("^RM~L~") and R.clock - t0 > R.Relay.CHAT_LANE_TTL + 2.4 then late = late + 1 end
			end
			seen = #sent
		end
		for k = 1, 10 do Say(R, k) end
		Run(3000, Watch)
		local got = LinesByReporter(R, sent, n)
		local count, delivered = {}, 0
		for k = 1, 10 do
			count[k] = 0
			for i = 1, n do
				local c = got[i][Line(k)] or 0
				assert(c <= 1, "none twice")
				count[k] = count[k] + c
			end
			delivered = delivered + count[k]
		end
		for k = 1, 8 do eq(count[k], n, "line " .. k .. " reached every reporter") end
		assert(count[9] < n, "the ninth line waited past CHAT_LANE_TTL: " .. count[9])
		eq(delivered + R.Relay.Stats().chatLost, 10 * n, "each whisper sent once or counted lost")
		eq(late, 0, "none sent after CHAT_LANE_TTL")
		assert(most >= 8 * n, "the waiting count grows in a burst (/oly status): " .. most)
	end)
end)

test("chat delivery (1.5.5): a reporter whose queue is full of other words still hands every relayed chat line to its guild", function()
	WithMember(function()
		local R, _, sent = extra.RelayWorld("Plain Reporter-CAMWOWUS2Realm7PvE", "Olympus II")
		-- The reporter's queue full of ordinary words (its guild's own, the relay's census trickle).
		for i = 1, R.Comm.MAX_QUEUE - 1 do R.Comm.Send("GUILD", ("X1~word %d"):format(i), nil, false) end
		local line = "M1~A~Olympus Dawn~7~WA~can anyone hear me"
		R.Relay.HandleRelayed("WHISPER", "Max Ran-CAMWOWUS2Realm1PvE", "RM~L~Speaker Far-CAMWOWUS2Realm3PvE~" .. line)
		-- More words after it, every one ordinary: a full queue pushes out its oldest waiting ones.
		for i = 1, R.Comm.MAX_QUEUE do R.Comm.Send("GUILD", ("X1~later %d"):format(i), nil, false) end
		for _ = 1, 400 do R.Comm.Pump() end
		local handed = 0
		for _, s in ipairs(sent) do
			if s.dist == "GUILD" and s.msg == "RG~L~Speaker Far-CAMWOWUS2Realm3PvE~" .. line then handed = handed + 1 end
		end
		eq(handed, 1, "the chat line reached the guild, once")
	end)
end)

-- The addon's own event dispatcher (Core.lua), found by a probe: no other frame's.
local function Dispatcher(probeEvent)
	local hit = false
	ns.RegisterEvent(probeEvent, function() hit = true end)
	for _, f in ipairs(EVENT_SCRIPTS) do
		hit = false
		pcall(f, nil, probeEvent, "probe", "Probe-Realm")
		if hit then return f end
	end
	error("no dispatcher")
end

-- A value the game marks secret: anything done with it but passing it on errors.
local function Secret()
	return setmetatable({}, { __index = function() error("a secret value was read") end,
		__len = function() error("a secret value was measured") end, __eq = function() error("a secret value was compared") end })
end

-- (The check of the 1.5.5 chat lane: a secret field after the second once reached the handlers as
-- nil. Now no field of a chat event with a secret one reaches them.)
test("chat delivery (1.5.5): a chat event with any secret field (its text, its sender, a GUID, a channel's name) reaches no handler, counted; a plain one as it came", function()
	local savedSecret, savedCapture = rawget(_G, "issecretvalue"), ns.CaptureError
	local ok, err = pcall(function()
		local dispatch = Dispatcher("CHAT_MSG_OLYMPUS_TEST")
		local secret = Secret()
		issecretvalue = function(v) return rawequal(v, secret) end
		local errors = {}
		ns.CaptureError = function(where, e) errors[#errors + 1] = where .. ": " .. tostring(e) end
		local calls = {}
		ns.RegisterEvent("CHAT_MSG_OLYMPUS_TEST", function(...) calls[#calls + 1] = { n = select("#", ...), ... } end)
		local before = ns.secretChatSkipped
		dispatch(nil, "CHAT_MSG_OLYMPUS_TEST", secret, "Some One-Realm", "", "", "", "", 0, 6, "OlympusNet2")
		dispatch(nil, "CHAT_MSG_OLYMPUS_TEST", "hello", secret, "", "", "", "", 0, 6, "OlympusNet2")
		eq(#calls, 0, "a secret text or sender: no handler called")
		eq(ns.secretChatSkipped - before, 2, "counted for /oly status")
		dispatch(nil, "CHAT_MSG_OLYMPUS_TEST", "hello", "Some One-Realm", "", "", "", "", 0, 6, secret, 0, secret)
		eq(#calls, 0, "a secret GUID or channel name: no handler called either, never the field as nil")
		eq(ns.secretChatSkipped - before, 3)
		dispatch(nil, "CHAT_MSG_OLYMPUS_TEST", "plain", "Some One-Realm", "x")
		eq(#calls, 1); eq(calls[1][1], "plain"); eq(calls[1][3], "x"); eq(calls[1].n, 3)
		-- The game's own non-chat events are passed as they come (a secret there is the handler's).
		local other = {}
		ns.RegisterEvent("OLYMPUS_TEST_OTHER", function(a) other[#other + 1] = a end)
		dispatch(nil, "OLYMPUS_TEST_OTHER", secret)
		eq(#other, 1)
		eq(#errors, 0, table.concat(errors, "; "))
	end)
	issecretvalue, ns.CaptureError = savedSecret, savedCapture
	if not ok then error(err, 0) end
end)

-- (The check of the 1.5.5 chat lane, blocking.) An outsider's word on another channel we sit in:
-- Comm's OnAddonMessage drops it by its channel number (field 7) and lets a word with no number
-- through. A secret number once reached it as nil, and the word passed as one from our channel.
test("chat delivery (1.5.5): an addon word whose channel number (field 7) is secret reaches no handler, logged or not, counted; with a plain number it comes as it was", function()
	local savedSecret, savedCapture = rawget(_G, "issecretvalue"), ns.CaptureError
	local probing, words = true, {}
	local ok, err = pcall(function()
		local dispatch = Dispatcher("CHAT_MSG_OLYMPUS_TEST")
		local secret = Secret()
		issecretvalue = function(v) return rawequal(v, secret) end
		local errors = {}
		ns.CaptureError = function(where, e) errors[#errors + 1] = where .. ": " .. tostring(e) end
		local function Probe(...) if probing then words[#words + 1] = { n = select("#", ...), ... } end end
		ns.RegisterEvent("CHAT_MSG_ADDON", Probe)
		ns.RegisterEvent("CHAT_MSG_ADDON_LOGGED", Probe)
		local before = ns.secretChatSkipped
		-- (prefix, text, channel, sender, target, zoneChannelID, localID, channelName)
		dispatch(nil, "CHAT_MSG_ADDON", ns.PREFIX, "X1~from another channel", "CHANNEL", "Out Sider-Realm", "", 0, secret, "Trade")
		dispatch(nil, "CHAT_MSG_ADDON_LOGGED", ns.PREFIX, "M1~A~Olympus II~1~~hi", "CHANNEL", "Out Sider-Realm", "", 0, secret, "Trade")
		eq(#words, 0, "no handler called: never taken as a word from our channel")
		eq(ns.secretChatSkipped - before, 2, "both counted")
		dispatch(nil, "CHAT_MSG_ADDON", "SOMEADDON", "plain words", "CHANNEL", "Out Sider-Realm", "", 0, 9, "Trade")
		eq(#words, 1); eq(words[1][2], "plain words"); eq(words[1][7], 9, "its number as it came"); eq(words[1].n, 8)
		eq(#errors, 0, table.concat(errors, "; "))
	end)
	probing = false
	issecretvalue, ns.CaptureError = savedSecret, savedCapture
	if not ok then error(err, 0) end
end)

test("chat delivery (1.5.5): the relay's readers of the server's \"No player named\" line leave a secret one unread", function()
	local savedSecret, savedNotFound = rawget(_G, "issecretvalue"), ERR_CHAT_PLAYER_NOT_FOUND_S
	WithMember(function()
		local R = extra.RelayWorld("Plain Reporter-CAMWOWUS2Realm7PvE", "Olympus II")
		ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
		local line = ERR_CHAT_PLAYER_NOT_FOUND_S:format("Max Ran")
		eq(R.Relay.QuietLine(nil, "CHAT_MSG_SYSTEM", line), true, "a plain line for a relay: kept out of the chat")
		local checked = 0
		local ok, err = pcall(function()
			issecretvalue = function(v) if v == line then checked = checked + 1 return true end return false end
			eq(R.Relay.QuietLine(nil, "CHAT_MSG_SYSTEM", line), false, "a secret one: not read, the chat frame shows it as the game's own")
			eq(R.Relay.NotFound(line), false, "not read: no relay left out")
			assert(checked >= 2, "checked for secrecy first: " .. checked)
			issecretvalue = savedSecret
			eq(R.Relay.NotFound(line), true, "the plain line still leaves an offline relay out")
		end)
		issecretvalue, ERR_CHAT_PLAYER_NOT_FOUND_S = savedSecret, savedNotFound
		if not ok then error(err, 0) end
	end)
end)

-- Our guild on Forever: the roster names every member bare, each plays on a sub-realm of his own.
local function ForeverGuild(fn)
	local saved = { total = GetNumGuildMembers, info = GetGuildRosterInfo, guild = GetGuildInfo, member = ns.IsMember,
		realm = ns.realm, group = ns.group, me = ns.me, split = ns.splitNames, chat = ns.db.addonChat, mute = ns.db.chatMute,
		history = ns.rdb.chat }
	local ok, err = pcall(function()
		ns.realm, ns.group, ns.splitNames = "CAMWOWUS2Realm1PvE", "ForeverPvE", true
		ns.me = "Wazizo Thelongone-CAMWOWUS2Realm1PvE"
		ns.IsMember = function() return true end
		GetGuildInfo = function() return "OLYMPUS GODS", "Member", 3 end
		local rows = { { "Wazizo Thelongone", "Member", 3 }, { "Hater Fistinator", "Officer", 1 }, { "Quiet Member", "Member", 3 } }
		GetNumGuildMembers = function() return #rows, #rows end
		GetGuildRosterInfo = function(i)
			local r = rows[i]
			if r then return r[1], r[2], r[3], 60, "Warrior", "Stormwind City", "", "", true, 0, "WARRIOR" end
		end
		ns.Roster.Scan()
		ns.db.addonChat, ns.db.chatMute = true, { A = true } -- (muted: each line kept in the history alone)
		fn()
	end)
	GetNumGuildMembers, GetGuildRosterInfo, GetGuildInfo, ns.IsMember = saved.total, saved.info, saved.guild, saved.member
	ns.realm, ns.group, ns.me, ns.splitNames = saved.realm, saved.group, saved.me, saved.split
	ns.db.addonChat, ns.db.chatMute, ns.rdb.chat = saved.chat, saved.mute, saved.history
	ns.Roster.Scan()
	if not ok then error(err, 0) end
end

test("chat delivery (1.5.5, Forever): guildmates on other sub-realms and under their plain names are shown, one line once under any stamp, our own line once; a same-family stranger claiming our guild is still forged", function()
	ForeverGuild(function()
		local C, Codec = ns.Channels, ns.Codec
		local function Line(id, text) return Codec.EncodeChat("A", "OLYMPUS GODS", id, "WA", text) end
		local function Stat(k) return C.Stats()[k] or 0 end
		local forged, dup = Stat("forged"), Stat("dup")
		-- A player's /oly bug of 2026-11-10 (1.5.3): guildmates' lines "dropped: forged", one of them
		-- under two sub-realm stamps a minute apart.
		local _, why = C.Receive("CHANNEL", "Hater Fistinator-CAMWOWUS1Realm5PvE", Line(4101, "first line from the officer"), 7000)
		eq(why, "muted", "a guildmate stamped with another sub-realm of our family: taken")
		_, why = C.Receive("CHANNEL", "Hater Fistinator-CAMWOWUS2Realm3PvE", Line(4101, "first line from the officer"), 7001)
		eq(why, "dup", "the same line under the relay's stamp: once")
		_, why = C.Receive("CHANNEL", "Hater Fistinator", Line(4101, "first line from the officer"), 7002)
		eq(why, "dup", "and under his plain name: once")
		_, why = C.Receive("CHANNEL", "Quiet Member", Line(4102, "plain name line"), 7003)
		eq(why, "muted", "a guildmate by his plain name: taken")
		_, why = C.Receive("CHANNEL", "Quiet Member-CAMWOWUS1Realm7PvE", Line(4103, "next line"), 7004)
		eq(why, "muted", "his next line under a sub-realm stamp: taken")
		eq(Stat("forged") - forged, 0, "none of them forged")
		-- A same-family impostor still fails our own roster check.
		_, why = C.Receive("CHANNEL", "Fake Officer-CAMWOWUS1Realm5PvE", Line(4104, "I speak for your guild"), 7005)
		eq(why, "forged", "a name our roster does not hold")
		-- Another ruleset's public chat is admitted as an unverified member. Our officer's
		-- name on that family keeps its own identity and inherits none of our roster's rank.
		local foreign = "Hater Fistinator-CAMWOWUS1Realm8PvP"
		local level, verified = C.VerifiedLevel(foreign, "OLYMPUS GODS")
		eq(level, 1); eq(verified, false)
		_, why = C.Receive("CHANNEL", foreign, Line(4105, "from the PvP family"), 7006)
		eq(why, "muted", "another ruleset's public line is admitted and follows this window's mute choice")
		eq(Stat("forged") - forged, 1, "the same-family impostor alone is forged")
		eq(Stat("dup") - dup, 2)
		-- Our own line coming back by the relay under another sub-realm's stamp: shown once, when sent.
		local mine = { ["4106#my own words"] = 7007 }
		local ok, reason = C.Admit("Wazizo Thelongone-CAMWOWUS1Realm5PvE", "OLYMPUS GODS", "my own words", 7008,
			{ tier = "A", id = 4106, mine = mine, seen = {}, buckets = {} })
		eq(ok, false); eq(reason, "own", "our own echo under another stamp")
		eq(C.IsMe("Wazizo Thelongone-CAMWOWUS2Realm7PvE"), true)
		eq(C.IsMe("Wazizo Thelongone-CAMWOWUS1Realm8PvP"), false, "a namesake of another family is not us")
	end)
end)

test("chat guild verification can look up a sender without writing a guild claim", function()
	ForeverGuild(function()
		local name, guild = "Readonly Sender-CAMWOWUS1Realm7PvE", "Olympus Other"
		eq(ns.Data.ClaimedGuild(name), nil)
		local _, verified = ns.Channels.VerifiedLevel(name, guild, true)
		eq(verified, false)
		eq(ns.Data.ClaimedGuild(name), nil, "checking an unverified request must not bind the sender")
	end)
end)

test("chat delivery (1.5.5): /oly status names the chat windows open beside the ones chosen, so a window \"gone\" can be told apart from one never made", function()
	local saved = { frame = rawget(_G, "ChatFrame3"), info = rawget(_G, "GetChatWindowInfo"), windows = ns.db.chatWindows }
	local ok, err = pcall(function()
		ChatFrame3 = { AddMessage = function() end }
		GetChatWindowInfo = function(i) if i == 3 then return "Trade", 14, 1, 1, 1, 1, true end end
		ns.db.chatWindows = { [ns.me] = { A = "Olympus", C = "Olympus", L = "Olympus" } }
		local line = ns.StatusText():match("chat windows:[^\n]*") or ""
		assert(line:find('[Olympus] "Olympus" ' .. ns.L.CHATWIN_GONE_TAG, 1, true), line)
		assert(line:find('open: "Trade"', 1, true), line)
		ChatFrame3 = nil
		line = ns.StatusText():match("chat windows:[^\n]*") or ""
		assert(line:find("open: the main one alone", 1, true), line)
	end)
	ChatFrame3, GetChatWindowInfo, ns.db.chatWindows = saved.frame, saved.info, saved.windows
	if not ok then error(err, 0) end
end)

test("chat delivery (1.5.5, Forever): another guild's officer and master speak in [Captains] and [Lords] under any sub-realm stamp; their reporters' stamps give one census picture; a plain member of theirs, or another family's namesake, is still no Captain", function()
	ForeverGuild(function()
		local saved, savedInfo, savedMute = ns.rdb.guilds, GetGuildInfo, ns.db.chatMute
		local ok, err = pcall(function()
			ns.rdb.guilds = {}
			GetGuildInfo = function() return "OLYMPUS GODS", "Master", 0 end -- (we read every channel)
			ns.db.chatMute = { A = true, C = true, L = true }
			local function Rep() return { guild = "Olympus Dawn", total = 40, online = 9, zones = {}, leader = "Dawn Master",
				officers = { { name = "Dawn Officer", online = true, days = 0 } } } end
			-- Its reports reach us stamped with their senders' sub-realms (the relay's copies).
			ns.Data.Receive(Rep(), "Dawn Reporter-CAMWOWUS2Realm3PvE")
			ns.Data.Receive(Rep(), "Dawn Witness-CAMWOWUS1Realm5PvE")
			eq(ns.rdb.guilds["Olympus Dawn"].conflict, nil, "one picture, whatever its senders' stamps")
			eq(ns.Data.KnownRank("Dawn Officer-CAMWOWUS2Realm7PvE", "Olympus Dawn"), 1, "his officer under a third stamp")
			eq(ns.Data.KnownRank("Dawn Master-CAMWOWUS1Realm7PvE", "Olympus Dawn"), 0, "his master too")
			eq(ns.Data.KnownRank("Dawn Officer-CAMWOWUS1Realm8PvP", "Olympus Dawn"), nil, "another family's namesake is nobody there")
			eq(ns.Data.KnownRank("Dawn Member-CAMWOWUS2Realm7PvE", "Olympus Dawn"), nil)
			local C, Codec = ns.Channels, ns.Codec
			local function Line(tier, id, text) return Codec.EncodeChat(tier, "Olympus Dawn", id, "WA", text) end
			local _, why = C.Receive("CHANNEL", "Dawn Officer-CAMWOWUS2Realm7PvE", Line("C", 4201, "captains, to me"), 8000)
			eq(why, "muted", "his [Captains] line taken")
			_, why = C.Receive("CHANNEL", "Dawn Master-CAMWOWUS1Realm7PvE", Line("L", 4202, "lords, to me"), 8010)
			eq(why, "muted", "his master's [Lords] line taken")
			_, why = C.Receive("CHANNEL", "Dawn Member-CAMWOWUS2Realm7PvE", Line("C", 4203, "let me in"), 8020)
			eq(why, "unverified", "a member the census names no officer: not in [Captains]")
			_, why = C.Receive("CHANNEL", "Dawn Officer-CAMWOWUS1Realm8PvP", Line("C", 4204, "me too"), 8030)
			eq(why, "unverified", "another family's namesake: not in [Captains]")
		end)
		ns.rdb.guilds, GetGuildInfo, ns.db.chatMute = saved, savedInfo, savedMute
		if not ok then error(err, 0) end
	end)
end)
