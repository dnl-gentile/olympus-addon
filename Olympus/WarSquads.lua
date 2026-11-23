local _, ns = ...
local Squads = {}
ns.WarSquads = Squads

-- Small military squads are NOT the War Room's historical capability-post Centuries.
-- WU~1~S~leader~revision~members: a complete bounded assignment, over actual GUILD.
-- WU~1~Q: request current assignments; only current own-guild officers answer (1.2.0: one of
-- them, the first by name of those heard on WU lately, once a minute, on the normal lane).
-- SC~1~room-hash~sequence~words: logged private WHISPER, never a guild broadcast.
Squads.MAX_SOLDIERS, Squads.MAX_MEMBERS, Squads.MAX_LEADERS = 39, 40, 25
Squads.LEGACY_MAX_SOLDIERS = 99 -- old saved assignments are retained, never silently trimmed
Squads.MAX_ROWS, Squads.MAX_GUILDS, Squads.CHAT_MAX = 40, 20, 100
Squads.SEEN_MAX = 1000
Squads.ASK_GAP, Squads.ASKS = 300, 3  -- 1.2.0: a client's asks: this far apart, this many a session
Squads.REPLY_GAP = 60                 -- ...an officer answers once a window
Squads.ELECT_FOR = 1800               -- ...the one first by name of the officers heard on WU this lately
local incoming, outgoing, chatRate = {}, {}, {}
local heardOfficers, asks, answered = {}, 0, false
local roomCache, roomCacheCount = {}, 0
local memberIndex, indexedRoster, indexedNames, indexedGeneration, indexedAt = {}, nil, nil, nil, nil
local onlineIndex, onlineRoster, onlineRows, onlineGeneration, onlineAt = {}, nil, nil, nil, nil
local lastRequest = -math.huge
local function Now() return GetServerTime and GetServerTime() or ns.Now() end
local function Clock() return GetTime and GetTime() or ns.Now() end
local function Int(x) return type(x) == "number" and x == math.floor(x) and x >= 0 and x < 2147483648 end
local function Fold(s) return ns.Fold(s) end
local function Full(s)
	if type(s) ~= "string" or #s < 2 or #s > 72 or s:find("[~|,%c]") then return nil end
	return ns.FullName(s)
end
local function Guild()
	local guild = IsInGuild and IsInGuild() and GetGuildInfo("player")
	if ns.IsMember() ~= true or type(guild) ~= "string" or not ns.IsFederation(guild) then return nil end
	local roster = ns.Roster
	return roster and roster.Fresh and roster.Fresh() and guild or nil
end
local function Member(name)
	if not ns.SharedPeerAllowed(name, Guild()) then return nil end
	local full = Full(name)
	if not full or not Guild() then return nil end
	local roster, names = ns.Roster, ns.Roster.byName
	if names[full] then return full end
	if indexedRoster ~= roster or indexedNames ~= names or indexedGeneration ~= roster.generation or indexedAt ~= roster.snapshotAt then
		memberIndex = {}; for known in pairs(names) do memberIndex[Fold(known)] = known end
		indexedRoster, indexedNames, indexedGeneration, indexedAt = roster, names, roster.generation, roster.snapshotAt
	end
	local known = memberIndex[Fold(full)]
	return known and names[known] and known or nil
end
local function Preview()
	local v = ns.ViewAs
	if v and v.Previewing and v.Previewing() then return true end
	if v and v.Available and v.Available() and v.Role and v.Role() ~= "my" then return true end
	return ns.King and ns.King.Preview and ns.King.Preview() == true or false
end
local function Officer(name)
	name = Member(name)
	if not name then return false end
	local rank = ns.Roster.RankOf(name)
	if rank and rank <= ns.CAPTAIN_RANK then return true end
	if ns.War and ns.War.IsWarCouncillor and ns.War.IsWarCouncillor(name) then return true end
	local n = ns.Nominees
	return n and n.IsCorrespondent and n.IsCorrespondent(name, Guild(), "Department of War") == true or false
end
local Leader
function Squads.CanManage()
	return not Preview() and (Officer(ns.me) or (Leader and Leader(ns.me) ~= nil)) and not (ns.ChatLocked and ns.ChatLocked()) or false
end
local function CanEdit(name)
	return Squads.CanManage() and (Officer(ns.me) or Fold(ns.me) == Fold(name)) or false
