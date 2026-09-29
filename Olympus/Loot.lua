local ADDON, ns = ...
local L = ns.L

-- Loot notes (1.1, Fern's #22): "[Loot notes] and an optional points column officers edit by
-- hand. Not a bid window and not auto-loot. Loot arguments restart every raid because nobody kept
-- last week's decision. Notes carry that history. Points, if you use them, stay a notebook. Gold
-- bids are out because GDKP is not allowed on Forever."
--
-- A guild's own book, over GUILD alone (never the Olympus channel). Its officers (the guild master
-- and the officer rank right below, by each reader's own roster: the server's word) write notes,
-- the decision the next raid starts from ("[Nightslayer Belt] to Ann: she passed on the gloves,
-- Bob gets the next one"), and, if the guild uses them, a member's points by hand: a number,
-- nothing adds or takes any. Every member with the addon reads the book on the Realm tab (Loot
-- notes). Nothing is bid, rolled, handed out or traded: no bid window, no gold, no loot moved. The
-- items the group loots show there to its officers (the game's own loot lines, this session),
-- only so a note can name one with a click.
--   J1~<entry>              an officer's change: a note written or removed, points set (GUILD;
--                           a note's words go through the logged API, the server keeps them)
--   JQ~<newest change held> a member's addon asks for the changes since (GUILD): an officer's at
--                           login, anyone else's when the page first opens this session
--   JB~<entry>^<entry>...   an officer's answer: the changes since (GUILD, in pieces)
-- Entries:
--   N~<writer>~<id>~<written>~<changed>~<item id>~<1: removed>~<to whom>~<words>
--   P~<member>~<points, or nothing: cleared>~<changed>~<officer>
-- (times in base 36, the server's clock). A reader takes a change only from an officer of its own
-- roster, only newer than what it holds. Kept per guild in the saved variables; on the Forever
-- beta, which forgets them at every login, the book comes back from the officers online.

local Loot = {}
ns.Loot = Loot

Loot.TEXT_MAX = 100        -- bytes of a note's words (a change fits one message: 255 bytes)
Loot.TO_MAX = 40           -- ...of whom it went to
Loot.NOTES_MAX = 150       -- notes kept per guild (the newest changes; removed ones count)
Loot.POINTS_MAX = 1000     -- members with points
Loot.POINTS_LIMIT = 99999  -- points go from minus this to this
Loot.REMOVED_KEEP = 30 * 86400 -- a removed note's mark is kept this long (so no old copy brings it back)
Loot.ANSWER_GAP = 120      -- an officer answers asks once each 2 minutes at most...
Loot.ANSWER_BYTES = 5000   -- ...with this much of the book (the newest changes first)
Loot.DROPS_MAX = 20        -- the group's loot kept for the officers' notes, this session
Loot.random = math.random
Loot.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local answering        -- an answer of ours waiting: { since, heard }
local lastAnswer = -math.huge
local askedThisSession = false
local counter = 0
local drops = {}       -- { { id, link, to, t } }, newest first

local function ServerNow() return (GetServerTime and GetServerTime()) or time() end
local B36 = function(n) return ns.Codec.Base36(n) or "0" end
local function UnB36(s) return type(s) == "string" and #s >= 1 and #s <= 8 and s:match("^[0-9a-z]+$") and tonumber(s, 36) or nil end

-- A player's words as they travel and show: no escape code, control byte, "~" or "^"; one space
-- between words; at most n bytes (never half a letter).
local function Clean(s, n)
	s = tostring(s or ""):gsub("[|%c~%^]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return ns.Cut(s, n)
end
Loot.Clean = Clean

-- A character's name as it travels: "Name" or "First Surname", with "-Realm" or not.
local function NameField(s)
	if type(s) ~= "string" or #s > 60 then return nil end
	local short, realm = s:match("^([^%-]+)%-([^%-]+)$")
	short = short or s
	if not short:match("^[%a\128-\255]+ ?[%a\128-\255]*$") then return nil end
	if realm and not realm:match("^[%w\128-\255]+$") then return nil end
	return s
end

---------------------------------------------------------------------------
-- The book (our guild's)
---------------------------------------------------------------------------

function Loot.Guild()
	local guild = IsInGuild() and GetGuildInfo("player")
	return type(guild) == "string" and guild ~= "" and guild or nil
end

local function Book()
	local guild = Loot.Guild()
	if not guild or not ns.rdb then return nil end
	if type(ns.rdb.loot) ~= "table" then ns.rdb.loot = {} end
	local key = ns.Fold(guild)
	local b = ns.rdb.loot[key]
	if type(b) ~= "table" then
		b = {}
		ns.rdb.loot[key] = b
	end
	if type(b.notes) ~= "table" then b.notes = {} end
	if type(b.points) ~= "table" then b.points = {} end
	return b
end
Loot.Book = Book

-- An officer: the guild master or the officer rank right below (our own rank, from the server).
function Loot.IsOfficer() return ns.IsMember() == true and ns.Roster.IsOfficer() == true end
-- A sender our roster ranks an officer of our guild.
local function SenderOfficer(sender)
	local rank = ns.Roster.RankOf(sender)
	return rank ~= nil and rank <= ns.CAPTAIN_RANK
end

-- The newest change held (notes and points), 0 for none.
local function Newest(b)
	local at = 0
	for _, n in pairs(b.notes) do if type(n) == "table" and (n.rev or 0) > at then at = n.rev end end
	for _, p in pairs(b.points) do if type(p) == "table" and (p.rev or 0) > at then at = p.rev end end
	return at
end

-- At most NOTES_MAX notes (the newest changes), a removed one's mark REMOVED_KEEP, POINTS_MAX points.
function Loot.Prune(b)
	b = b or Book()
	if not b then return end
	local now, list = ServerNow(), {}
	for key, n in pairs(b.notes) do
		if type(n) ~= "table" or (n.del and now - (n.rev or 0) > Loot.REMOVED_KEEP) then b.notes[key] = nil
		else list[#list + 1] = { key = key, rev = n.rev or 0 } end
	end
	if #list > Loot.NOTES_MAX then
		table.sort(list, function(a, c) if a.rev ~= c.rev then return a.rev > c.rev end return a.key < c.key end)
		for i = Loot.NOTES_MAX + 1, #list do b.notes[list[i].key] = nil end
	end
	list = {}
	for key, p in pairs(b.points) do list[#list + 1] = { key = key, rev = type(p) == "table" and p.rev or 0 } end
	if #list > Loot.POINTS_MAX then
		table.sort(list, function(a, c) if a.rev ~= c.rev then return a.rev > c.rev end return a.key < c.key end)
		for i = Loot.POINTS_MAX + 1, #list do b.points[list[i].key] = nil end
	end
end

-- An entry as it travels (see the top).
local function NoteEntry(n)
	return ("N~%s~%s~%s~%s~%s~%s~%s~%s"):format(n.writer, n.id, B36(n.t), B36(n.rev), n.item and tostring(n.item) or "",
		n.del and "1" or "", n.del and "" or (n.to or ""), n.del and "" or (n.text or ""))
end
local function PointsEntry(member, p)
	return ("P~%s~%s~%s~%s"):format(member, p.v and tostring(p.v) or "", B36(p.rev), p.by or "")
end

-- An entry heard from `sender` (an officer), taken into the book when newer than ours: true then.
-- live: an officer's own change (J1): a new note must be his own.
local function Take(b, entry, sender, live)
	local now = ServerNow()
	if entry:sub(1, 2) == "N~" then
		local writer, id, t, rev, item, del, to, text = entry:match("^N~([^~]+)~([0-9a-z]+)~([0-9a-z]+)~([0-9a-z]+)~(%d*)~(1?)~([^~]*)~([^~]*)$")
		writer, t, rev = NameField(writer), UnB36(t), UnB36(rev)
		if not writer or not t or not rev or #id > 10 or rev < t or rev > now + 3600 or #item > 9 then return false end
		if #to > Loot.TO_MAX or #text > Loot.TEXT_MAX then return false end
		if del ~= "1" and text == "" then return false end
		if live and del ~= "1" and ns.FullName(writer) ~= ns.FullName(sender) then return false end
		local key = ns.FullName(writer) .. "#" .. id
		local old = b.notes[key]
		if type(old) == "table" and (old.rev or 0) >= rev then return false end
		if del == "1" then
			b.notes[key] = { writer = ns.FullName(writer), id = id, t = t, rev = rev, del = true, item = tonumber(item), by = ns.FullName(sender) }
		else
			b.notes[key] = { writer = ns.FullName(writer), id = id, t = t, rev = rev, item = tonumber(item),
				to = to ~= "" and Clean(to, Loot.TO_MAX) or nil, text = Clean(text, Loot.TEXT_MAX), by = ns.FullName(sender) }
		end
		return true
	elseif entry:sub(1, 2) == "P~" then
		local member, value, rev, by = entry:match("^P~([^~]+)~(%-?%d*)~([0-9a-z]+)~([^~]*)$")
		member, rev = NameField(member), UnB36(rev)
		local v = value ~= "" and tonumber(value) or nil
		if not member or not rev or rev > now + 3600 or (value ~= "" and (not v or math.abs(v) > Loot.POINTS_LIMIT)) then return false end
		local key = ns.FullName(member)
		local old = b.points[key]
		if type(old) == "table" and (old.rev or 0) >= rev then return false end
		b.points[key] = { v = v, rev = rev, by = NameField(by) and ns.FullName(by) or ns.FullName(sender) }
		return true
	end
	return false
end

local function Changed()
	ns.Fire("REALM_PAGE_CHANGED", "loot")
end

---------------------------------------------------------------------------
-- The officers' changes
---------------------------------------------------------------------------

local function Send(entry, logged)
	ns.Comm.Send("GUILD", "J1~" .. entry, nil, nil, logged)
end

-- A note: its words, and the item and whom it went to when one of the group's loot was clicked.
function Loot.Write(text, item, to)
	if not Loot.IsOfficer() then return ns.Print(L.LOOT_OFFICERS_ONLY) end
	local b = Book()
	if not b then return end
	text = Clean(text, Loot.TEXT_MAX)
	if #text < 2 then return ns.Print(L.LOOT_TOO_SHORT) end
	local now = ServerNow()
	counter = (counter + 1) % 1296
	local n = { writer = ns.me, id = B36(now) .. B36(counter), t = now, rev = now, item = tonumber(item),
		to = to and to ~= "" and Clean(to, Loot.TO_MAX) or nil, text = text, by = ns.me }
	-- (One message: a long name of ours leaves the words a little less room.)
	while #NoteEntry(n) > 250 do n.text = ns.Cut(n.text, #n.text - 1) end
	b.notes[n.writer .. "#" .. n.id] = n
	Loot.Prune(b)
	Send(NoteEntry(n), true)
	ns.Print(L.LOOT_WRITTEN)
	Changed()
	return n
end

-- A note removed (any officer): its mark goes to the guild, so every copy drops it.
function Loot.Remove(key)
	if not Loot.IsOfficer() then return ns.Print(L.LOOT_OFFICERS_ONLY) end
	local b = Book()
	local n = b and b.notes[key]
	if type(n) ~= "table" or n.del then return end
	local r = { writer = n.writer, id = n.id, t = n.t, rev = math.max(ServerNow(), (n.rev or 0) + 1), del = true, item = n.item, by = ns.me }
	b.notes[key] = r
	Send(NoteEntry(r))
	ns.Print(L.LOOT_REMOVED)
	Changed()
end

-- A member of our guild by name, as our roster writes him ("Name-Realm"), whatever the case.
local function Member(name)
	name = Clean(name, 60)
	if name == "" or not ns.Roster.byName then return nil end
	local want = ns.Fold(ns.ShortName(name))
	local realm = ns.RealmOf(name)
	for full in pairs(ns.Roster.byName) do
		if ns.Fold(ns.ShortName(full)) == want and (not realm or ns.Fold(ns.RealmOf(full) or "") == ns.Fold(realm)) then return full end
	end
	return nil
end
Loot.Member = Member

-- A member's points, set by hand ("Bob 12"; "Bob" alone clears them). A notebook: nothing adds
-- or takes any.
function Loot.SetPoints(text)
	if not Loot.IsOfficer() then return ns.Print(L.LOOT_OFFICERS_ONLY) end
	local b = Book()
	if not b then return end
	text = Clean(text, 80)
	local name, value = text:match("^(.-)%s+([%+%-]?%d+)$")
	if not name then name = text end
	local v = value and tonumber(value) or nil
	if v and math.abs(v) > Loot.POINTS_LIMIT then return ns.Print(L.LOOT_POINTS_BAD:format(Loot.POINTS_LIMIT, Loot.POINTS_LIMIT)) end
	local member = Member(name)
	if not member then return ns.Print(L.LOOT_POINTS_NOT_MEMBER:format(name ~= "" and name or "?")) end
	local old = b.points[member]
	local p = { v = v, rev = math.max(ServerNow(), (type(old) == "table" and old.rev or 0) + 1), by = ns.me }
	b.points[member] = p
	Loot.Prune(b)
	Send(PointsEntry(member, p))
	ns.Print(v and L.LOOT_POINTS_DONE:format(ns.DisplayName(member), v) or L.LOOT_POINTS_CLEARED:format(ns.DisplayName(member)))
	Changed()
	return p
end

-- J1: an officer's change.
function Loot.HandleLive(dist, sender, text)
	if dist ~= "GUILD" or not SenderOfficer(sender) then return end
	local b = Book()
	local entry = b and text:match("^J1~(.+)$")
	if entry and Take(b, entry, sender, true) then
		Loot.Prune(b)
		Changed()
	end
end
ns.Comm.Handle("J1", function(...) Loot.HandleLive(...) end)

---------------------------------------------------------------------------
-- The book for a member's addon that lacks it (a login, a /reload on the Forever beta)
---------------------------------------------------------------------------

-- Our ask: an officer's addon at login, anyone else's the first time the page opens.
function Loot.Ask()
	local b = ns.IsMember() and Book()
	if not b then return false end
	askedThisSession = true
	ns.Comm.Send("GUILD", "JQ~" .. B36(Newest(b)), "lootask")
	return true
end

-- The changes newer than `since`, newest first, as much as ANSWER_BYTES holds.
local function Since(b, since)
	local list = {}
	for _, n in pairs(b.notes) do
		if type(n) == "table" and (n.rev or 0) > since then list[#list + 1] = { rev = n.rev, entry = NoteEntry(n) } end
	end
	for member, p in pairs(b.points) do
		if type(p) == "table" and (p.rev or 0) > since then list[#list + 1] = { rev = p.rev, entry = PointsEntry(member, p) } end
	end
	table.sort(list, function(a, c) if a.rev ~= c.rev then return a.rev > c.rev end return a.entry < c.entry end)
	local out, size = {}, 3
	for _, e in ipairs(list) do
		if size + #e.entry + 1 > Loot.ANSWER_BYTES then break end
		out[#out + 1] = e.entry
		size = size + #e.entry + 1
	end
	return out
end

-- Someone's ask (JQ): an officer's addon holding newer changes answers, 2 to 12 seconds later,
-- once each ANSWER_GAP; another officer's answer heard meanwhile answers for it.
function Loot.HandleAsk(dist, sender, text)
	if dist ~= "GUILD" or not Loot.IsOfficer() then return end
	if not ns.Roster.RankOf(sender) then return end -- (a guildmate our roster knows)
	local since = UnB36(text:match("^JQ~([0-9a-z]+)$"))
	local b = since and Book()
	if not b then return end
	if answering then
		answering.since = math.min(answering.since, since)
		return
	end
	if ns.Now() - lastAnswer < Loot.ANSWER_GAP or Newest(b) <= since then return end
	local a = { since = since }
	answering = a
	Loot.after(2 + Loot.random() * 10, "loot answer", function()
		if answering ~= a then return end
		answering = nil
		if a.heard or not Loot.IsOfficer() then return end
		local book = Book()
		local entries = book and Since(book, a.since) or {}
		if #entries == 0 then return end
		lastAnswer = ns.Now()
		ns.Comm.SendChunked("JB~" .. table.concat(entries, "^"), nil, "GUILD")
	end)
end
ns.Comm.Handle("JQ", function(...) Loot.HandleAsk(...) end)

-- JB: an officer's answer (in pieces over GUILD, Comm.lua), taken entry by entry.
function Loot.HandleBook(dist, sender, text)
	if dist ~= "GUILD" or not SenderOfficer(sender) then return end
	if answering then answering.heard = true end
	local b = Book()
	local body = b and text:match("^JB~(.+)$")
	if not body then return end
	local changed = false
	for entry in body:gmatch("[^%^]+") do
		if Take(b, entry, sender, false) then changed = true end
	end
	if changed then
		Loot.Prune(b)
		Changed()
	end
end
ns.Comm.Handle("JB", function(...) Loot.HandleBook(...) end)

---------------------------------------------------------------------------
-- The group's loot, for the officers' notes (the game's own loot lines, this session)
---------------------------------------------------------------------------

-- The game's loot line as a pattern: "%s receives loot: %s." -> "^(.+) receives loot: (.+)%.$".
local function Pattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
	return "^" .. p .. "$"
end

-- A loot line of the group's: the item (rare and better, or not yet known to the client) and who got
-- it, kept for the officers to write its note with a click. Nothing else is done with it.
function Loot.OnLootMessage(text)
	if type(text) ~= "string" or not (IsInGroup and IsInGroup()) or not Loot.IsOfficer() then return end
	local link = text:match("|c%x+|Hitem:[^|]+|h%[[^%]]*%]|h|r") or text:match("|Hitem:[^|]+|h%[[^%]]*%]|h")
	local id = link and tonumber(link:match("|Hitem:(%d+)"))
	if not id then return end
	local quality
	if GetItemInfo then
		local ok, _, _, q = pcall(GetItemInfo, link)
		if ok then quality = q end
	end
	if quality and quality < 3 then return end
	local to
	for _, fmt in ipairs({ LOOT_ITEM, LOOT_ITEM_MULTIPLE }) do
		local p = Pattern(fmt)
		local who = p and text:match(p)
		if who then to = who break end
	end
	if not to then
		for _, fmt in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE }) do
			local p = Pattern(fmt)
			if p and text:match(p) then to = ns.ShortName(ns.me) break end
		end
	end
	if not to then return end
	table.insert(drops, 1, { id = id, link = link, to = Clean(ns.ShortName(to), Loot.TO_MAX), t = ns.Now() })
	while #drops > Loot.DROPS_MAX do table.remove(drops) end
	Changed()
end
function Loot.Drops() return drops end

---------------------------------------------------------------------------
-- The page (the Realm tab)
---------------------------------------------------------------------------

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end

-- An item as a line shows it: the game's link once the client knows it, else "item #id".
local function ItemText(id)
	if not id then return nil end
	if GetItemInfo then
		local ok, name, link = pcall(GetItemInfo, id)
		if ok and type(link) == "string" then return link end
		if ok and type(name) == "string" then return "[" .. name .. "]" end
	end
	return "[" .. L.LOOT_ITEM_N:format(id) .. "]"
end
local function ItemName(id)
	if not id then return nil end
	if GetItemInfo then
		local ok, name = pcall(GetItemInfo, id)
		if ok and type(name) == "string" then return name end
	end
	return L.LOOT_ITEM_N:format(id)
end

-- The notes shown (removed ones left out), newest first.
function Loot.Notes()
	local b, out = Book(), {}
	for key, n in pairs(b and b.notes or {}) do
		if type(n) == "table" and not n.del then out[#out + 1] = { key = key, n = n } end
	end
	table.sort(out, function(a, c)
		if a.n.t ~= c.n.t then return (a.n.t or 0) > (c.n.t or 0) end
		return a.key < c.key
	end)
	return out
end

-- The points set (cleared ones left out), most first.
function Loot.Points()
	local b, out = Book(), {}
	for member, p in pairs(b and b.points or {}) do
		if type(p) == "table" and p.v then out[#out + 1] = { member = member, v = p.v, by = p.by, rev = p.rev } end
	end
	table.sort(out, function(a, c) if a.v ~= c.v then return a.v > c.v end return a.member < c.member end)
	return out
end

local function Date(t) return date("%Y-%m-%d", t) end

function Loot.Show(open)
	if open then
		ns.Views.ShowPage("loot")
		-- The book may be older than the officers' (a login on the Forever beta): asked once a session.
		if not askedThisSession then Loot.Ask() end
	else
		ns.Views.ShowPage(nil)
	end
end

function Loot.Link()
	local guild = ns.IsMember() and Loot.Guild()
	if not guild then return nil end
	local n = #Loot.Notes()
	return {
		text = "|TInterface\\Icons\\INV_Misc_Note_01:14:14|t " .. Gold(L.LOOT_LINK:format(guild)),
		right = n > 0 and Grey(tostring(n)) or nil,
		onClick = function() Loot.Show(true) end,
		tooltip = function(tt)
			tt:AddLine(L.LOOT_LINK:format(guild), 1, 0.82, 0)
			tt:AddLine(L.LOOT_LINK_TIP, 1, 1, 1, true)
		end,
	}
end

-- The page's lines; `q`, the Realm's search: notes and points whose words hold it.
function Loot.Lines(q)
	local officer = Loot.IsOfficer()
	local guild = Loot.Guild() or "?"
	local lines = { { text = Gold(L.CHATS_BACK), onClick = function() Loot.Show(false) end, gapAfter = true } }
	lines[#lines + 1] = { header = true, text = L.LOOT_TITLE:format(guild),
		tooltip = function(tt)
			tt:AddLine(L.LOOT_TITLE:format(guild), 1, 0.82, 0)
			tt:AddLine(L.LOOT_ABOUT, 1, 1, 1, true)
		end }
	if officer and not q then
		lines[#lines + 1] = { text = Green(L.LOOT_WRITE), onClick = function() ns.ShowDialog("OLYMPUS_LOOT_NOTE", L.LOOT_NOTE_PROMPT, nil, {}) end,
			tooltip = function(tt) tt:AddLine(L.LOOT_WRITE, 1, 0.82, 0); tt:AddLine(L.LOOT_WRITE_TIP, 1, 1, 1, true) end }
		lines[#lines + 1] = { text = Green(L.LOOT_POINTS_SET), onClick = function() ns.ShowDialog("OLYMPUS_LOOT_POINTS", nil, nil, "") end,
			tooltip = function(tt) tt:AddLine(L.LOOT_POINTS_SET, 1, 0.82, 0); tt:AddLine(L.LOOT_POINTS_SET_TIP, 1, 1, 1, true) end }
		lines[#lines].gapAfter = true
		-- The group's loot this session: a click writes its note.
		if #drops > 0 then
			lines[#lines + 1] = { header = true, text = L.LOOT_DROPS }
			for _, d in ipairs(drops) do
				lines[#lines + 1] = { indent = 1, text = (ItemText(d.id) or "?") .. "  " .. Grey("> " .. d.to), right = Grey(ns.Ago(d.t)),
					onClick = function()
						ns.ShowDialog("OLYMPUS_LOOT_NOTE", L.LOOT_NOTE_FOR:format(ItemName(d.id), d.to), nil, { item = d.id, to = d.to })
					end,
					tooltip = function(tt)
						if tt.SetHyperlink then pcall(tt.SetHyperlink, tt, "item:" .. d.id) end
						tt:AddLine(L.LOOT_DROP_TIP, 0.6, 0.6, 0.6, true)
					end }
			end
			lines[#lines].gapAfter = true
		end
	end
	local notes, shown = Loot.Notes(), 0
	for _, e in ipairs(notes) do
		local n = e.n
		local what = (n.item and (ItemText(n.item) .. " ") or "") .. (n.to and Gold("> " .. n.to) .. "  " or "") .. n.text
		if not q or ns.Holds(q, n.text, n.to, n.item and ItemName(n.item), ns.DisplayName(n.writer)) then
			shown = shown + 1
			lines[#lines + 1] = {
				text = what, right = Grey(ns.ShortName(ns.DisplayName(n.writer) or "?") .. "  " .. Date(n.t)),
				onClick = officer and function() ns.ShowDialog("OLYMPUS_LOOT_REMOVE", n.text, nil, e.key) end or nil,
				tooltip = function(tt)
					if n.item and tt.SetHyperlink then pcall(tt.SetHyperlink, tt, "item:" .. n.item) end
					tt:AddLine(n.text, 1, 1, 1, true)
					tt:AddLine(L.LOOT_NOTE_TIP:format(ns.DisplayName(n.writer) or "?", date("%Y-%m-%d %H:%M", n.t)), 0.6, 0.6, 0.6, true)
					if officer then tt:AddLine(L.LOOT_REMOVE_TIP, 0.6, 0.6, 0.6, true) end
				end,
			}
		end
	end
	if #notes == 0 and not q then lines[#lines + 1] = { text = Grey(officer and L.LOOT_EMPTY_OFFICER or L.LOOT_EMPTY) } end
	-- The points, if the guild uses them: a column of numbers set by hand.
	local points, found = Loot.Points(), 0
	if #points > 0 then
		local header = { header = true, text = L.LOOT_POINTS_TITLE,
			tooltip = function(tt) tt:AddLine(L.LOOT_POINTS_TITLE, 1, 0.82, 0); tt:AddLine(L.LOOT_POINTS_TIP, 1, 1, 1, true) end }
		for _, p in ipairs(points) do
			if not q or ns.Holds(q, ns.DisplayName(p.member)) then
				if found == 0 then
					if lines[#lines] then lines[#lines].gapAfter = true end
					lines[#lines + 1] = header
				end
				found = found + 1
				lines[#lines + 1] = { indent = 1, text = ns.DisplayName(p.member), right = Gold(tostring(p.v)),
					onClick = officer and function() ns.ShowDialog("OLYMPUS_LOOT_POINTS", nil, nil, ns.DisplayName(p.member) .. " " .. p.v) end or nil,
					tooltip = function(tt)
						tt:AddLine(ns.DisplayName(p.member), 1, 0.82, 0)
						tt:AddLine(L.LOOT_POINTS_BY:format(ns.DisplayName(p.by) or "?", date("%Y-%m-%d %H:%M", p.rev)), 1, 1, 1, true)
					end }
			end
		end
	end
	if q and shown == 0 and found == 0 then lines[#lines + 1] = { text = Grey(L.SEARCH_NO_MATCH) } end
	if not q and (#notes > 0 or #points > 0) then
		if lines[#lines] then lines[#lines].gapAfter = true end
		lines[#lines + 1] = { text = Gold(L.COPY_DISCORD), onClick = function() ns.UI.ShowCopy(L.LOOT_TITLE:format(guild), Loot.DiscordText()) end }
	end
	return lines
end

-- The book as text for Discord: the notes, then the points.
function Loot.DiscordText()
	local guild = Loot.Guild() or "?"
	local out = { "**" .. L.LOOT_TITLE:format(guild) .. "**" }
	for _, e in ipairs(Loot.Notes()) do
		local n = e.n
		out[#out + 1] = ("%s %s%s%s (%s)"):format(Date(n.t), n.item and ("[" .. ItemName(n.item) .. "] ") or "",
			n.to and ("> " .. n.to .. ": ") or "", n.text, ns.ShortName(ns.DisplayName(n.writer) or "?"))
	end
	local points = Loot.Points()
	if #points > 0 then
		out[#out + 1] = "**" .. L.LOOT_POINTS_TITLE .. "**"
		for _, p in ipairs(points) do out[#out + 1] = ("%s: %d"):format(ns.DisplayName(p.member), p.v) end
	end
	return ns.Codec.NoMentions(table.concat(out, "\n"))
end

-- The dialogs: a note's words (data: { item, to }), a note's removal (data: its key), points
-- ("Name 12"; data: the text the box starts with).
StaticPopupDialogs["OLYMPUS_LOOT_NOTE"] = {
	text = "%s",
	button1 = L.LOOT_SAVE,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = Loot.TEXT_MAX,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(""); eb:SetFocus() end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		data = data or {}
		ns.SafeCall("loot note", Loot.Write, eb and eb:GetText(), data.item, data.to)
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local data = parent.data or {}
		ns.SafeCall("loot note", Loot.Write, self:GetText(), data.item, data.to)
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
StaticPopupDialogs["OLYMPUS_LOOT_REMOVE"] = {
	text = L.LOOT_REMOVE_PROMPT,
	button1 = L.LOOT_REMOVE_BTN,
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, key) ns.SafeCall("loot remove", Loot.Remove, key or (self and self.data)) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
StaticPopupDialogs["OLYMPUS_LOOT_POINTS"] = {
	text = L.LOOT_POINTS_PROMPT,
	button1 = L.LOOT_SAVE,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 220,
	maxLetters = 80,
	OnShow = function(self, data)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(type(data) == "string" and data or ""); eb:SetFocus() end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("loot points", Loot.SetPoints, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("loot points", Loot.SetPoints, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "loot", Link = function() return Loot.Link() end, Lines = function(q) return Loot.Lines(q) end, tip = "LOOT" })

ns.On("LOGIN", function()
	ns.RegisterEvent("CHAT_MSG_LOOT", function(text) Loot.OnLootMessage(text) end)
	-- An officer's addon asks for the changes it lacks once the roster is in (the answers are
	-- taken from officers our roster knows).
	ns.After(50 + Loot.random() * 30, "loot ask", function()
		if Loot.IsOfficer() and not askedThisSession then Loot.Ask() end
	end)
end)

-- Tests start from a clean state.
function Loot.Reset()
	answering, lastAnswer, askedThisSession, counter = nil, -math.huge, false, 0
	wipe(drops)
end
