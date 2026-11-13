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
-- public first lane, the key's sealed channel (first lane and lane 7) and the public lane 7 joined (with
-- o.late the public first lane alone: a test joins the others later, in w.indexes, as the game does on a
-- slow login). w.Event(name, ...) fires one of the game's events at the handlers Comm registered.
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
		local indexes, joined, left = { OlympusNet = PUBLIC_ID, OlympusNet7 = (not o.late) and LANE_ID or nil }, {}, {}
		if o.key and not o.late then indexes["Oly" .. C.Hash36(o.key)], indexes["Oly" .. C.Hash36(o.key) .. "7"] = SEALED_ID, SEALED_ID end
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
			Guild = function(sender, text) Fire("GUILD", sender, text) end,
			Event = function(event, ...) for _, f in ipairs(events[event] or {}) do f(...) end end })
	end)
	GetChannelName, JoinChannelByName, LeaveChannelByName, ns.IsMember, C_ChatInfo, SendChatMessage =
		saved.channel, saved.join, saved.leave, saved.member, saved.info, saved.say
	if not ok then error(err, 0) end
end

-- A census report (R2) of another guild, in the channel's pieces, as a client on 1.5.4 broadcasts it.
local function ReportPieces(guild, id)
	return ns.Codec.Chunk(ns.Codec.EncodeReport({ guild = guild, total = 980, online = 120, zones = {}, faction = "Alliance" }), id)
end

