-- 1.5.9 (the author, 2026-11-12: "Tem guildas diferentes que têm canais selados diferentes, você precisa
-- resolver esse problema. Todo mundo tá no mesmo canal, né?"). On WoW: Forever a guild with a realm key
-- sat on its sealed channel ("Oly" and the key's hash, its lane after it) and a client could sit on
-- another lane (OlympusNet7): either way it was deaf to the public first lane, OlympusNet, where the
-- clients still on 1.5.4 or older broadcast their census (two /oly bug reports of 2026-11-12: some 500
-- pieces at a client on the public channel, none at a sealed one on lane 7). There every client now sits
-- on its faction's public first lane, whatever key or lane it holds (Comm.ChannelSpec): no lane move, a
-- hello and /oly status that say so, no chat line typed as text there by a key holder (ChatHall.On), and
-- a key that arrives leaves and joins nothing. The key stays kept, and off Forever nothing changes. Real
-- Comm, Relay and ChatHall; the game's channels are simulated. Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ADDON = assert(extra and extra.addon, "tests/run.lua hands the addon's folder to this file")

local PUBLIC_ID, SEALED_ID, LANE_ID = 7, 6, 8

-- A client with Comm and Relay loaded (names split, the relay on), holding o.key (or none) on o.lane,
-- on Forever unless o.forever is false, joined to the channel its Comm names. The game already has the
-- public first lane, the key's sealed channel (first lane and lane 7) and the public lane 7 joined.
local function WithClient(o, fn)
	local saved = { channel = GetChannelName, join = JoinChannelByName, leave = LeaveChannelByName,
		member = ns.IsMember, info = C_ChatInfo, say = rawget(_G, "SendChatMessage") }
	local ok, err = pcall(function()
		ns.IsMember = function() return true end
		local events, login = {}, {}
		local cns = setmetatable({}, { __index = ns })
		cns.RegisterEvent = function(event, f) events[event] = events[event] or {}; table.insert(events[event], f) end
		cns.On = function(name, f) if name == "LOGIN" then table.insert(login, f) end end
		cns.timers, cns.After, cns.Every = {}, function() end, function(_, name, f) cns.timers[name] = f end
		cns.clock = 100000
		cns.Now = function() return cns.clock end
		cns.me, cns.splitNames, cns.faction = "Sealed Member-Realm", true, "Alliance"
		cns.OnForever = function() return o.forever ~= false end
		cns.db = { blocked = {} }
		cns.rdb = { realmKey = o.key, channelLane = o.lane, council = { names = { ["relay keeper"] = "Relay Keeper" } }, realm = "Realm" }
		cns.KingCharacter, cns.TreasurerPins, cns.AuthorCharacters = function() return nil end, function() return {} end, function() return {} end
		cns.Roster = setmetatable({ RankOf = function(name) return name == "Lord Officer-Realm" and 0 or 5 end }, { __index = ns.Roster })
		local sent, said = {}, {}
		local function Send(_, msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, target = target } return 0 end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = Send, SendAddonMessageLogged = Send }
		SendChatMessage = function(text, kind, _, target) said[#said + 1] = { text = text, kind = kind, target = target } end
		assert(loadfile(ADDON .. "Comm.lua"))("Olympus", cns)
		for _, f in ipairs(login) do f() end
		assert(loadfile(ADDON .. "Relay.lua"))("Olympus", cns)
		cns.Relay.Reset()
		local C = cns.Comm
		local indexes, joined, left = { OlympusNet = PUBLIC_ID, OlympusNet7 = LANE_ID }, {}, {}
		if o.key then indexes["Oly" .. C.Hash36(o.key)], indexes["Oly" .. C.Hash36(o.key) .. "7"] = SEALED_ID, SEALED_ID end
		GetChannelName = function(name) return indexes[name] or 0, name end
		JoinChannelByName = function(name) joined[#joined + 1] = name end
		LeaveChannelByName = function(name) left[#left + 1] = name end
		C.JoinChannel()
		local function Fire(dist, sender, text, localID)
			for _, f in ipairs(events.CHAT_MSG_ADDON) do
				f(ns.PREFIX, text, dist, sender, "", 0, localID, localID and (tostring(localID) .. ". channel") or nil)
			end
		end
		-- The hello this client sends now, as its guildmates read it.
		local function Hello()
			local n = #sent
			C.Hello(true)
			for _ = 1, 40 do if #sent > n then break end C.Pump() end
			for i = #sent, n + 1, -1 do if sent[i].dist == "GUILD" and sent[i].msg:sub(1, 3) == "H1~" then return sent[i].msg end end
			return nil
		end
		fn({ C = C, cns = cns, sent = sent, said = said, joined = joined, left = left, indexes = indexes, Hello = Hello,
			Native = function(localID, sender, text) Fire("CHANNEL", sender, text, localID) end,
			Guild = function(sender, text) Fire("GUILD", sender, text) end })
	end)
	GetChannelName, JoinChannelByName, LeaveChannelByName, ns.IsMember, C_ChatInfo, SendChatMessage =
		saved.channel, saved.join, saved.leave, saved.member, saved.info, saved.say
	if not ok then error(err, 0) end
end

-- A census report (R2) of another guild, in the channel's pieces, as a client on 1.5.4 broadcasts it.
local function ReportPieces(guild, id)
	return ns.Codec.Chunk(ns.Codec.EncodeReport({ guild = guild, total = 980, online = 120, zones = {}, faction = "Alliance" }), id)
end

-- Fails before: the client sat on the key's sealed channel of lane 7 and dropped the report as another
-- channel's (otherChannel 1, reports 0).
test("1.5.9 one channel on Forever: a client holding a realm key on lane 7 sits on the faction's public first lane, unsealed, keeps its key, and takes the census report a 1.5.4 client broadcast there", function()
	WithClient({ key = "fixture-secret", lane = 7 }, function(w)
		local name, password = w.C.ChannelSpec()
		eq(name, "OlympusNet"); eq(password, nil, "no password")
		local st = w.C.Stats()
		eq(st.channelName, "OlympusNet"); eq(st.channel, PUBLIC_ID); eq(st.sealed, false); eq(st.lane, 0)
		eq(st.keyHeld, true)
		eq(w.cns.rdb.realmKey, "fixture-secret", "the key is kept"); eq(w.cns.rdb.channelLane, 7, "and the lane kept")
		eq(w.C.SealedBase(), "Oly" .. w.C.Hash36("fixture-secret"), "the key's own name, for /oly bug to leave out")
		for _, piece in ipairs(ReportPieces("OLYMPUS PRIME", "43")) do w.Native(PUBLIC_ID, "Older Broadcaster-Realm", piece) end
		eq(w.C.Stats().otherChannel, 0, "not dropped as another channel's")
		eq(w.C.Stats().reports, 1, "the census report is taken")
		-- Its hello says what it is on: the public channel, the first lane (no lane field).
		local hello = assert(w.Hello(), "a hello")
		assert(hello:match("^H1~[^~]+~[^~]*~p~~~~R"), hello)
	end)
end)

-- Fails before: a client without a key on lane 7 sat on OlympusNet7 and dropped the report.
test("1.5.9 one channel on Forever: a client without a key on lane 7 sits on the public first lane too, and no lane move takes it elsewhere: the next lane, an officer's hello, a crowd", function()
	WithClient({ lane = 7 }, function(w)
		eq(w.C.ChannelSpec(), "OlympusNet"); eq(w.C.Stats().channel, PUBLIC_ID); eq(w.C.Lane(), 0)
		for _, piece in ipairs(ReportPieces("OLYMPUS PRIME", "44")) do w.Native(PUBLIC_ID, "Older Broadcaster-Realm", piece) end
		eq(w.C.Stats().otherChannel, 0); eq(w.C.Stats().reports, 1)
		eq(w.C.NextLane("refused"), false, "the next lane: none")
		w.Guild("Lord Officer-Realm", "H1~1.4.1~Realm~p~~~L9~R")
		eq(w.C.ChannelSpec(), "OlympusNet", "an officer's hello naming lane 9 moves nobody")
		-- Five guildmates on lane 3 would be a clear crowd off Forever: here none to follow, none to show.
		for i = 1, 5 do w.Guild(("Crowd Peer%d-Realm"):format(i), "H1~1.5.8~Realm~p~~~L3~R~N") end
		w.cns.clock = w.cns.clock + 3600
		eq(w.C.FollowCrowd(), false, "no crowd move")
		local lanes = w.C.LaneStats()
		eq(lanes.lane, 0); eq(lanes.dominant, nil); eq(lanes.mismatch, false, "no lane mismatch shown")
		eq(w.cns.rdb.channelLane, 7, "the lane kept as it was"); eq(#w.left, 0, "no channel left"); eq(#w.joined, 0, "none joined")
		eq(w.C.Stats().channelName, "OlympusNet")
	end)
end)

-- Fails before: the key holder's line went as his own text in the channel he sat on.
test("1.5.9 one channel on Forever: the chat hall is off for a client holding a realm key (its lines go by the relay alone, never as text in the public channel); on for one without, and off Forever with a key as before", function()
	for _, case in ipairs({ { key = "fixture-secret", on = false }, { key = nil, on = true }, { key = "fixture-secret", forever = false, on = true } }) do
		WithClient({ key = case.key, lane = 0, forever = case.forever }, function(w)
			assert(loadfile(ADDON .. "ChatHall.lua"))("Olympus", w.cns)
			local H = w.cns.ChatHall
			local label = ("key %s, %s"):format(tostring(case.key), case.forever == false and "off Forever" or "on Forever")
			eq(H.On(), case.on, label)
			eq(H.Send("M1~A~Olympus Sealed~7~WL~a line"), case.on, label .. ": the line as text")
			eq(#w.said, case.on and 1 or 0, label .. ": what the game was asked to say")
			-- Through Comm.SendChat: the hidden way waits in the chat lane either way.
			eq(w.C.SendChat("M1~A~Olympus Sealed~8~WL~another line"), true, label)
			eq(#w.said, case.on and 2 or 0, label .. ": the text beside it only where the hall is on")
		end)
	end
end)

-- Fails before: an officer's key left the public channel for the sealed one, and the chat lines waiting
-- for the old channel were dropped.
test("1.5.9 one channel on Forever: a realm key that arrives from an officer is kept, and the client stays on the public channel: nothing left, nothing joined, no chat line dropped", function()
	WithClient({ lane = 0 }, function(w)
		eq(w.C.Stats().channelName, "OlympusNet")
		eq(w.C.SendChat("M1~A~Olympus Sealed~9~WL~waiting"), true)
		w.Guild("Lord Officer-Realm", "K1~an-officer-key")
		eq(w.cns.rdb.realmKey, "an-officer-key", "the key is taken")
		eq(w.C.Stats().channelName, "OlympusNet"); eq(w.C.Stats().channel, PUBLIC_ID); eq(w.C.Stats().sealed, false)
		eq(#w.left, 0, "nothing left"); eq(#w.joined, 0, "nothing joined")
		eq(w.C.Stats().chatMoved, 0, "no chat line dropped as moved"); eq(w.C.Stats().chatQueue, 1)
		w.C.JoinChannel()
		eq(#w.left, 0); eq(#w.joined, 0)
	end)
end)

-- Off Forever nothing changes: the key seals the channel, on its lane, and the hello says so.
test("1.5.9 one channel on Forever: off Forever a realm key still seals the channel, on its lane, deaf to the public first lane, and the hello says sealed and the lane", function()
	WithClient({ key = "fixture-secret", lane = 7, forever = false }, function(w)
		local name, password = w.C.ChannelSpec()
		eq(name, "Oly" .. w.C.Hash36("fixture-secret") .. "7"); eq(password, "fixture-secret")
		eq(w.C.Stats().channel, SEALED_ID); eq(w.C.Stats().sealed, true); eq(w.C.Lane(), 7)
		for _, piece in ipairs(ReportPieces("OLYMPUS PRIME", "45")) do w.Native(PUBLIC_ID, "Older Broadcaster-Realm", piece) end
		eq(w.C.Stats().reports, 0, "the public channel's report is another channel's")
		local hello = assert(w.Hello(), "a hello")
		assert(hello:match("^H1~[^~]+~[^~]*~s~~~L7~R"), hello)
	end)
end)

-- /oly status and /oly bug on Forever: the channel joined (public, lane 0), the key held, and the sealed
-- channel's name the key gives never shown, though the log still names it from before.
test("1.5.9 one channel on Forever: /oly status says the key held, not sealing; the sealed name the key gives, any lane, never shows, though the log named it before", function()
	local saved = { forever = ns.OnForever, key = ns.rdb.realmKey, lane = ns.rdb.channelLane, log = ns.db.log }
	local ok, err = pcall(function()
		ns.OnForever = function() return true end
		ns.rdb.realmKey, ns.rdb.channelLane = "fixture-secret", 7
		local sealed = "Oly" .. ns.Comm.Hash36("fixture-secret")
		eq((ns.Comm.ChannelSpec()), "OlympusNet")
		ns.db.log = { "joining channel " .. sealed .. "7 (sealed)", "relay: lane note " .. sealed .. "7 was #6", "census: a line " .. sealed }
		local recent = ns.RecentDiagnostics("")
		assert(not recent:find(sealed, 1, true), "the sealed name never shows: " .. recent)
		assert(recent:find("relay: lane note (sealed channel) was #6", 1, true), recent)
		local status = ns.StatusText()
		assert(not status:find(sealed, 1, true), "nor in /oly status")
		assert(status:find("channel sealed (key holders)", 1, true), "the privacy line still by the key: " .. status)
		-- The key's own line (Keys.lua, in a namespace of its own: its handlers stay off the shared Comm).
		local kns = setmetatable({ rdb = { realmKey = "fixture-secret" }, OnForever = function() return true end,
			Comm = { Handle = function() end, Hash36 = ns.Comm.Hash36 }, On = function() end, Every = function() end, After = function() end },
			{ __index = ns })
		assert(loadfile(ADDON .. "Keys.lua"))("Olympus", kns)
		assert(kns.Keys.StatusLine():find("^held %(the public channel on Forever%)  |  epoch "), kns.Keys.StatusLine())
		kns.OnForever = function() return false end
		assert(kns.Keys.StatusLine():find("^sealed  |  epoch "), "off Forever: " .. kns.Keys.StatusLine())
		kns.rdb.realmKey = nil
		assert(kns.Keys.StatusLine():find("^public  |  epoch "), "no key: " .. kns.Keys.StatusLine())
	end)
	ns.OnForever, ns.rdb.realmKey, ns.rdb.channelLane, ns.db.log = saved.forever, saved.key, saved.lane, saved.log
	if not ok then error(err, 0) end
end)
