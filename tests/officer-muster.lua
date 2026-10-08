local ns, test, eq, H = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]officer%-muster%.lua$")) or "./"

local function World(fn)
	local w = { clock = 1800000000, now = 1000, guild = "Olympus Ember", map = 1429, member = true, logged = true,
		roles = { ["Harbor Lord-Realm"] = "lord" }, sources = {}, links = {}, jobs = {}, handlers = {}, events = {}, hidden = {}, barred = {} }
	local c = setmetatable({ me = "Harbor Lord-Realm", realm = "Realm", group = "Realm", faction = "Alliance", db = {},
		rdb = { guilds = {} }, L = setmetatable({}, { __index = ns.L }), RealmPages = {} }, { __index = ns })
	w.c = c
	c.Now = function() return w.now end
	c.FullName = function(name) return name and (name:find("-", 1, true) and name or name .. "-Realm") end
	c.RealmOf = function(name) return name and name:match("%-(.+)$") end
	c.GroupOf = function(realm) return w.links[realm] or realm end
	c.DisplayName = function(name) return name and name:gsub("%-Realm$", "") end
	c.IsMember = function() return w.member end
	c.IsFederation = function(guild) return type(guild) == "string" and guild:find("Olympus", 1, true) ~= nil end
	c.IsKingCharacter = function(name) return w.roles[c.FullName(name)] == "king" end
	c.IsKingGuild = function() return false end
	c.ViewAs = { Previewing = function() return w.preview == true end }
	c.King = { IsKing = function() return w.roles[c.me] == "king" end,
		SharingLocation = function() return w.crownSharing == true end,
		IsStewardName = function(name) return w.roles[c.FullName(name)] == "steward" end,
		IsHandName = function(name) return w.roles[c.FullName(name)] == "hand" end }
	c.WatchChat = { Barred = function(_, name) return w.barred[name or c.me] == true end }
	c.Moderation = { Hides = function(name) return w.hidden[name] and {} or nil end }
	c.Roster = { MyRank = function() return w.roles[c.me] == "lord" and 0 or 3 end,
		IsOfficer = function() return w.roles[c.me] == "lord" or w.roles[c.me] == "king" end,
		RankOf = function(name) return w.roles[c.FullName(name)] == "lord" and 0 or nil end }
	c.Data = { ServerTime = function() return w.clock end, Summary = function() return { guilds = {} } end,
		KnownRank = function() return nil end,
		AuthorizedRank = function(name)
			local role = w.roles[c.FullName(name)]
			return role == "lord" and 0 or (role == "captain" and 1 or nil), w.sources[name] or "roster"
		end }
	c.Zones = { NameForKey = function(key) return key == "m1429" and "Elwynn Forest" or "Westfall" end }
	c.UI = { RefreshSoon = function() w.refreshes = (w.refreshes or 0) + 1 end }
	c.Views = { ShowPage = function(key) w.page = key end, PageShown = function() return w.page end }
	c.Comm = { Handle = function(prefix, handler) w.handlers[prefix] = handler end, Hello = function() end,
		DeliveredLogged = function() return w.logged end,
		Send = function(dist, msg, key, urgent, logged, done, opts)
			if w.refuse and w.refuse(msg) then return false end
			w.jobs[#w.jobs + 1] = { dist = dist, msg = msg, logged = logged, opts = opts }; return true
		end }
	c.On = function(event, callback) w.events[event] = w.events[event] or {}; table.insert(w.events[event], callback) end
	c.Fire = function(event, ...) for _, callback in ipairs(w.events[event] or {}) do callback(...) end end
	c.Every, c.After = function() end, function() end
	c.RegisterEvent, c.Log = function() end, function() end
	c.Print = function(text) w.printed = text end
	c.ShowDialog, c.Alert = function() error("a quiet muster must not open a popup or alert") end, function() error("no muster alert") end
	c.Filter = { Hides = function(text) return text == w.filteredTitle end }
	local saved = { guild = GetGuildInfo, inside = IsInInstance, inGuild = IsInGuild, unit = UnitGUID,
		map = C_Map, info = C_ChatInfo, time = GetServerTime, locale = GetLocale, dialog = StaticPopupDialogs.OLYMPUS_LOCATION_CHOICE }
	GetGuildInfo, IsInGuild = function() return w.guild end, function() return w.member end
	IsInInstance = function() return false end
	UnitGUID = function() return "Creature-0-0-0-11-1-1" end
	GetServerTime, GetLocale = function() return w.clock end, function() return "enUS" end
	C_ChatInfo = { SendAddonMessageLogged = function() end }
	C_Map = { GetBestMapForUnit = function() return w.map end,
		GetMapInfo = function(id) if id == 1429 or id == 1436 then return { mapType = 3 } end; if id == 947 then return { mapType = 1 } end end,
		GetPlayerMapPosition = function() error("a muster must not read precise coordinates") end }
	for _, file in ipairs({ "Locales/OfficerMusterText", "Layers", "Chronicle", "OfficerMuster" }) do
		assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c)
	end
	function w.advance(seconds) w.clock, w.now = w.clock + seconds, w.now + seconds end
	function w.word(by, seq, title, zone, at, group, faction)
		w.roles[by] = w.roles[by] or "lord"
		return ("OM~1~P~%s~%s~%d~%d~Olympus Ember~%d~%s"):format(faction or "A", group or "Realm", seq or w.clock, at or w.clock, zone or 1429, title or "Gather")
	end
	function w.receive(by, msg, dist) return w.handlers.OM(dist or "CHANNEL", by, msg) end
	function w.endWord(seq, at) return ("OM~1~E~A~Realm~%d~%d"):format(seq, at) end
	local ok, err = pcall(fn, w, c)
	GetGuildInfo, IsInInstance, IsInGuild, UnitGUID, C_Map, C_ChatInfo, GetServerTime, GetLocale = saved.guild, saved.inside, saved.inGuild, saved.unit, saved.map, saved.info, saved.time, saved.locale
	StaticPopupDialogs.OLYMPUS_LOCATION_CHOICE = saved.dialog
	if not ok then error(err, 0) end