end
local function Rate(map, key, max, window)
	local now, list = Clock(), map[key] or {}
	map[key] = list
	for i = #list, 1, -1 do if now - list[i] >= window then table.remove(list, i) end end
	if #list >= max then return false end
	list[#list + 1] = now
	return true
end
local function Store(make)
	local guild = Guild()
	if not guild or not ns.rdb then return nil end
	local all = ns.rdb.warSquads
	if all == nil and make then all = {}; ns.rdb.warSquads = all end
	if type(all) ~= "table" then return nil end
	local key, s = Fold(guild), all[Fold(guild)]
	if s == nil and make then
		local count = 0; for _ in pairs(all) do count = count + 1 end
		if count >= Squads.MAX_GUILDS then return nil end
		s = { guild = guild, rows = {}, chats = {} }; all[key] = s
	end
	return type(s) == "table" and s.guild == guild and type(s.rows) == "table" and type(s.chats) == "table" and s or nil
end
-- (1.2.3: found first by the names as given, roomOf, without folding them: each census notice
-- reads the leaders, Signature, and so does the Chat tab's ticker on a squad's room.)
local roomOf, roomOfCount = {}, 0 -- guild -> leader -> room
local function Room(guild, leader)
	local known = roomOf[guild]
	if known and known[leader] then return known[leader] end
	local key = Fold(guild) .. "|" .. Fold(leader)
	local room = roomCache[key]
	if not room then
		local digest = ns.Sign.SHA256(key)
		room = "squad:" .. (digest:sub(1, 12):gsub(".", function(byte) return ("%02x"):format(byte:byte()) end))
		if roomCacheCount < 256 then roomCache[key], roomCacheCount = room, roomCacheCount + 1 end
	end
	if roomOfCount < 256 then
		if not known then known = {}; roomOf[guild] = known end
		known[leader], roomOfCount = room, roomOfCount + 1
	end
	return room
end
function Squads.Leaders()
	local guild, list, seen = Guild(), {}, {}
	if not guild then return list end
	local function Add(name)
		local full = Member(name)
		local key = full and Fold(full) -- (1.2.3: folded once; each census notice reads the leaders, Signature)
		if not full or seen[key] or #list >= Squads.MAX_LEADERS then return end
		seen[key] = true
		list[#list + 1] = { name = full, index = #list + 1, kind = "centurion", room = Room(guild, full) }
	end
	local n = ns.Nominees
	local nominees = n and n.ListOf and n.ListOf(guild)
	if not nominees or not n.Proven or n.Proven(nominees.by, guild) ~= true then return list end
	if not (ns.IsKingGuild and ns.IsKingGuild(guild)) then
		local master = Member(nominees.by)
		if not master or ns.Roster.RankOf(master) ~= 0 then return list end
	end
	for _, e in ipairs(nominees.entries or {}) do
		if e.role == "centurion" and n.RoleOf(e.name, guild) == "centurion" then Add(e.name) end
	end
	return list
end
Leader = function(name)
	local full = Member(name)
	if not full then return nil end
	for _, e in ipairs(Squads.Leaders()) do if Fold(e.name) == Fold(full) then return e end end
end
-- (1.2.3: every squad's room is "squad:" and its hash, Room. ChatRooms asks each provider about every
-- room id it is given, the race, class, guild and role rooms' too, and the Chat page gave it a few
-- hundred a redraw, each reading the leaders again: on the author's game, in the King's guild, most of
-- the 2.5 MB of garbage each redraw made. An id that is not a squad's is none, the leaders unread.)
local function LeaderRoom(id)
	if type(id) ~= "string" or not id:find("^squad:") then return nil end
	for _, e in ipairs(Squads.Leaders()) do if e.room == id then return e end end
end
local function Dense(array, max)
	if type(array) ~= "table" then return nil end
	local count, highest = 0, 0
	for key in pairs(array) do
		if not Int(key) or key < 1 or key > max then return nil end
		count, highest = count + 1, math.max(highest, key)
		if count > max then return nil end
	end
	return count == highest and count or nil
end
local function ValidRow(row)
	if type(row) ~= "table" or not Int(row.rev) or not Full(row.leader) or Full(row.leader) ~= row.leader then return false end
	local count = Dense(row.members, Squads.LEGACY_MAX_SOLDIERS)
	if count == nil then return false end
	local seen = {}
	for i = 1, count do
		local name = row.members[i]
		if not Full(name) or Full(name) ~= name or Fold(name) == Fold(row.leader) or seen[Fold(name)] then return false end
		seen[Fold(name)] = true
	end
	return true
end
local function List(leader, members)
	if Dense(members, Squads.MAX_SOLDIERS) == nil then return nil end
	local out, seen = {}, {}
	for i, name in ipairs(members) do
		local full = Member(name)
		if not full or Fold(full) == Fold(leader) or seen[Fold(full)] then return nil end
		seen[Fold(full)], out[i] = true, full
	end
	for key in pairs(members) do if not Int(key) or key < 1 or key > #out then return nil end end
	table.sort(out, function(a, b) return Fold(a) < Fold(b) end)
	return out
end
local function Encode(e) return ("WU~1~S~%s~%d~%s"):format(e.leader, e.rev, table.concat(e.members, ",")) end
local told      -- (1.2.3) what the squads' rooms rested on when they were last told changed (Signature's)
local Signature -- (below)
-- now: Signature's, when the caller has it already.
local function Changed(now)
	told = now or Signature()
	ns.Fire("SQUADS_CHANGED"); ns.Fire("CHAT_ROOMS_CHANGED")
end
-- Reuse the native member rows, once per snapshot rather than rescanning the guild per group.
-- A missing/nonboolean status stays unknown; the same member may support more than one group.
local function OnlineCounts(leader, soldiers)
	local R = ns.Roster
	if onlineRoster ~= R or onlineRows ~= R.members or onlineGeneration ~= R.generation or onlineAt ~= R.snapshotAt then
		onlineIndex = {}
		for _, row in ipairs(R.members or {}) do
			local name = Full(row.full or row.raw or row.name)
			if name and type(row.online) == "boolean" then onlineIndex[Fold(name)] = row.online end
		end
		onlineRoster, onlineRows, onlineGeneration, onlineAt = R, R.members, R.generation, R.snapshotAt
	end
	local online, unknown = 0, 0
	local function Count(name)
		local value = onlineIndex[Fold(name)]
		if value == true then online = online + 1 elseif value == nil then unknown = unknown + 1 end
	end
	Count(leader)
	for _, name in ipairs(soldiers) do Count(name) end
	return online, unknown
end
local function Online(name)
	-- Squad() refreshes this cache before Lines reaches a member row.
	return onlineIndex[Fold(name)] == true
end
-- Leader entry `leader` (of Squads.Leaders) with his squad as its stored row has it (Squads.Get's).
local function Squad(leader)
	local s = Store(false)
	local row = s and s.rows[Fold(leader.name)]
	if not ValidRow(row) or Fold(row.leader) ~= Fold(leader.name) then row = nil end
	leader.soldiers = {}
	for _, soldier in ipairs(row and row.members or {}) do
		local current = Member(soldier)
		if current and Fold(current) ~= Fold(leader.name) then leader.soldiers[#leader.soldiers + 1] = current end
	end
	leader.count, leader.rev, leader.by = #leader.soldiers, row and row.rev, row and row.by
	leader.total = leader.count + 1
	leader.online, leader.onlineUnknown = OnlineCounts(leader.name, leader.soldiers)
	leader.overflow = row ~= nil and #row.members > Squads.MAX_SOLDIERS
	return leader
end
function Squads.Get(name)
	local leader = Leader(name)
	if not leader then return nil end
	return Squad(leader)
end
local function Put(e, sender)
	local s = Store(true)
	if not s then return false, "store" end
	local key, old = Fold(e.leader), s.rows[Fold(e.leader)]
	if old ~= nil and not ValidRow(old) then return false, "store" end
	if old and (e.rev < old.rev or e.rev == old.rev and Encode(e) <= Encode(old)) then return false, "old" end
	if not old then
		local count = 0; for _ in pairs(s.rows) do count = count + 1; if count >= Squads.MAX_ROWS then return false, "limit" end end
		-- Retain older assignments rather than destructively pruning history to make room.
		if count >= Squads.MAX_ROWS then return false, "limit" end
	end
	if old and #old.members > Squads.MAX_SOLDIERS then
		-- An explicit reviewed replacement preserves the original complete membership locally.
		-- No query serializes this archive and no automatic migration discards any member.
		if s.legacy == nil then s.legacy = {} end
		if type(s.legacy) ~= "table" or s.legacy[key] ~= nil then return false, "archive" end
		local count = 0; for _ in pairs(s.legacy) do count = count + 1 end
		if count >= Squads.MAX_ROWS then return false, "archive" end
		s.legacy[key] = old
	end
	e.by = sender; s.rows[key] = e
	Changed(); return true
end
local function SendRecord(e, low)
	if not ValidRow(e) or #e.members > Squads.MAX_SOLDIERS or not Leader(e.leader) or not CanEdit(e.leader) then return false end
	local guild, msg = Guild(), Encode(e)
	local key = "squad:" .. Fold(e.leader)
	local options = { owner = Squads, key = key, permit = function(_, guardKey, dist, target, currentMessage)
		if guardKey ~= key or dist ~= "GUILD" or target ~= nil or #msg <= 255 and currentMessage ~= msg then return false end
		local s = Store(false); local current = s and s.rows[Fold(e.leader)]
		return Guild() == guild and CanEdit(e.leader) and Leader(e.leader) ~= nil and ValidRow(current)
			and #current.members <= Squads.MAX_SOLDIERS and Encode(current) == msg or false
	end }
	-- (An officer's own edit goes urgent; an answer to an ask on the normal lane, 1.2.0.)
	if #msg <= 255 then return ns.Comm.Send("GUILD", msg, options.key, not low, false, nil, options) end
	return ns.Comm.SendChunked(msg, not low, "GUILD", nil, options)
end
function Squads.Replace(name, members, confirmed)
	if not Squads.CanManage() then return false, "officer" end
	local leader = Leader(name)
	if not leader then return false, "leader" end
	if not CanEdit(leader.name) then return false, "leader" end
	local list = List(leader.name, members)
	if not list then return false, "members" end
	local s = Store(true); if not s then return false, "store" end
	local old = s.rows[Fold(leader.name)]
	if old ~= nil and not ValidRow(old) then return false, "store" end
	if old and #old.members > Squads.MAX_SOLDIERS and confirmed ~= true then
		ns.ShowDialog("OLYMPUS_SQUAD_REPLACE", ns.ShortName(leader.name), nil,
			{ leader = leader.name, members = list, guild = Guild(), rev = old.rev })
		return false, "confirmation"
	end
	if not Rate(outgoing, "write", 20, 60) then return false, "rate" end
	local rev = math.max(Now(), old and old.rev + 1 or 0)
	if not Int(rev) or rev > Now() + 300 then return false, "revision" end
	local e = { leader = leader.name, members = list, rev = rev }
	if #Encode(e) > ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS then return false, "wire" end
	local ok, why = Put(e, ns.me)
	if not ok then return false, why end
	SendRecord(e); return true
end
function Squads.Assign(leader, soldier)
	local current = Squads.Get(leader)
	if not current then return false, "leader" end
	if current.overflow then return false, "overflow" end
	local full = Member(soldier)
	if not full then return false, "member" end
	for _, member in ipairs(current.soldiers) do if Fold(member) == Fold(full) then return false, "duplicate" end end
	current.soldiers[#current.soldiers + 1] = full
	return Squads.Replace(leader, current.soldiers)
end
function Squads.Remove(leader, soldier)
	local current, full = Squads.Get(leader), Full(soldier)
	if not current or not full then return false, "member" end
	if current.overflow then return false, "overflow" end
	local list = {}; for _, member in ipairs(current.soldiers) do if Fold(member) ~= Fold(full) then list[#list + 1] = member end end
	return Squads.Replace(leader, list)
end
function Squads.Handle(dist, sender, text)
	if dist ~= "GUILD" or not Guild() or type(text) ~= "string" or #text > ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS or not Member(sender) then return false end
	if not Rate(incoming, Fold(sender), 60, 60) then return false end
	if Officer(sender) then heardOfficers[Fold(Member(sender))] = Clock() end
	if text == "WU~1~Q" then
		if not Squads.CanManage() or not Officer(ns.me) then return false end
		-- (1.2.0: one officer answers, the first by name of those heard lately, this one included.)
		local mine, now = Fold(Member(ns.me)), Clock()
		for key, at in pairs(heardOfficers) do
			if now - at > Squads.ELECT_FOR then heardOfficers[key] = nil
			elseif key < mine and Officer(key) then return true, "other" end
		end
		if not Rate(outgoing, "reply", 1, Squads.REPLY_GAP) then return true, "window" end
		local s = Store(false)
		local checked = 0
		for key, row in pairs(s and s.rows or {}) do
			checked = checked + 1; if checked > Squads.MAX_ROWS then return false end
			if ValidRow(row) and key == Fold(row.leader) and Leader(row.leader) then SendRecord(row, true) end
		end
		return true
	end
	local name, revision, raw = text:match("^WU~1~S~([^~]+)~(%d+)~([^~]*)$")
	local leader, rev = name and Leader(name), tonumber(revision)
	if not leader or not Int(rev) or rev > Now() + 300 then return false end
	if not Officer(sender) and Fold(Member(sender)) ~= Fold(leader.name) then return false end
	local members = {}; for member in raw:gmatch("[^,]+") do members[#members + 1] = member end
	local list = List(leader.name, members)
	if not list or table.concat(list, ",") ~= raw then return false end
	answered = true
	return Put({ leader = leader.name, members = list, rev = rev }, Member(sender))
end
-- (1.2.0: at login, and after a roster scan only until an officer's rows came, ASKS at most a
-- session, ASK_GAP apart.)
function Squads.Request()
	if not Guild() or Clock() - lastRequest < Squads.ASK_GAP or answered or asks >= Squads.ASKS then return false end
	local guild = Guild(); lastRequest = Clock(); asks = asks + 1
	return ns.Comm.Send("GUILD", "WU~1~Q", "squads:query", false, false, nil, { owner = Squads, key = "squads:query",
		permit = function(_, key, dist, target, message)
			return key == "squads:query" and dist == "GUILD" and target == nil and message == "WU~1~Q"
				and Guild() == guild and Member(ns.me) ~= nil
		end })
end
-- Whether member `full` reads leader entry `leader`'s room: the leader himself, or one of his soldiers.
local function Reads(leader, full)
	if Fold(full) == Fold(leader.name) then return true end
	local current = Squad(leader)
	for _, soldier in ipairs(current.soldiers) do if Fold(soldier) == Fold(full) then return true end end
	return false
end
function Squads.CanReadHistory(room, name)
	if Preview() or not Member(ns.me) then return false end
	local leader, full = LeaderRoom(room), Member(name or ns.me)
	if not leader or not full then return false end
	return Reads(leader, full)
end
function Squads.CanAccess(room, name)
	if not Squads.CanReadHistory(room, name) then return false end
	return Squad(LeaderRoom(room)).overflow ~= true
end
local function ChatOn() return ns.SharedToolsHere() and ns.db and ns.db.chatRooms == true and not (ns.ChatLocked and ns.ChatLocked()) or false end
local function Chat(room, make)
	local s = Store(make)
	if not s then return nil end
	local chat = s.chats[room]
	if chat == nil and make then
		local count = 0; for _ in pairs(s.chats) do count = count + 1; if count >= Squads.MAX_ROWS then return nil end end
		chat = { seq = 0, lines = {}, seen = {} }; s.chats[room] = chat
	end
	if type(chat) ~= "table" or not Int(chat.seq) or type(chat.seen) ~= "table" then return nil end
	local count = Dense(chat.lines, Squads.CHAT_MAX)
	if count == nil then return nil end
	for i = 1, count do
		local line = chat.lines[i]
		if type(line) ~= "table" or not Full(line.sender) or type(line.text) ~= "string" or #line.text > 150
			or not Int(line.id) or line.id < 1 or not Int(line.t) then return nil end
	end
	local seen = 0
	for name, seq in pairs(chat.seen) do
		seen = seen + 1
		if seen > Squads.SEEN_MAX or not Full(name) or not Int(seq) or seq < 1 then return nil end
	end
	return chat
end
local function Words(text)
	if type(text) ~= "string" then return "" end
	return ns.Cut(ns.Codec.SanitizeChat(ns.Codec.Plain(text)):gsub("~", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""), 150)
end
-- unsent: our own line kept in the view before (or without) any whisper of it leaving; the
-- Companion's chat record (Bridge.lua) takes our own line only once one left (ChatSend's Mine).
local function Keep(room, e, unsent)
	local chat = Chat(room, true); if not chat then return end
	chat.lines[#chat.lines + 1] = e
	while #chat.lines > Squads.CHAT_MAX do table.remove(chat.lines, 1) end
	ns.Fire("CHAT_ROOM_CHANGED", room)
	if not e.mine then ns.Fire("CHAT_ROOM_LINE", room, e.sender, e.text) end
	if not unsent and ns.RecordChat then ns.RecordChat(room, e.sender, e.text, e.mine == true) end -- (the Companion's chat record, Bridge.lua)
end
function Squads.ChatHistory(room)
	local out = {}
	if not ChatOn() or not Squads.CanReadHistory(room) then return out end
	local chat = Chat(room, false)
	local moderation = ns.Moderation
	for _, line in ipairs(chat and chat.lines or {}) do
		if Squads.CanReadHistory(room, line.sender) and not (moderation and moderation.Hides and moderation.Hides(line.sender, Guild())) then out[#out + 1] = line end
	end
	return out
end
function Squads.ChatSend(room, text)
	if not ChatOn() or not Squads.CanAccess(room) then return false, "access" end
	text = Words(text); if text == "" then return false, "empty" end
	if not Rate(chatRate, "mine", 12, 60) then return false, "rate" end
	local leader, guild = LeaderRoom(room), Guild()
	local squad, chat = Squads.Get(leader.name), Chat(room, true)
	if squad.overflow then return false, "overflow" end
	if not chat or not Int(chat.seq) or chat.seq >= 2147483647 then return false, "sequence" end
	chat.seq = chat.seq + 1
	local seq, msg = chat.seq, ("SC~1~%s~%d~%s"):format(room:sub(7), chat.seq, text)
	local recipients = { leader.name }; for _, name in ipairs(squad.soldiers) do recipients[#recipients + 1] = name end
	-- left: one of its whispers left. A line kept before that (the leader alone, nobody to whisper)
	-- shows in the view but reaches the Companion's chat record only once one does, if ever.
	local kept, recorded, queued = false, false, false
	local function Mine(left)
		if Guild() ~= guild or not ChatOn() or not Squads.CanAccess(room) then return end
		if not kept then
			kept, recorded = true, left == true
			Keep(room, { sender = ns.me, guild = guild, text = text, t = Now(), mine = true, id = seq }, not recorded)
		elseif left and not recorded then
			recorded = true
			if ns.RecordChat then ns.RecordChat(room, ns.me, text, true) end
		end
	end
	for _, recipient in ipairs(recipients) do
		if Fold(recipient) ~= Fold(ns.me) then
			local to = recipient
			local guard = function() return Guild() == guild and ChatOn() and Squads.CanAccess(room) and Squads.CanAccess(room, to) end
			local ok = ns.Comm.Whisper(to, msg, "squad-chat:" .. room .. ":" .. seq .. ":" .. Fold(to), false, true,
				function(sent) if sent and guard() then Mine(true) end end, { owner = Squads, guard = guard })
			queued = ok or queued
		end
	end
	if #recipients == 1 then Mine(false); return true end
	return queued, queued and "ok" or "busy"
end
function Squads.ReceiveChat(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > 255 or not ChatOn() then return false end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then return false end
	local hash, sequence, words = text:match("^SC~1~(%x+)~(%d+)~(.+)$")
	local room, seq, full = hash and "squad:" .. hash, tonumber(sequence), Member(sender)
	if not hash or #hash ~= 24 or not Int(seq) or seq < 1 or not full or Fold(full) == Fold(ns.me)
		or Words(words) ~= words or not Squads.CanAccess(room) or not Squads.CanAccess(room, full) then return false end
	if Squad(LeaderRoom(room)).overflow then return false, "overflow" end
	if not Rate(chatRate, Fold(full), 24, 60) then return false end
	local chat = Chat(room, true)
	if not chat then return false, "store" end
	if seq <= (chat.seen[Fold(full)] or 0) then return false end
	if chat.seen[Fold(full)] == nil then
		local count = 0; for _ in pairs(chat.seen) do count = count + 1 end
		if count >= Squads.SEEN_MAX then return false, "limit" end
	end
	local admitted, why = ns.Channels.Admit(full, Guild(), words, Clock(), { id = room .. ":" .. Fold(full) .. ":" .. seq, chat = room, line = seq, level = 1 })
	if not admitted then return false, why end
	chat.seen[Fold(full)] = seq
	Keep(room, { sender = full, guild = Guild(), text = words, t = Now(), id = seq }); return true
end
local function RoomInfo(leader)
	local format = ns.L and ns.L.SQUAD_CHAT_LABEL or "Squad %d"
	return { id = leader.room, kind = "role", scope = "restricted", label = format:format(leader.index) }
end
function Squads.ChatInfo(room)
	local leader = LeaderRoom(room)
	if not leader then return nil end
	return RoomInfo(leader)
end
local provider = { Info = Squads.ChatInfo, CanAccess = Squads.CanAccess, History = Squads.ChatHistory,
	Send = Squads.ChatSend, ChatOn = ChatOn, IsOpen = function(room) return Squads.CanAccess(room) end,
	Select = function(room) return Squads.CanAccess(room) end,
	-- (1.2.3: the leaders read once, each room's access and description from its own entry: CanAccess
	-- and ChatInfo read them all again for each room, three times, and the Chat page asks every era.)
	Options = function(kind)
		local out = {}; if kind ~= "role" then return out end
		local me = not Preview() and Member(ns.me)
		if not me then return out end
		for _, e in ipairs(Squads.Leaders()) do if Reads(e, me) and not Squad(e).overflow then out[#out + 1] = RoomInfo(e) end end
		return out
	end,
}
Squads.ChatProvider = provider
local function Label(key, fallback) return ns.L and rawget(ns.L, key) or fallback end
function Squads.ShowHistory(room)
	if not Squads.CanReadHistory(room) then return false end
	local lines = Squads.ChatHistory(room)
	if #lines == 0 or not ns.UI or type(ns.UI.ShowCopy) ~= "function" then return false end
	local text = {}
	for _, line in ipairs(lines) do text[#text + 1] = ns.Codec.Plain(ns.DisplayName(line.sender)) .. ": " .. line.text end
	return ns.UI.ShowCopy(Label("SQUAD_HISTORY_READONLY", "Saved group conversation (read-only)"), table.concat(text, "\n"))
end
function Squads.ConfirmReplacement(data)
	if type(data) ~= "table" or data.guild ~= Guild() then return false end
	local s = Store(false)
	local row = s and s.rows[Fold(data.leader or "")]
	if not ValidRow(row) or row.rev ~= data.rev or #row.members <= Squads.MAX_SOLDIERS then return false end
	return Squads.Replace(data.leader, data.members, true)
end
function Squads.Review(name)
	local squad = Squads.Get(name)
	if not squad or not squad.overflow or not CanEdit(squad.name) then return false end
	return ns.ShowDialog("OLYMPUS_SQUAD_REVIEW", ns.ShortName(squad.name),
		Label("SQUAD_REVIEW_HINT", "Enter up to 39 current guildmates who agreed to join, separated by commas. No guild invitations or removals happen."),
		{ leader = squad.name, guild = Guild(), rev = squad.rev })
end
StaticPopupDialogs["OLYMPUS_SQUAD_REVIEW"] = {
	text = Label("SQUAD_REVIEW_TITLE", "Review legacy group: %s"),
	button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel", hasEditBox = true, editBoxWidth = 360,
	maxLetters = Squads.MAX_SOLDIERS * 73,
	OnShow = function(self)
		local edit = self.editBox or self.EditBox
		if edit then edit:SetText(""); edit:SetFocus() end
	end,
	OnAccept = function(self, data)
		data = data or (self and self.data)
		if type(data) ~= "table" or data.guild ~= Guild() then return false end
		local squad = Squads.Get(data.leader)
		if not squad or squad.rev ~= data.rev then return false end
		local edit = self and (self.editBox or self.EditBox)
		if not edit or not edit.GetText then return false end
		if #edit:GetText() > Squads.MAX_SOLDIERS * 73 then return false end
		local members = {}
		for name in (edit:GetText() .. ","):gmatch("([^,]*),") do
			name = name:gsub("^%s+", ""):gsub("%s+$", "")
			if name ~= "" then members[#members + 1] = name end
		end
		return Squads.Replace(data.leader, members)
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["OLYMPUS_SQUAD_REPLACE"] = {
	text = Label("SQUAD_REPLACE_CONFIRM", "Replace %s's oversized legacy group with the reviewed list? Only people who agreed should be listed. The full old membership will be archived privately. No guild invitations or removals happen."),
	button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
	OnAccept = function(self, data) return Squads.ConfirmReplacement(data or (self and self.data)) end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
function Squads.Lines(query, baseIndent, manage)
	local lines, indent = {}, baseIndent or 0
	local masked = ns.CouncilMasked and ns.CouncilMasked() == true and ns.IsKingGuild(Guild())
	local officer = manage ~= false and Squads.CanManage() and not masked
	for _, e in ipairs(Squads.Leaders()) do
		local squad, hit = Squads.Get(e.name), not query
		if query and not masked then
			hit = ns.Holds(query, e.name)
			for _, name in ipairs(squad.soldiers) do hit = hit or ns.Holds(query, name) end
		end
		if hit then
			local shown = masked and Label("SQUAD_COUNCILLOR", "Legate %d"):format(e.index) or ns.Codec.Plain(ns.ShortName(e.name))
			if not masked then shown = (e.kind == "councillor" and Label("SQUAD_LEADER_COUNCIL", "High Councillor - %s") or Label("SQUAD_LEADER_CENTURION", "Centurion - %s")):format(shown) end
			lines[#lines + 1] = { indent = indent, squadLeader = not masked and e.name or nil, text = shown,
				right = Label("SQUAD_TOTAL", "%d/40 members"):format(squad.total) }
			if not masked then
				local edit = officer and CanEdit(e.name)
				local online = squad.onlineUnknown > 0
					and Label("SQUAD_ONLINE_PARTIAL", "%d confirmed online / %d members · %d unknown"):format(squad.online, squad.total, squad.onlineUnknown)
					or Label("SQUAD_ONLINE_COUNT", "%d online / %d members"):format(squad.online, squad.total)
				lines[#lines + 1] = { indent = indent + 1, text = online, squadOnline = e.name }
				if squad.overflow then
					lines[#lines + 1] = { indent = indent + 1, text = Label("SQUAD_OVERFLOW", "Legacy group: %d/40 members; read-only until reviewed."):format(squad.total) }
					if Squads.CanReadHistory(e.room) and #Squads.ChatHistory(e.room) > 0 then
						local room = e.room
						lines[#lines + 1] = { indent = indent + 1, text = Label("SQUAD_HISTORY_READONLY", "Saved group conversation (read-only)"),
							readonlyHistory = room, onClick = function() return Squads.ShowHistory(room) end }
					end
					if edit then
						local name = e.name
						lines[#lines + 1] = { indent = indent + 1, text = Label("SQUAD_REVIEW", "Review legacy group"), onClick = function() return Squads.Review(name) end }
					end
				end
				for _, name in ipairs(squad.soldiers) do
					lines[#lines + 1] = { indent = indent + 1, player = name, text = ns.Codec.Plain(ns.ShortName(name)) }
					if edit and not squad.overflow and Online(name) and ns.PartyGuard and ns.PartyGuard.InviteGuildmate then
						local soldier = name
						lines[#lines + 1] = { indent = indent + 2, text = Label("SQUAD_INVITE", "Invite online member to raid"),
							onClick = function() return CanEdit(e.name) and ns.PartyGuard.InviteGuildmate(soldier) or false end }
					end
					if edit and not squad.overflow then
						local soldier, leader = name, e.name
						lines[#lines + 1] = { indent = indent + 2, text = Label("SQUAD_REMOVE", "Remove soldier"),
							onClick = function() return Squads.Remove(leader, soldier) end }
					end
				end
				if squad.count == 0 then lines[#lines + 1] = { indent = indent + 1, text = Label("SQUAD_EMPTY", "No soldiers assigned") } end
				if edit and not squad.overflow and squad.count < Squads.MAX_SOLDIERS then
					local leader = e.name
					lines[#lines + 1] = { indent = indent + 1, text = Label("SQUAD_ADD", "Assign soldier"), onClick = function()
						if not CanEdit(leader) or not Leader(leader) then return false end
						return ns.ShowDialog("OLYMPUS_WAR_INPUT", Label("SQUAD_ADD", "Assign soldier"), Label("SQUAD_HINT", "Name of a current member of your guild."), { prefix = "squadadd " .. leader .. "|" })
					end }
				end
				if not squad.overflow and Squads.CanAccess(e.room) then
					local room = e.room
					lines[#lines + 1] = { indent = indent + 1, text = Label("SQUAD_OPEN_CHAT", "Open private squad chat"),
						onClick = function()
							if ns.ChatRooms and ns.ChatRooms.OpenMatter and Squads.CanAccess(room) then return ns.ChatRooms.OpenMatter({ room = room, keep = false }) end
							return false
						end }
				end
			end
		end
	end
	if #lines > 0 then table.insert(lines, 1, { indent = indent, header = true, text = Label("SQUAD_TITLE", "Military squads - your guild") }) end
	return lines
end
-- 1.2.3: what the squads' rooms rest on, as one text: our guild, our own place (in the roster, a
-- preview, the chats on) and each leader's room, kind and place in the list (his room's label).
-- The rows change only through Put, which tells at once; whether we read a room follows from
-- these and the rows (Reads). A soldier gone from the guild changes nothing the Chat tab keeps for
-- its era (a room's lines and anyone's access are asked at each redraw), and the War page is the
-- window's, redrawn at every DATA_CHANGED (UI.lua). The census tells DATA_CHANGED every second or
-- so on a busy realm (Data.NOTIFY_GAP), and each was told as the squads changed: the Chat tab
-- starts a new era at CHAT_ROOMS_CHANGED, and on the author's game (the King's guild) it worked
-- every line and room out again 0.2 s after every notice, never waiting for its DATA_GAP.
-- (A name holds no ",", Full; a room is "squad:" and hex.)
local parts = {}
Signature = function()
	parts[1], parts[2] = Guild() or "", Member(ns.me) or ""
	parts[3], parts[4] = Preview() and "preview" or "", ChatOn() and "on" or ""
	local n = 4
	for _, e in ipairs(Squads.Leaders()) do
		parts[n + 1], parts[n + 2], parts[n + 3] = e.room, e.kind, e.name
		n = n + 3
	end
	for i = #parts, n + 1, -1 do parts[i] = nil end
	return table.concat(parts, ",", 1, n)
end
if ns.ChatRooms then ns.ChatRooms.RegisterProvider(provider) end
ns.Comm.Handle("WU", Squads.Handle)
ns.Comm.Handle("SC", Squads.ReceiveChat)
-- Event driven only: no per-frame task or periodic enumeration while idle; a roster scan asks
-- for rows only until an officer's came (Squads.Request's own limits). (1.2.3: told only when
-- what the squads' rooms rest on changed, Signature.)
ns.On("DATA_CHANGED", function()
	indexedRoster = nil
	local now = Signature()
	if now ~= told then Changed(now) end
	Squads.Request()
end)
ns.On("LOGIN", Squads.Request)