-- Every language's lines as a game in it loads them (the TOC's locale files, as tests/locales-full.lua
-- loads them), each language once: [code] = its L.
local languages
local function Languages()
	if languages then return languages end
	languages = {}
	for _, code in ipairs({ "enUS", "ptBR", "deDE", "esES", "frFR", "itIT", "ruRU" }) do
		local lns, saved = {}, GetLocale
		GetLocale = function() return code end
		local ok, err = pcall(function()
			for line in io.lines(ADDON .. "Olympus.toc") do
				local f = line:match("^%s*(Locales%.lua)%s*$") or line:match("^%s*(Locales[\\/].-%.lua)%s*$")
				if f then assert(loadfile(ADDON .. f:gsub("\\", "/")))("Olympus", lns) end
			end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		languages[code] = lns.L
	end
	return languages
end
-- Each of `keys` in its own words in all seven languages: never the English line, with its format codes
-- (a line whose codes differ stays English, ns.Locale), and no em dash in Russian.
local function InEveryLanguage(keys)
	local all = Languages()
	for _, k in ipairs(keys) do
		local en = all.enUS[k]
		assert(type(en) == "string" and en ~= "", "English: " .. k)
		for code, L in pairs(all) do
			if code ~= "enUS" then
				assert(type(L[k]) == "string" and L[k] ~= en, code .. " translates " .. k)
				eq(ns.LocaleCodes(L[k]), ns.LocaleCodes(en), code .. " " .. k .. ": its format codes")
			end
		end
		assert(not all.ruRU[k]:find("\226\128\148", 1, true), "ruRU " .. k .. ": no em dash")
	end
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
		-- (1.5.9's review: their hellos recent, a minute old, within Comm.CROWD_RECENT. An hour old, as this
		-- test had them, no crowd counted with or without the guards, and nothing here tested them.)
		for i = 1, 5 do w.Guild(("Crowd Peer%d-Realm"):format(i), "H1~1.5.8~Realm~p~~~L3~R~N") end
		w.cns.clock = w.cns.clock + 60
		assert(w.cns.clock - 60 + w.C.CROWD_RECENT > w.cns.clock, "the hellos are within CROWD_RECENT")
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
		-- (1.5.9's review, C5: the line said "channel sealed (key holders)" beside "sealed=false". On Forever the
		-- channel is the public one whatever the key: the line says so, and the key's one effect beside it.)
		assert(status:find("channel public (anyone), key held: typed chat lines by the relay alone", 1, true),
			"the privacy line: the public channel, the key held: " .. status)
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

-- 1.5.9's review (C1): on Forever a client takes native words from the public first lane alone, yet it may
-- still sit in Olympus's own channels from an earlier session (Comm.JoinChannel leaves only the one it
-- joined this session): its key's sealed channel and a later lane. Older clients still broadcast their
-- census there (1.4.0 and 1.4.1 always, 1.4.3 to 1.5.4 while no relay answers, on the sealed channel when
-- they hold the key), and a 1.5.8 client on it took it. Those words are taken again (Comm.Leftover); a
-- channel that is not Olympus's, never. Off Forever, as before. Fails before (reports 0, otherChannel 1
-- for each piece).
test("1.5.9 one channel on Forever: a client still in its key's sealed channel and an older lane from an earlier session takes the census older clients broadcast there; another channel's words never; off Forever as before", function()
	local function Ids(w, byId)
		GetChannelName = function(x)
			if type(x) == "number" then return byId[x] and x or 0, byId[x] end
			for id, name in pairs(byId) do if name == x then return id, name end end
			return 0, x
		end
	end
	WithClient({ key = "fixture-secret", lane = 7 }, function(w)
		local sealed = "Oly" .. w.C.Hash36("fixture-secret")
		Ids(w, { [PUBLIC_ID] = "OlympusNet", [6] = sealed, [9] = sealed .. "7", [8] = "OlympusNet7", [3] = "SomeOtherChannel" })
		local heard = 0
		for k, id in ipairs({ 6, 9, 8 }) do
			for _, piece in ipairs(ReportPieces(("OLYMPUS OLD %d"):format(k), tostring(50 + k))) do
				w.Native(id, ("Older Broadcaster%d-Realm"):format(k), piece)
				heard = heard + 1
			end
		end
		eq(w.C.Stats().otherChannel, 0, "none dropped as another channel's")
		eq(w.C.Stats().leftover, heard, "each counted as taken on a leftover channel (/oly bug's channel line)")
		eq(w.C.Stats().reports, 3, "the census broadcast on the old sealed channel, its lane 7 and OlympusNet7 is taken")
		local stranger = ReportPieces("OLYMPUS STRANGER", "60")
		for _, piece in ipairs(stranger) do w.Native(3, "Some Stranger-Realm", piece) end
		eq(w.C.Stats().reports, 3, "a channel that is not Olympus's: nothing taken")
		eq(w.C.Stats().otherChannel, #stranger, "each of its pieces dropped as another channel's")
		eq(w.C.Leftover(sealed), true); eq(w.C.Leftover(sealed .. "7"), true); eq(w.C.Leftover("OlympusNet7"), true)
		eq(w.C.Leftover("OlympusNet"), false, "the joined one is no leftover"); eq(w.C.Leftover("OlympusNetH7"), false, "nor the Horde's")
		eq(w.C.Leftover("SomeOtherChannel"), false); eq(w.C.Leftover(sealed .. "77"), false, "no lane past LANE_MAX")
	end)
	WithClient({ key = "fixture-secret", lane = 0, forever = false }, function(w)
		local sealed = "Oly" .. w.C.Hash36("fixture-secret")
		Ids(w, { [SEALED_ID] = sealed, [8] = "OlympusNet7" })
		eq(w.C.Leftover("OlympusNet7"), false, "off Forever no leftover")
		local pieces = ReportPieces("OLYMPUS OLD 9", "61")
		for _, piece in ipairs(pieces) do w.Native(8, "Older Broadcaster9-Realm", piece) end
		eq(w.C.Stats().reports, 0); eq(w.C.Stats().otherChannel, #pieces, "off Forever another lane is another channel, as before")
		eq(w.C.Stats().leftover, 0, "and nothing taken on a leftover channel")
	end)
end)

-- 1.5.9's review (P6): those channels are kept for that census, never left, but off the chat windows again
-- once a session: a 1.5.8 key holder's chat line goes as text into the sealed one, and a window whose
-- channel list was reset showed it raw. Fails before (only the joined channel was kept off them).
test("1.5.9 one channel on Forever: the sealed channel and the older lane still joined from an earlier session are kept off the chat windows again, never left", function()
	local saved = { num = NUM_CHAT_WINDOWS, remove = ChatFrame_RemoveChannel, f1 = rawget(_G, "ChatFrame1"), f2 = rawget(_G, "ChatFrame2") }
	local removed = {}
	local ok, err = pcall(function()
		NUM_CHAT_WINDOWS, ChatFrame1, ChatFrame2 = 2, {}, {}
		ChatFrame_RemoveChannel = function(frame, name) removed[name] = (removed[name] or 0) + 1 end
		WithClient({ key = "fixture-secret", lane = 7 }, function(w)
			local sealed = "Oly" .. w.C.Hash36("fixture-secret")
			eq(removed.OlympusNet, 2, "the joined channel off both windows, as ever")
			eq(removed.OlympusNet7, 2, "the older lane off both windows")
			eq(removed[sealed], 2, "the sealed channel off both windows")
			eq(removed[sealed .. "7"], 2, "and its lane 7")
			eq(#w.left, 0, "none of them left")
			removed = {}
			w.C.JoinChannel()
			eq(removed.OlympusNet7, nil, "once a session")
		end)
	end)
	NUM_CHAT_WINDOWS, ChatFrame_RemoveChannel, ChatFrame1, ChatFrame2 = saved.num, saved.remove, saved.f1, saved.f2
	if not ok then error(err, 0) end
end)

-- 1.5.9's review (B3, from e57a1bba): JoinChannel put those channels off the chat windows at its first call
-- and never looked again, yet on a slow login the game joins its remembered channels after ours (Comm.lua's
-- CHANNEL_UI_UPDATE handler): the old sealed channel and lane 7 then stayed in the chat windows all session.
-- Each goes off them once it is found joined: by JoinChannel, or in the session's first 180 s by a change of
-- the channel list, once it settles; never left, and later changes are the player's. Fails before (those
-- joined after ours were never put off the windows).
test("1.5.9 one channel on Forever: the sealed channel and lane 7 the game joins after ours on a slow login still go off the chat windows, once each, in the session's first minutes; never left", function()
	local saved = { num = NUM_CHAT_WINDOWS, remove = ChatFrame_RemoveChannel, f1 = rawget(_G, "ChatFrame1"), f2 = rawget(_G, "ChatFrame2") }
	local removed = {}
	local ok, err = pcall(function()
		NUM_CHAT_WINDOWS, ChatFrame1, ChatFrame2 = 2, {}, {}
		ChatFrame_RemoveChannel = function(frame, name) removed[name] = (removed[name] or 0) + 1 end
		WithClient({ key = "fixture-secret", lane = 7, late = true }, function(w)
			local sealed = "Oly" .. w.C.Hash36("fixture-secret")
			local timers = {}
			w.cns.After = function(_, _, f) timers[#timers + 1] = f end
			local function Settle()
				local due = timers
				timers = {}
				for _, f in ipairs(due) do f() end
			end
			eq(removed.OlympusNet, 2, "ours off both windows, as ever")
			eq(removed[sealed], nil, "the old sealed channel not joined yet")
			-- 40 s in, the game joins its remembered channels: the old sealed channel, its lane 7, and OlympusNet7.
			w.cns.clock = w.cns.clock + 40
			w.indexes[sealed], w.indexes[sealed .. "7"], w.indexes.OlympusNet7 = SEALED_ID, SEALED_ID, LANE_ID
			w.Event("CHANNEL_UI_UPDATE")
			w.Event("CHANNEL_UI_UPDATE")
			Settle()
			eq(removed[sealed], 2, "the old sealed channel off both windows")
			eq(removed[sealed .. "7"], 2, "and its lane 7")
			eq(removed.OlympusNet7, 2, "and the older public lane")
			-- Once each: another change of the list leaves them be.
			w.Event("CHANNEL_UI_UPDATE")
			Settle()
			eq(removed[sealed], 2, "once a session")
			eq(removed.OlympusNet7, 2, "once a session")
			-- Past the session's first 180 s, one the game joins is the player's business.
			w.cns.clock = w.cns.clock + 180
			w.indexes.OlympusNet3 = 9
			w.Event("CHANNEL_UI_UPDATE")
			Settle()
			eq(removed.OlympusNet3, nil, "later changes are the player's")
			eq(#w.left, 0, "none of them left")
		end)
	end)
	NUM_CHAT_WINDOWS, ChatFrame_RemoveChannel, ChatFrame1, ChatFrame2 = saved.num, saved.remove, saved.f1, saved.f2
	if not ok then error(err, 0) end
end)

-- 1.5.9's review (C3): the first line of a tier waits for the player's OK under a warning that names its
-- audience (GitHub #34: a line written for one audience is never sent to another). The guard compared the
-- channel's name alone; on Forever a key cleared while the warning is open (K7, Keys.TakeClear) keeps the
-- name and turns the chat hall on, so a line confirmed for the sealed audience went out as plain text in
-- the public channel. It is dropped as moved now, the tier not counted as warned. Real Comm, Channels and
-- ChatHall. Fails before (Confirm sent it, and the game was asked to say it in the channel).
test("1.5.9's review one channel on Forever: a line confirmed under the first-line warning for key holders is dropped as moved when a key clear arrives meanwhile, never typed into the public channel; off Forever too", function()
	local FreshComm = assert(extra.FreshComm, "tests/run.lua hands FreshComm to this file")
	for _, forever in ipairs({ true, false }) do
		local saved = { name = GetChannelName, leave = LeaveChannelByName, join = JoinChannelByName, guild = GetGuildInfo,
			time = GetTime, info = C_ChatInfo, say = rawget(_G, "SendChatMessage"),
			slash = { SlashCmdList.OLYMPUSALL, SlashCmdList.OLYMPUSCAPTAINS, SlashCmdList.OLYMPUSLORDS },
			dialogs = { StaticPopupDialogs.OLYMPUS_CHAT_PRIVACY, StaticPopupDialogs.OLYMPUS_PIN, StaticPopupDialogs.OLYMPUS_PIN_DOWN } }
		local ok, err = pcall(function()
			local cns = FreshComm()
			local said, printed, dialogs, ids, clock = {}, {}, {}, {}, 100000
			cns.db = { addonChat = true, chatWarned = {}, blocked = {} }
			cns.rdb = { guilds = {}, realmKey = "fixture-secret" }
			cns.IsMember = function() return true end
			cns.OnForever = function() return forever end
			cns.splitNames = forever
			cns.Print = function(msg) printed[#printed + 1] = tostring(msg) end
			cns.Fire = function() end
			cns.ShowDialog = function(which, a, b, data) dialogs[#dialogs + 1] = { which = which, audience = b, data = data } end
			cns.Data = setmetatable({ ForgetVotes = function() end }, { __index = ns.Data })
			GetGuildInfo = function() return "OLYMPUS FIXTURE", "Lord", 0 end
			GetTime = function() return clock end
			GetChannelName = function(name) return ids[name] or 0 end
			LeaveChannelByName = function(name) ids[name] = nil end
			JoinChannelByName = function() end
			C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() return 0 end,
				SendAddonMessageLogged = function() return 0 end }
			SendChatMessage = function(text, kind) said[#said + 1] = { text = text, kind = kind } end
			assert(loadfile(ADDON .. "Channels.lua"))("Olympus", cns)
			assert(loadfile(ADDON .. "ChatHall.lua"))("Olympus", cns)
			local C, Chan = cns.Comm, cns.Channels
			ids[C.ChannelSpec()] = 6
			ids.OlympusNet = ids.OlympusNet or 7
			C.JoinChannel()
			local label = forever and "on Forever" or "off Forever"
			local _, why = Chan.Send("A", "a line for key holders only")
			eq(why, "confirm", label .. ": the warning shows")
			local d = assert(dialogs[1], "a warning")
			eq(d.audience, forever and ns.L.CHANNEL_SEALED_FOREVER or ns.L.CHANNEL_SEALED, label .. ": it names the key holders")
			-- What Keys.TakeClear does (K7): the key cleared, then JoinChannel.
			cns.rdb.realmKey = nil
			C.JoinChannel()
			local r1, r2 = Chan.Confirm(d.data, true)
			for _ = 1, 10 do C.Pump() end
			eq(r1, false, label); eq(r2, "moved", label .. ": dropped as moved")
			local typed = 0
			for _, x in ipairs(said) do if x.text:find("a line for key holders only", 1, true) then typed = typed + 1 end end
			eq(typed, 0, label .. ": never typed into a channel")
			eq(cns.db.chatWarned.A, nil, label .. ": the tier is not counted as warned")
			eq(printed[#printed], ns.L.CHAN_MOVED:format("Olympus"), label .. ": the player is told")
		end)
		GetChannelName, LeaveChannelByName, JoinChannelByName, GetGuildInfo = saved.name, saved.leave, saved.join, saved.guild
		GetTime, C_ChatInfo, SendChatMessage = saved.time, saved.info, saved.say
		SlashCmdList.OLYMPUSALL, SlashCmdList.OLYMPUSCAPTAINS, SlashCmdList.OLYMPUSLORDS = saved.slash[1], saved.slash[2], saved.slash[3]
		StaticPopupDialogs.OLYMPUS_CHAT_PRIVACY, StaticPopupDialogs.OLYMPUS_PIN = saved.dialogs[1], saved.dialogs[2]
		StaticPopupDialogs.OLYMPUS_PIN_DOWN = saved.dialogs[3]
		if not ok then error(err, 0) end
	end
end)

-- 1.5.9's review (C4): /oly bug leaves out an older key's sealed name where Comm.lua writes a channel's
-- name ("channel X", "joining channel X"), by its shape; a lane digit after it ("Oly...7", logged while
-- the client sat on lane 7 when the King rotated the key) defeated the pattern, and the old name, which
-- gives the old key back to anyone guessing keys offline, showed. Fails before (the lane-7 lines kept it).
test("1.5.9's review /oly bug: an older key's sealed name with a lane digit after it never shows in the log lines; OlympusNet7 and a character's name stay", function()
	local saved = { key = ns.rdb.realmKey, log = ns.db.log }
	local ok, err = pcall(function()
		ns.rdb.realmKey = "fixture-new-key"
		local old = "Oly" .. ns.Comm.Hash36("fixture-old-key")
		ns.db.log = { "joining channel " .. old .. "7 (sealed)", "channel " .. old .. "7 -> #6", "channel " .. old .. " -> #6",
			"joining channel OlympusNet7", "whisper from Olyabcdefgh, a character" }
		local recent = ns.RecentDiagnostics("")
		assert(not recent:find(old, 1, true), "the older key's name never shows: " .. recent)
		assert(recent:find("joining channel (sealed channel) (sealed)", 1, true), recent)
		assert(recent:find("channel (sealed channel) -> #6", 1, true), recent)
		assert(recent:find("joining channel OlympusNet7", 1, true), "the public lane's name stays: " .. recent)
		assert(recent:find("Olyabcdefgh, a character", 1, true), "a name shaped alike elsewhere stays: " .. recent)
	end)
	ns.rdb.realmKey, ns.db.log = saved.key, saved.log
	if not ok then error(err, 0) end
end)

-- 1.5.9's review (C5, P3 and the 1.5.9 builder's open item): what a player is told of a realm key on
-- Forever said it sealed the channel, joined a new one or returned the guild to the public one, none of
-- which happens there any more (Comm.ChannelSpec). Each message says what happens instead, in every
-- language (tests/locales-full.lua): the key kept, every guild on the public channel, a key holder's
-- typed lines by the relays alone. Off Forever, the old messages. And the Census's public channel line
-- has no "seal it with the key" on Forever (since B1 of the review, its own words there: the next test).
-- Fails before (the old messages on Forever).
test("1.5.9's review one channel on Forever: /oly key, a key taken or cleared, /oly help and the chat warning's audience say what a key does on Forever; off Forever as before; no sealing advice on the Census", function()
	local L = ns.L
	for _, forever in ipairs({ true, false }) do
		local printed = {}
		local label = forever and "on Forever" or "off Forever"
		WithClient({ key = nil, lane = 0, forever = forever }, function(w)
			w.cns.Print = function(msg) printed[#printed + 1] = msg end
			w.cns.Roster.IsOfficer = function() return true end
			w.cns.Keys = { Typed = function() end }
			w.C.SetRealmKey("fixture-secret")
			eq(printed[#printed], forever and L.KEY_SET_FOREVER or L.KEY_SET, label .. ": /oly key")
			eq(w.C.Audience(), forever and L.CHANNEL_SEALED_FOREVER or L.CHANNEL_SEALED, label .. ": the chat warning's audience")
			-- The Census's line for a public guild's officer: (changed on purpose, B1 of 1.5.9's review) on
			-- Forever too, in its Forever words, without the advice to seal the channel.
			w.cns.rdb.realmKey = nil
			w.cns.Roster.IsOfficer = function() return true end
			local lines = {}
			local saved = { comm = ns.Comm, forever = ns.OnForever, roster = ns.Roster.IsOfficer }
			ns.Comm, ns.OnForever, ns.Roster.IsOfficer = w.C, function() return forever end, function() return true end
			local okV, shown = pcall(ns.Views.PublicLines, lines)
			ns.Comm, ns.OnForever, ns.Roster.IsOfficer = saved.comm, saved.forever, saved.roster
			assert(okV, shown)
			eq(shown, true, label .. ": the public channel line on the Census")
			assert(lines[1].text:find((forever and L.PUBLIC_NET_FOREVER or L.PUBLIC_NET):format("OlympusNet"), 1, true), label .. ": " .. lines[1].text)
		end)
		-- Keys.lua in a namespace of its own (its handlers off the shared Comm).
		local kns = setmetatable({ rdb = { realmKey = "fixture-old" }, OnForever = function() return forever end,
			Print = function(msg) printed[#printed + 1] = msg end, IsMember = function() return true end,
			Roster = setmetatable({ IsOfficer = function() return true end }, { __index = ns.Roster }),
			Comm = { Handle = function() end, Hash36 = ns.Comm.Hash36, JoinChannel = function() end, Send = function() end },
			Log = function() end, On = function() end, Every = function() end, After = function() end }, { __index = ns })
		assert(loadfile(ADDON .. "Keys.lua"))("Olympus", kns)
		eq(kns.Keys.Take("fixture-newer", 2000000000, false), true)
		eq(printed[#printed], forever and L.KEY_ROTATED_TAKEN_FOREVER or L.KEY_ROTATED_TAKEN, label .. ": a new key taken")
		eq(kns.Keys.TakeClear(2000000001, false), true)
		eq(printed[#printed], forever and L.KEY_CLEARED_TAKEN_FOREVER or L.KEY_CLEARED_TAKEN, label .. ": a clear taken")
		kns.rdb.realmKey = "fixture-again"
		eq(kns.Keys.Clear(), true)
		eq(printed[#printed], forever and L.KEY_CLEARED_FOREVER or L.KEY_CLEARED, label .. ": /oly key off")
	end
	-- /oly help's two key lines.
	local saved = { forever = ns.OnForever, print = print }
	local ok, err = pcall(function()
		for _, forever in ipairs({ true, false }) do
			local said = {}
			ns.OnForever = function() return forever end
			print = function(msg) said[#said + 1] = tostring(msg) end
			pcall(SlashCmdList.OLYMPUS, "help")
			print = saved.print
			local all = table.concat(said, "\n")
			assert(all:find(forever and L.HELP_CMD_KEY_FOREVER or L.HELP_CMD_KEY, 1, true), (forever and "on" or "off") .. " Forever: the key's help line")
			assert(all:find(forever and L.HELP_CMD_KEY_PUBLIC_FOREVER or L.HELP_CMD_KEY_PUBLIC, 1, true), "and its off line")
		end
	end)
	ns.OnForever, print = saved.forever, saved.print
	if not ok then error(err, 0) end
end)

-- 1.5.9's review (B1, from eb2e95a9): the Census's public channel line was hidden on Forever whatever the
-- key, so a key-less officer there no longer saw that his guild's typed chat lines go as plain text into
-- the public channel (ChatHall.On), which is still so and the one thing a key still changes there. His
-- line is back on Forever in words true there: anyone who joins reads the guild's typed chat lines; its
-- tooltip, that 1.5.5 and later send the census by the relays, so what is read there is the typed lines of
-- guilds without a key and older clients' census, and that a key (/oly key) keeps the guild's lines out of
-- it, the relays carrying them to the other guilds. No advice to seal it and no count of guildmates "on
-- the sealed channel" (1.5.8's hellos) there; a member sees nothing, a key holder nothing; off Forever as
-- before. In all seven languages. Fails before (no line on Forever).
test("1.5.9's review one channel on Forever: a key-less officer's Census line says anyone in the public channel reads his guild's typed chat lines, its tooltip what a key does there, in every language; no sealing advice or sealed count; off Forever as before", function()
	local L = ns.L
	for _, forever in ipairs({ true, false }) do
		local label = forever and "on Forever" or "off Forever"
		WithClient({ key = nil, lane = 0, forever = forever }, function(w)
			-- Two guildmates whose hellos (1.5.8's) say they are on the sealed channel.
			w.Guild("Old Sealer-Realm", "H1~1.5.8~Realm~s")
			w.Guild("Other Sealer-Realm", "H1~1.5.8~Realm~s")
			eq(w.C.SealedPeers(), 2, label .. ": their hellos heard")
			local function Build(officer)
				local lines = {}
				local saved = { comm = ns.Comm, forever = ns.OnForever, officer = ns.Roster.IsOfficer }
				ns.Comm, ns.OnForever, ns.Roster.IsOfficer = w.C, function() return forever end, function() return officer end
				local ok, shown = pcall(ns.Views.PublicLines, lines)
				ns.Comm, ns.OnForever, ns.Roster.IsOfficer = saved.comm, saved.forever, saved.officer
				assert(ok, shown)
				return shown, lines
			end
			local function Tip(line)
				local tip = {}
				line.tooltip({ AddLine = function(_, t) tip[#tip + 1] = t end })
				return tip
			end
			local shown, lines = Build(true)
			eq(shown, true, label .. ": an officer's line")
			if forever then
				eq(#lines, 1, "on Forever: the officer's line alone, no count of guildmates on a sealed channel")
				assert(lines[1].text:find(L.PUBLIC_NET_FOREVER:format("OlympusNet"), 1, true), lines[1].text)
				local tip = Tip(lines[1])
				eq(#tip, 2, "its title and what it means, no advice to seal it")
				eq(tip[1], L.PUBLIC_NET_TITLE)
				eq(tip[2], L.PUBLIC_NET_TIP_FOREVER:format("OlympusNet"))
				local memberShown, memberLines = Build(false)
				eq(memberShown, false, "on Forever: nothing for a member")
				eq(#memberLines, 0)
			else
				eq(#lines, 2, "off Forever: the officer's line and the guildmates on the sealed channel")
				assert(lines[1].text:find(L.PUBLIC_NET:format("OlympusNet"), 1, true), lines[1].text)
				assert(lines[2].text:find(L.PUBLIC_NET_SPLIT:format(2), 1, true), lines[2].text)
				local tip = Tip(lines[1])
				eq(tip[1], L.PUBLIC_NET_TITLE)
				eq(tip[2], L.PUBLIC_NET_TIP:format("OlympusNet"))
				eq(tip[3], L.PUBLIC_NET_OFFICER, "off Forever: how to seal it")
				local memberShown, memberLines = Build(false)
				eq(memberShown, true, "off Forever: a member sees the count")
				eq(#memberLines, 1)
			end
			-- A key held: no line, on Forever or off it (there its typed lines stay out of the channel).
			w.cns.rdb.realmKey = "fixture-secret"
			eq((Build(true)), false, label .. ": an officer holding a key")
		end)
	end
	-- The Forever words: the typed chat lines, the relays and what a key does there, never sealing.
	assert(L.PUBLIC_NET_FOREVER:find("typed chat lines", 1, true), L.PUBLIC_NET_FOREVER)
	assert(L.PUBLIC_NET_TIP_FOREVER:find("/oly key", 1, true) and L.PUBLIC_NET_TIP_FOREVER:find("relays", 1, true), L.PUBLIC_NET_TIP_FOREVER)
	for _, k in ipairs({ "PUBLIC_NET_FOREVER", "PUBLIC_NET_TIP_FOREVER" }) do assert(not L[k]:lower():find("seal", 1, true), k) end
	InEveryLanguage({ "PUBLIC_NET_FOREVER", "PUBLIC_NET_TIP_FOREVER" })
end)

-- 1.5.9's review (B2, from eb2e95a9): a key holder's audience text on Forever (CHANNEL_SEALED_FOREVER, from
-- Comm.Audience) said "your lines never show in it as text", but it is also what the zone sharing question,
-- the Board's flags and camps, the groups' listing and application, the privacy page and the Treasurer's
-- share say of who reads what they send. It now fits any of them: what is sent to all guilds reaches them by
-- the relays, where any of their players can read it, and nothing sent goes into the public channel they
-- share (there ChatHall.On is off for a key holder, and every channel word goes by the relays). In all
-- seven languages, none of which speaks of lines any more. Fails before (each language's word for lines).
-- (Round 2 of the review) "Nothing you send goes into the public Olympus channel they share" then denied the
-- sentence each of four questions puts right before it: the zone's "Everyone on the Olympus channel receives
-- it", the chat warning's "anyone on the channel can read all three", the Treasurer's "goes out on the Olympus
-- channel", the privacy page's census "on the Olympus channel". On Forever the key holder's Olympus channel is
-- the public one (Comm.ChannelSpec), and the relays carry what goes on it. The text now says so, and what the
-- key does keep out: none of it shows as text in the game's public channel. Fails before (the denial, and no
-- word for text, in every language).
test("1.5.9's review one channel on Forever: a key holder's audience fits any message the privacy questions send (zone, Board, groups, privacy page, treasury, chat): the relays carry the Olympus channel to every guild, none of it as text in the game's public channel, never denying the question's own channel; in every language", function()
	local L = ns.L
	WithClient({ key = "fixture-secret", lane = 0 }, function(w)
		local audience = w.C.Audience()
		eq(audience, L.CHANNEL_SEALED_FOREVER, "a key holder's audience on Forever")
		-- The Board's flag and the privacy page carry it as they ask.
		local saved = ns.Comm
		ns.Comm = w.C
		local ok, err = pcall(function()
			assert(ns.Board.PrivacyText(nil):find(audience, 1, true), "the Board's flag")
			assert(ns.Consent.Intro():find(audience, 1, true), "the privacy page")
		end)
		ns.Comm = saved
		if not ok then error(err, 0) end
	end)
	assert(L.CHANNEL_SEALED_FOREVER:find("the relays carry the Olympus channel", 1, true), L.CHANNEL_SEALED_FOREVER)
	assert(L.CHANNEL_SEALED_FOREVER:find("none of it shows as text in the game's public channel", 1, true), L.CHANNEL_SEALED_FOREVER)
	-- (Each question as a key holder on Forever reads it: the question's own channel sentence, then this.)
	for key, sentence in pairs({ LOCATION_ASK = "Everyone on the Olympus channel receives it.",
		CHAN_WARN_ASK = "anyone on the channel can read all three with a script.",
		TREASURER_SHARE_ASK = "goes out on the Olympus channel, and every client on it receives it",
		CONSENT_INTRO = "sends your guild's census on the Olympus channel" }) do
		local text = key == "CHAN_WARN_ASK" and L[key]:format("Olympus", L.CHANNEL_SEALED_FOREVER) or L[key]:format(L.CHANNEL_SEALED_FOREVER)
		assert(text:find(sentence, 1, true) and text:find(L.CHANNEL_SEALED_FOREVER, 1, true), key .. ": " .. text)
	end
	local LINES = { enUS = "lines", ptBR = "linhas", deDE = "Zeilen", esES = "líneas", frFR = "lignes", itIT = "righe", ruRU = "строки" }
	local RELAYS = { enUS = "relays", ptBR = "relays", deDE = "Relays", esES = "relays", frFR = "relais", itIT = "relay", ruRU = "ретранслятор" }
	local TEXT = { enUS = "as text", ptBR = "como texto", deDE = "als Text", esES = "como texto", frFR = "en texte", itIT = "come testo",
		ruRU = "текстом" }
	-- (The denial each language said before.)
	local DENIAL = { enUS = "nothing you send goes into", ptBR = "nada do que você envia entra", deDE = "nichts, was du sendest, kommt in",
		esES = "nada de lo que envías entra", frFR = "rien de ce que tu envoies n'entre", itIT = "niente di ciò che invii entra",
		ruRU = "ничего из того, что ты отправляешь, не попадает" }
	for code, Lc in pairs(Languages()) do
		local text = Lc.CHANNEL_SEALED_FOREVER
		assert(not text:find(LINES[code], 1, true), code .. ": no lines in " .. text)
		assert(text:find(RELAYS[code], 1, true), code .. ": the relays in " .. text)
		assert(text:find(TEXT[code], 1, true), code .. ": what stays out of the public channel is text: " .. text)
		assert(not text:find(DENIAL[code], 1, true), code .. ": no denial of the question's channel: " .. text)
	end
	InEveryLanguage({ "CHANNEL_SEALED_FOREVER" })
end)

-- 1.5.9's review (B4): the King's key rotation still promised channel moves on Forever: its tooltip on the
-- Throne ("stays behind on the old channel"), its question ("move to it", "stays on the old channel") and
-- the answer to anyone else ("Officers still seal their own guild's channel"), none of which happens there
-- (Comm.ChannelSpec). On Forever each says what rotating does instead: nobody moves channel, the new key
-- reaches the picked guilds the same way, and a key, old or new, keeps its holders' typed chat lines out of
-- the public channel. Off Forever as before. In all seven languages. Keys.lua in a namespace of its own,
-- /oly key rotate through the harness's Core with it. Fails before (the old texts and question on Forever).
test("1.5.9's review one channel on Forever: the King's key rotation (the Throne's tooltip, its question, the answer to anyone else, /oly key rotate) says nobody moves channel there and what a key does; off Forever as before; in every language", function()
	local L = ns.L
	local savedDialogs = {}
	for k, v in pairs(StaticPopupDialogs) do if tostring(k):find("^OLYMPUS_KEY_") then savedDialogs[k] = v end end
	local ok, err = pcall(function()
		for _, forever in ipairs({ true, false }) do
			local label = forever and "on Forever" or "off Forever"
			local printed, shown, author = {}, {}, false
			local kns = setmetatable({ rdb = { realmKey = "fixture-old" }, OnForever = function() return forever end,
				Print = function(msg) printed[#printed + 1] = msg end, IsMember = function() return true end,
				ShowDialog = function(which, a) shown[#shown + 1] = { which = which, a = a } end,
				Workshop = { IsAuthor = function() return author end }, ViewAs = false,
				King = { IsKing = function() return false end, IsSteward = function() return false end, Preview = function() return false end,
					Line = function(text, _, o) local l = o or {} l.text = text return l end, INK = {}, TITLE = {}, Para = function() end },
				Comm = { Handle = function() end, Hash36 = ns.Comm.Hash36, JoinChannel = function() end, Send = function() end },
				Log = function() end, On = function() end, Every = function() end, After = function() end }, { __index = ns })
			assert(loadfile(ADDON .. "Keys.lua"))("Olympus", kns)
			local K = kns.Keys
			-- Anyone else: told so, and on Forever not that officers seal a channel.
			eq(K.Rotate(), nil)
			eq(printed[#printed], forever and L.KEY_ROTATE_ONLY_KING_FOREVER or L.KEY_ROTATE_ONLY_KING, label .. ": the answer to anyone else")
			K.RotatePrompt()
			eq(printed[#printed], forever and L.KEY_ROTATE_ONLY_KING_FOREVER or L.KEY_ROTATE_ONLY_KING, label .. ": and to his prompt")
			eq(#shown, 0, label .. ": no question for him")
			-- /oly key rotate typed by him: the harness's own Core, with this Keys.
			local savedKeys, savedPrint = ns.Keys, ns.Print
			ns.Keys, ns.Print = K, function(msg) printed[#printed + 1] = msg end
			local okS, errS = pcall(SlashCmdList.OLYMPUS, "key rotate")
			ns.Keys, ns.Print = savedKeys, savedPrint
			assert(okS, errS)
			eq(printed[#printed], forever and L.KEY_ROTATE_ONLY_KING_FOREVER or L.KEY_ROTATE_ONLY_KING, label .. ": /oly key rotate")
			-- The one who may rotate (here the author's own view): the Throne's tooltip, then the question.
			author = true
			local line
			for _, l in ipairs(K.ThroneLines()) do if type(l.text) == "string" and l.text:find(L.KEY_ROTATE, 1, true) and l.tooltip then line = l end end
			assert(line, label .. ": the Throne's rotate line")
			local tip = {}
			line.tooltip({ AddLine = function(_, t) tip[#tip + 1] = t end })
			eq(tip[2], forever and L.KEY_ROTATE_TIP_FOREVER or L.KEY_ROTATE_TIP, label .. ": its tooltip")
			K.RotatePrompt()
			local which = forever and "OLYMPUS_KEY_ROTATE_FOREVER" or "OLYMPUS_KEY_ROTATE"
			eq(shown[#shown] and shown[#shown].which, which, label .. ": the question")
			eq(shown[#shown].a, tostring(math.ceil(K.GRACE / 60)), label .. ": with its minutes")
			eq(StaticPopupDialogs[which].text, forever and L.KEY_ROTATE_CONFIRM_FOREVER or L.KEY_ROTATE_CONFIRM, label .. ": its words")
			-- Its Yes starts the rotation, as the old question's does.
			StaticPopupDialogs[which].OnAccept()
			assert(K.Rotation() and K.Rotation().picking, label .. ": the rotation begun")
		end
	end)
	for k in pairs(StaticPopupDialogs) do if tostring(k):find("^OLYMPUS_KEY_") then StaticPopupDialogs[k] = nil end end
	for k, v in pairs(savedDialogs) do StaticPopupDialogs[k] = v end
	if not ok then error(err, 0) end
	-- The Forever words: nobody moves channel, the public channel, the typed chat lines; never a seal or an old channel.
	for _, k in ipairs({ "KEY_ROTATE_TIP_FOREVER", "KEY_ROTATE_CONFIRM_FOREVER", "KEY_ROTATE_ONLY_KING_FOREVER" }) do
		assert(L[k]:find("typed chat lines", 1, true) and L[k]:find("public Olympus channel", 1, true), k)
		assert(not L[k]:find("seal", 1, true) and not L[k]:find("old channel", 1, true), k)
	end
	for _, k in ipairs({ "KEY_ROTATE_TIP_FOREVER", "KEY_ROTATE_CONFIRM_FOREVER" }) do assert(L[k]:find("nobody moves channel", 1, true), k) end
	InEveryLanguage({ "KEY_ROTATE_TIP_FOREVER", "KEY_ROTATE_CONFIRM_FOREVER", "KEY_ROTATE_ONLY_KING_FOREVER" })
end)