end

test("Officer muster: zone observation count uses consent, fresh existing records and immediate withdrawal without a census", function()
	World(function(w, c)
		local layers = c.Layers
		layers.Observe("target")
		eq(layers.ForMap(1429)[1].count, 1, "the personal layer view deliberately includes private self")
		eq(layers.CountSharedInZone(1429), 0, "private local self is not a public headcount")
		layers.Receive("Willow Scout-Realm", { guild = w.guild, mapID = 1429, zoneUID = 11 })
		layers.Receive("River Scout-Realm", { guild = w.guild, mapID = 1429, zoneUID = 12 })
		layers.Receive("Foreign Scout-Unlinked", { guild = w.guild, mapID = 1429, zoneUID = 12 })
		eq(layers.CountSharedInZone(1429), 2, "both layers in the zone, each observed character once")
		layers.Receive(c.me, { guild = w.guild, mapID = 1429, zoneUID = 11 })
		eq(layers.CountSharedInZone(1429), 2, "a self echo cannot bypass consent")
		layers.SetSharing(true); eq(layers.CountSharedInZone(1429), 3, "consented self counts once")
		layers.SetSharing(false); eq(layers.CountSharedInZone(1429), 2)
		layers.Receive("Willow Scout-Realm", { guild = w.guild, mapID = 1436, zoneUID = 20 })
		eq(layers.CountSharedInZone(1429), 1); eq(layers.CountSharedInZone(1436), 1)
		w.handlers.L0("CHANNEL", "River Scout-Realm", "L0~")
		eq(layers.CountSharedInZone(1429), 0, "withdrawal removes the observation immediately")
		local sent = #w.jobs
		w.advance(1261); eq(layers.CountSharedInZone(1436), 0, "expired observations count nowhere")
		eq(#w.jobs, sent, "reading counts sends no additional census or per-player packet")
		w.roles[c.me], w.crownSharing = "king", false
		c.db.shareLocation = true; layers.Observe("target")
		eq(layers.CountSharedInZone(1429), 0, "the King's sharing switch, not the ordinary preference, controls consent")
		w.crownSharing = true; eq(layers.CountSharedInZone(1429), 1)
	end)
end)

test("Officer muster: current King, Steward, Hand and verified Lord may post; captain, census role, preview and sanctions may not", function()
	for _, role in ipairs({ "king", "steward", "hand", "lord" }) do World(function(w, c)
		w.roles[c.me] = role
		eq(c.OfficerMuster.Post("Gather for patrol", 1429), true, role)
		eq(#c.OfficerMuster.List(), 1); eq(#c.Chronicle.Entries(), 0, "one ending line, not a new beginning history")
		local job = w.jobs[1]; eq(job.dist, "CHANNEL"); eq(job.logged, true); assert(#job.msg <= 255)
		eq(job.opts.guard(), true)
		w.roles[c.me] = "captain"; eq(job.opts.guard(), false, "queued authority is checked again")
		c.OfficerMuster.Tick(); eq(#c.OfficerMuster.List(), 0)
		eq(#c.Chronicle.Entries(), 0, "role loss removes quietly, without revealing inferred role history")
	end) end
	World(function(w, c)
		w.roles[c.me] = "captain"; eq(c.OfficerMuster.Post("Denied", 1429), false)
		w.roles[c.me], w.sources[c.me] = "lord", "census"; eq(c.OfficerMuster.Post("Denied", 1429), false)
		w.sources[c.me], w.preview = "signed", true; eq(c.OfficerMuster.Post("Denied", 1429), false)
		w.preview, w.barred[c.me] = false, true; eq(c.OfficerMuster.Post("Denied", 1429), false)
		w.barred[c.me] = false; eq(c.OfficerMuster.Post("Allowed", 1429), true)
	end)
end)

test("Officer muster: exact faction and linked realm group, logged channel, valid title and zone are required before budgets", function()
	World(function(w, c)
		local M, by = c.OfficerMuster, "River Lord-Realm"
		eq(select(2, w.receive(by, w.word(by, 1, "Gather", 1429, w.clock, "Other"))), "scope")
		eq(select(2, w.receive(by, w.word(by, 1, "Gather", 1429, w.clock, "Realm", "H"))), "scope")
		eq(select(2, w.receive("River Lord-Unlinked", w.word("River Lord-Unlinked", 1))), "realm")
		eq(select(2, w.receive(by, w.word(by, 1), "GUILD")), "shape")
		w.logged = false; eq(select(2, w.receive(by, w.word(by, 1))), "unlogged"); w.logged = true
		for _, title in ipairs({ "bad|title", "bad~title", "", string.rep("x", M.TITLE_MAX + 1) }) do
			eq(select(2, w.receive(by, w.word(by, 1, title))), "shape")
		end
		for _, zone in ipairs({ 947, 999999 }) do eq(select(2, w.receive(by, w.word(by, 1, "Gather", zone))), "shape") end
		for _, at in ipairs({ w.clock + M.DATE_AHEAD + 1, w.clock - M.LIFE }) do eq(select(2, w.receive(by, w.word(by, 1, "Gather", 1429, at))), "time") end
		for i = 1, M.RATE_ALL + 5 do
			local stranger = "Plain" .. i .. "-Realm"
			local msg = w.word(stranger, 1); w.roles[stranger] = "member"
			eq(select(2, w.receive(stranger, msg)), "role")
			eq(select(2, w.receive(by, w.word(by, 1, "bad|title"))), "shape")
		end
		eq(w.receive(by, w.word(by, 1)), true, "unauthorized and malformed payloads did not exhaust the shared budget")
		w.links.LinkedRealm = "Realm"
		eq(w.receive("Dawn Hand-LinkedRealm", w.word("Dawn Hand-LinkedRealm", 1)), true, "only an explicitly linked realm shares this group")
		eq(#M.List(), 2)
	end)
end)

test("Officer muster: repeat never renews expiry; withdrawal and reload preserve one attributed ending even after Chronicle eviction", function()
	World(function(w, c)
		local M, by = c.OfficerMuster, "River Lord-Realm"
		local msg = w.word(by, 1, "River patrol")
		eq(w.receive(by, msg), true)
		local row = M.List()[1]; w.advance(100)
		eq(select(2, w.receive(by, msg)), "repeat"); eq(row.at + M.LIFE, 1800001200)
		local ending = w.endWord(row.seq, row.at)
		eq(w.receive("Another Lord-Realm", ending), false, "only the server-stamped poster can close that call")
		eq(w.receive(by, ending), true); eq(#c.Chronicle.Entries(), 1)
		local entry = c.Chronicle.Entries()[1]; eq(entry.by, by); eq(entry.words, "River patrol")
		assert(loadfile(ROOT .. "Olympus/OfficerMuster.lua"))("Olympus", c)
		M = c.OfficerMuster
		eq(select(2, w.receive(by, ending)), "repeat"); eq(select(2, w.receive(by, msg)), "older")
		c.rdb.acts = {}; c.rdb.actsState = {}
		eq(select(2, w.receive(by, ending)), "repeat"); eq(#c.Chronicle.Entries(), 0, "a forgotten Chronicle row cannot recreate the ending")
		w.advance(M.LIFE)
		eq(select(2, w.receive(by, msg)), "time"); eq(select(2, w.receive(by, ending)), "time")
		eq(#M.List(), 0); eq(#c.Chronicle.Entries(), 0, "expired unknown calls never invent history")
	end)
end)

test("Officer muster: expiration and role loss close known calls once; ending headcount is consent-aware", function()
	World(function(w, c)
		local M = c.OfficerMuster
		c.Layers.Observe("target")
		c.Layers.Receive("Willow Scout-Realm", { guild = w.guild, mapID = 1429, zoneUID = 11 })
		eq(M.Post("Patrol", 1429), true)
		w.advance(M.LIFE)
		M.Tick(); eq(#M.List(), 0); eq(#c.Chronicle.Entries(), 1)
		local entry = c.Chronicle.Entries()[1]
		eq(entry.by, c.me); assert(entry.what:find("1 observed sharing players", 1, true), entry.what)
		assert(loadfile(ROOT .. "Olympus/OfficerMuster.lua"))("Olympus", c)
		c.OfficerMuster.Tick(); eq(#c.Chronicle.Entries(), 1)
		local by = "Dawn Hand-Realm"; w.roles[by] = "hand"
		eq(w.receive(by, w.word(by, 1, "Gather")), true)
		w.roles[by] = nil; c.Fire("THRONE_CHANGED")
		eq(#c.OfficerMuster.List(), 0); eq(#c.Chronicle.Entries(), 1, "role loss is not a public Chronicle inference")
	end)
end)

test("Officer muster: bounded queues and replay floors refuse floods without forgetting live history; refused sends remain retryable", function()
	World(function(w, c)
		local M = c.OfficerMuster
		w.refuse = function(msg) return msg:sub(1, 3) == "OM~" end
		eq(select(2, M.Post("Patrol", 1429)), "queue"); eq(#M.List(), 0)
		w.refuse = nil; eq(M.Post("Patrol", 1429), true)
		eq(select(2, M.Post("Replacement", 1429)), "rate")
		w.refuse = function(msg) return msg:sub(1, 3) == "OM~" end
		eq(select(2, M.Withdraw()), "queue"); eq(#M.List(), 1); eq(#c.Chronicle.Entries(), 0)
		w.refuse = nil; eq(M.Withdraw(), true); eq(#M.List(), 0); eq(w.jobs[#w.jobs].opts.guard(), true)
		for i = 1, M.MAX do local by = "Caller" .. i .. "-Realm"; assert(w.receive(by, w.word(by, 1))) end
		eq(select(2, w.receive("Overflow-Realm", w.word("Overflow-Realm", 1))), "full"); eq(#M.List(), M.MAX)
		local s = c.rdb.officerMuster
		assert(w.receive("Caller1-Realm", w.endWord(1, w.clock)))
		local count = 0; for _ in pairs(s.floors) do count = count + 1 end
		for i = 1, M.FLOORS_MAX - count do s.floors["retained" .. i] = { seq = 1, at = w.clock, ended = true } end
		w.advance(61)
		eq(select(2, w.receive("Flooroverflow-Realm", w.word("Flooroverflow-Realm", 1))), "full")
		eq(w.receive("Caller2-Realm", w.word("Caller2-Realm", 2)), true, "a full floor map may update an already known poster")
		count = 0; for _ in pairs(s.floors) do count = count + 1 end; eq(count, M.FLOORS_MAX)
		assert(s.floors.retained1, "live floors were not evicted")
	end)
end)

test("Officer muster: authorized new-poster floods are capped even when every accepted call is immediately ended", function()
	World(function(w, c)
		local M = c.OfficerMuster
		for i = 1, M.RATE_ALL do
			local by = "Caller" .. i .. "-Realm"
			eq(w.receive(by, w.word(by, 1)), true)
			eq(w.receive(by, w.endWord(1, w.clock)), true)
		end
		eq(select(2, w.receive("Floodcaller-Realm", w.word("Floodcaller-Realm", 1))), "rate")
		eq(#M.List(), 0)
		w.advance(60)
		eq(w.receive("Freshcaller-Realm", w.word("Freshcaller-Realm", 1)), true, "the next legitimate window remains usable")
	end)
end)

test("Officer muster: queued post and ending guards reject membership, guild, role and stale-scope reentry", function()
	for _, ending in ipairs({ false, true }) do World(function(w, c)
		local M = c.OfficerMuster
		assert(M.Post("Patrol", 1429))
		if ending then assert(M.Withdraw()) end
		local guard = w.jobs[#w.jobs].opts.guard
		eq(guard(), true)
		w.member = false; eq(guard(), false); w.member = true
		w.guild = "Olympus Willow"; eq(guard(), false); w.guild = "Olympus Ember"
		w.roles[c.me] = "captain"; eq(guard(), false); w.roles[c.me] = "lord"
		local me = c.me; c.me = "Other Lord-Realm"; eq(guard(), false); c.me = me
		c.group = "Other"; M.List(); eq(guard(), false)
		c.group = "Realm"; M.List(); eq(guard(), false, "returning to a scope cannot revive a job from its detached store")
	end) end
end)

test("Officer muster: Realm rows require explicit posting, expose zone-only sampled counts, and never open a surprise popup", function()
	World(function(w, c)
		local M = c.OfficerMuster
		eq(c.RealmPages[1].key, "officermuster"); M.Link().onClick(); eq(w.page, "officermuster")
		local lines = M.Lines()
		eq(#w.jobs, 0, "opening and reading the page sends nothing")
		local title, zone, post
		for _, line in ipairs(lines) do
			if line.input then title = line end
			if line.text == c.L.OFFICER_MUSTER_USE_ZONE then zone = line end
			if line.text == c.L.OFFICER_MUSTER_POST then post = line end
		end
		assert(title and zone and post)
		title.input.onChange(" Patrol\n preparation|~ "); zone.onClick()
		eq(#w.jobs, 0, "editing a draft and choosing a zone are local")
		post.onClick(); eq(#w.jobs, 1); eq(M.List()[1].title, "Patrol preparation")
		local result = M.Lines(); local observed, ending
		for _, line in ipairs(result) do
			if line.right then observed = line.right end
			if line.text == c.L.OFFICER_MUSTER_END then ending = line end
		end
		assert(observed:find("0 observed sharing players", 1, true)); assert(ending)
		ending.onClick(); eq(#M.List(), 0); eq(#c.Chronicle.Entries(), 1)
		w.member = false; eq(M.Link(), nil); eq(#M.Lines(), 0)
	end)
end)

test("Officer muster: actual Realm row renderer edits and clicks in mouse and gamepad modes without native popups", function()
	assert(H and H.WithUI and H.WithGamepadUI, "the harness supplies the existing UI helpers")
	for _, gamepad in ipairs({ false, true }) do
		H.WithUI(function()
			H.WithGamepadUI(gamepad, function(game)
				World(function(w, c)
					local M = c.OfficerMuster
					local content = CreateFrame("Frame", nil, UIParent)
					content:SetWidth(600); content.style = "hd"
					ns.Views.Render(content, M.Lines())
					local box = assert(content.input)
					box:SetText("Rendered patrol")
					box:Fire("OnTextChanged", true) -- the stand-in's SetText does not synthesize Blizzard's typing event
					local choose, post
					for _, row in ipairs(content.rows) do
						if row.line.text == c.L.OFFICER_MUSTER_USE_ZONE then choose = row end
						if row.line.text == c.L.OFFICER_MUSTER_POST then post = row end
					end
					assert(choose and post); choose:Click(); eq(#w.jobs, 0, "rendering and editing never publish")
					post:Click(); eq(#w.jobs, 1); eq(M.List()[1].title, "Rendered patrol")
					w.roles[c.me] = "captain"; post:Click(); eq(#w.jobs, 1, "stale visible actions recheck the current role")
					ns.Views.Render(content, M.Lines()); eq(#M.List(), 0); eq(#c.Chronicle.Entries(), 0)
					if gamepad then eq(#game.shown, 0, "no native popup under the gamepad UI") end
				end)
			end)
		end)
	end
end)

test("Officer muster: English and pt-BR text preserve placeholders", function()
	local texts = {}
	local old = GetLocale
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		GetLocale = function() return locale end
		local c = { L = {} }; assert(loadfile(ROOT .. "Olympus/Locales/OfficerMusterText.lua"))("Olympus", c); texts[locale] = c.L
	end
	GetLocale = old
	for key, value in pairs(texts.enUS) do
		assert(type(texts.ptBR[key]) == "string", key)
		local function Formats(s) local out = {}; for f in s:gmatch("%%[sd]") do out[#out + 1] = f end; return table.concat(out) end
		eq(Formats(value), Formats(texts.ptBR[key]), key)
	end
end)
