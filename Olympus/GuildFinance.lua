local ADDON, ns = ...
local L, T = ns.L, ns.Treasury

-- Explicit attribution, not a second bank or a balance. Only the native receipt callback
-- admits copper; a keeper assigns one such source once to a guild/event. The original book
-- stays authoritative about exclusions. No payer names or receipt details leave this client:
-- scoped, requested aggregates alone use Treasury's bounded private transport (GF).
local F = {}
ns.GuildFinance = F
F.RECEIPTS, F.EVENTS, F.ROOM, F.ACTORS = 2000, 60, 6000, 32
F.FRESH, F.WAIT, F.GAP = 900, 120, 180
local pending, replies, asked = {}, {}, {}
local nextAsk = 0
local function Clock() return math.floor(ns.Now()) end
local function Int(n, max)
	return type(n) == "number" and n == n and n % 1 == 0 and n >= 0 and n <= (max or T.MAX_COPPER)
end
local function Word(key, fallback) return rawget(L, key) or fallback end
local function Clean(text, max)
	return ns.Cut(tostring(text or ""):gsub("[|~/;%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""), max or 70)
end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
local function Preview()
	local V = ns.ViewAs
	return ns.King.Preview() or T.DevView() or (V and V.Previewing and V.Previewing()) or (ns.db and ns.db.devGMView == true)
end
local function Off(name, guild)
	local M = ns.Moderation
	return M and M.Hides and M.Hides(name, guild) ~= nil
end
local function Crown(name)
	if Same(name, ns.me) then return ns.King.IsKing() or ns.King.IsSteward() or ns.King.IsHand() end
	return type(name) == "string" and (ns.IsKingCharacter(name) or ns.King.IsStewardName(name) or ns.King.IsHandName(name))
end
local function Lord(name, guild)
	if type(guild) ~= "string" or not ns.IsFederation(guild) or Off(name, guild) then return false end
	local rank, source = ns.Data.AuthorizedRank(ns.FullName(name), guild)
	if rank ~= 0 then return false end
	if source == "roster" then
		if guild ~= GetGuildInfo("player") or not ns.Roster.Fresh() then return false end
		if Same(name, ns.me) then local own, _, live = GetGuildInfo("player"); return own == guild and live == 0 end
		return true
	end
	if source == "signed" or source == "pinned" then return true end
	-- A new private financial audience never inherits the old census capability fallback.
	-- Two reports may corroborate a directory entry, but cannot prove this Lord's office.
	return false
end
function F.MayView(guild, name)
	name = name or ns.me
	if Same(name, ns.me) and (Preview() or not ns.IsMember()) then return false end
	if type(guild) ~= "string" or (guild ~= "*" and not ns.IsFederation(guild)) or Off(name, guild) then return false end
	return Crown(name) or (guild ~= "*" and Lord(name, guild)) or false
end
function F.MayAllocate()
	return T.RealKeeper() and not Preview() and not Off(ns.me, GetGuildInfo("player"))
end
function F.Visible() return F.MayAllocate() or F.MayView((GetGuildInfo("player"))) end
local function Identity()
	return { me = ns.me, guild = GetGuildInfo("player"), store = ns.rdb, faction = ns.faction, realm = ns.realm }
end
local function SameIdentity(i)
	return i and Same(i.me, ns.me) and i.guild == GetGuildInfo("player") and i.store == ns.rdb
		and i.faction == ns.faction and i.realm == ns.realm
end
local function SameViewer(i)
	return i and Same(i.me, ns.me) and i.guild == GetGuildInfo("player") and i.faction == ns.faction and i.realm == ns.realm
end
local function Store()
	if not ns.rdb then return nil end
	local s = ns.rdb.guildFinance
	if s == nil then s = { version = 1, actors = {}, held = {} }; ns.rdb.guildFinance = s end
	if type(s) ~= "table" or s.version ~= 1 or type(s.actors) ~= "table" or type(s.held) ~= "table" then return nil end
	return s
end
local function Actor(name, create)
	local s = Store(); if not s then return nil end
	name = ns.FullName(name or ns.me)
	local a = s.actors[name]
	if a == nil and create then
		local n = 0; for _ in pairs(s.actors) do n = n + 1 end
		if n >= F.ACTORS then return nil end
		a = { next = 0, eventNext = 0, rev = 0, receipts = {}, events = {}, n = 0, cut = false }; s.actors[name] = a
	end
	if type(a) ~= "table" or not Int(a.next) or not Int(a.eventNext) or not Int(a.rev) or not Int(a.n, F.RECEIPTS)
		or type(a.receipts) ~= "table" or type(a.events) ~= "table" then return nil end
	local n, events = 0, 0
	for id, r in pairs(a.receipts) do
		n = n + 1
		if n > F.RECEIPTS or not Int(id) or type(r) ~= "table" or not Int(r.money) or r.money == 0
			or not Int(r.at) or type(r.book) ~= "string" or (r.how ~= "mail" and r.how ~= "trade") then return nil end
	end
	for id, e in pairs(a.events) do
		events = events + 1
		if events > F.EVENTS or not Int(id) or type(e) ~= "table" or type(e.guild) ~= "string" or type(e.purpose) ~= "string" or not Int(e.at) then return nil end
	end
	return n == a.n and a.next >= n and a or nil
end
local function Mine(actor)
	return Same(actor, ns.me) or (F.MayAllocate() and ns.IsTreasurer(ns.me, GetGuildInfo("player")) and ns.IsTreasurerMail(actor))
end
local function Rev(a) a.rev = math.max(Clock(), a.rev + 1) end
local function Changed() ns.Fire("TREASURY_CHANGED") end
local function Guild(text)
	if type(text) ~= "string" or text == "" or #text > 72 or text:find("[~|/;%c]") or not ns.IsFederation(text) then return nil end
	return text
end
local function Recognized(guild)
	if not Guild(guild) then return false end
	if guild == GetGuildInfo("player") then return ns.IsMember() and ns.Roster.Fresh() and true or false end
	local g = ns.Data.Guild(guild)
	return g ~= nil and not ns.Data.Dispute(g) and Clock() - (tonumber(g.t) or 0) >= 0
		and Clock() - (tonumber(g.t) or 0) <= ns.Data.FRESH
end
local function Source(e)
	return type(e) == "table" and not e.item and Int(e.money) and e.money > 0
		and (e.how == "mail" or e.how == "trade") and (e.kind == nil or (not e.out and e.kind == "charity") or (e.out and e.kind == "purchase"))
end
function F.Received(e, b)
	if not F.MayAllocate() or not Source(e) or type(b) ~= "table" or b.epoch ~= T.EPOCH or not Same(b.name, ns.me) then return false end
	local found = false; for _, row in ipairs(b.lines or {}) do if row == e then found = true; break end end
	if not found then return false end
	local a = Actor(nil, true); if not a then return false end
	if e.financeActor and e.financeReceipt then return false end
	if a.n >= F.RECEIPTS then a.cut = true; Rev(a); return false end
	a.next, a.n = a.next + 1, a.n + 1
	e.financeActor, e.financeReceipt = ns.FullName(ns.me), a.next
	a.receipts[a.next] = { book = b.name, epoch = b.epoch, at = e.t, money = e.money, how = e.how,
		out = e.out == true, payee = ns.Dues.Key(e.patron or e.name), guild = Guild(e.guild), guildVerified = e.gv == true, valid = not e.excluded,
		status = e.out and e.how == "mail" and "sent" or "observed" }
	Rev(a)
	return true
end
-- A historical line is native evidence only while the private native-intake cache still
-- contains its exact immutable receipt. A copied ledger's gv flag or note is not enough.
function F.ContributionSource(book, e)
	if not F.MayAllocate() or type(book) ~= "table" or type(e) ~= "table" or not Same(book.name, ns.me)
		or not Same(e.financeActor, ns.me) then return nil end
	local a = Actor(e.financeActor)
	local r = a and a.receipts[e.financeReceipt]
	if not r or r.book ~= book.name or r.epoch ~= book.epoch or r.at ~= e.t or r.money ~= e.money or r.how ~= e.how
		or r.payee ~= ns.Dues.Key(e.name) or r.out or not r.valid or r.status ~= "observed" or r.guildVerified ~= true then return nil end
	return { guild = r.guild, source = "native-" .. r.how, nativeKey = e.financeActor .. ":" .. e.financeReceipt }
end
function F.CreateEvent(input, actor)
	actor = ns.FullName(actor or ns.me)
	if not F.MayAllocate() or not Mine(actor) then return false end
	local guild, purpose = tostring(input or ""):match("^%s*(.-)%s*|%s*(.-)%s*$")
	purpose = Clean(purpose)
	if not Recognized(guild) or purpose == "" then return false end
	local a = Actor(actor, true); if not a then return false end
	local n = 0; for _ in pairs(a.events) do n = n + 1 end
	if n >= F.EVENTS then return false end
	a.eventNext = a.eventNext + 1
	a.events[a.eventNext] = { guild = guild, purpose = purpose, at = Clock() }
	Rev(a); Changed()
	return a.eventNext
end
-- A source carrying a guild remains in that guild. Unknown income is not re-labelled from
-- a census guess. Expenses are assigned explicitly to a recognized event's recipient guild.
function F.Allocate(id, event, actor)
	actor = ns.FullName(actor or ns.me)
	if not F.MayAllocate() or not Mine(actor) then return false end
	F.Reconcile(actor)
	local a = Actor(actor)
	local r, e = a and a.receipts[id], a and a.events[event]
	if not r or not e or r.event or not r.valid or not Recognized(e.guild) or (not r.out and r.guild ~= e.guild) then return false end
	r.event, r.allocated = event, Clock()
	Rev(a); Changed()
	return true
end
function F.Reconcile(actor)
	actor = ns.FullName(actor or ns.me)
	if not F.MayAllocate() or not Mine(actor) then return false end
	local a = Actor(actor); if not a then return false end
	local changed, ambiguous = false, {}
	local books = {}; for _, r in pairs(a.receipts) do books[r.book] = true end
	for name in pairs(books) do
		local b = T.BookOf(name)
		if b and b.epoch == T.EPOCH then
			for _, e in ipairs(b.lines or {}) do
				local r = Same(e.financeActor, actor) and a.receipts[e.financeReceipt]
				if r then
					local valid = Source(e) and not e.excluded and e.money == r.money and (e.out == true) == r.out and e.how == r.how and e.t == r.at
						and ns.Dues.Key(e.patron or e.name) == r.payee and (r.out or e.kind == "charity" or Guild(e.guild) == r.guild)
					if e.returned or r.status == "return-unknown" then valid = false end
					if r.valid ~= valid then r.valid, changed = valid, true end
					-- The old book can match returned mail by amount/name only. That is not an
					-- exact receipt ID: retain the correction, never assert a proved refund.
					local status = (e.returned or r.status == "return-unknown") and "return-unknown" or (valid and (r.out and r.how == "mail" and "sent" or "observed") or "corrected")
					if r.status ~= status then r.status, changed = status, true end
					if e.returned then ambiguous[r.book .. "|" .. tostring(r.payee) .. "|" .. r.money] = true end
				end
			end
		end
	end
	-- An amount-only returned-mail match does not identify which equal payment returned.
	-- Every possible attributed source stays unknown, rather than leaving the other event
	-- falsely confirmed or declaring a specific refund. This survives row eviction/reload.
	for _, r in pairs(a.receipts) do
		if r.out and r.how == "mail" and ambiguous[r.book .. "|" .. tostring(r.payee) .. "|" .. r.money] then
			if r.valid or r.status ~= "return-unknown" then r.valid, r.status, changed = false, "return-unknown", true end
		end
	end
	if changed then Rev(a) end
	return changed
end
local function Rows(actor, scope)
	local a = Actor(actor); if not a then return {} end
	local rows = {}
	for id, e in pairs(a.events) do
		if scope == "*" or e.guild == scope then rows[id] = { id = id, guild = e.guild, purpose = e.purpose, at = e.at, inn = 0, out = 0, sent = 0, corrected = 0, verified = 0, unknown = 0 } end
	end
	for _, r in pairs(a.receipts) do
		local e = r.event and rows[r.event]
		if e then
			if not r.valid then e.corrected = e.corrected + 1; if r.status == "return-unknown" then e.unknown = e.unknown + r.money end
			elseif r.out then e.out = e.out + r.money; if r.status == "sent" then e.sent = e.sent + r.money end
			else e.inn = e.inn + r.money; if r.guildVerified then e.verified = e.verified + r.money end end
		end
	end
	local out = {}; for _, r in pairs(rows) do out[#out + 1] = r end
	table.sort(out, function(x, y) return x.id < y.id end)
	return out
end
function F.LocalRows(actor, scope)
	actor = ns.FullName(actor or ns.me)
	if not F.MayAllocate() or not Mine(actor) then return {} end
	F.Reconcile(actor)
	return Rows(actor, scope or "*")
end
local function Fields(text, sep)
	local out = {}; for part in (text .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end; return out
end
local function Parse(text)
	if type(text) ~= "string" or #text > F.ROOM then return nil end
	local f = Fields(text, "~")
	if #f ~= 11 or f[1] ~= "GF" or f[2] ~= "1" or f[3] ~= "D" then return nil end
	local q, rev, at = tonumber(f[4]), tonumber(f[8]), tonumber(f[9])
	if not Int(q, 9007199254740991) or not Int(rev) or not Int(at) or at > Clock() + 60 or (f[10] ~= "0" and f[10] ~= "1")
		or type(f[5]) ~= "string" or #f[5] > 96 or not f[5]:find("%-") or (f[7] ~= "*" and not Guild(f[7])) then return nil end
	local s = { q = q, actor = ns.FullName(f[5]), senderGuild = f[6], scope = f[7], rev = rev, at = at, cut = f[10] == "1", rows = {},
		fingerprint = table.concat({ f[5], f[6], f[7], f[8], f[10], f[11] }, "~") }
	for _, part in ipairs(f[11] == "" and {} or Fields(f[11], ";")) do
		local r = Fields(part, "/")
		local id, created, inn, out, sent, corrected, verified, unknown = tonumber(r[1]), tonumber(r[4]), tonumber(r[5]), tonumber(r[6]), tonumber(r[7]), tonumber(r[8]), tonumber(r[9]), tonumber(r[10])
		if #r ~= 10 or not Int(id) or id == 0 or not Guild(r[2]) or r[3] == "" or r[3] ~= Clean(r[3])
			or not Int(created) or created > at or not Int(inn) or not Int(out) or not Int(sent) or sent > out or not Int(corrected, F.RECEIPTS)
			or not Int(verified) or verified > inn or not Int(unknown)
			or s.rows[id] or (s.scope ~= "*" and s.scope ~= r[2]) then return nil end
		s.rows[id] = { id = id, guild = r[2], purpose = r[3], at = created, inn = inn, out = out, sent = sent, corrected = corrected, verified = verified, unknown = unknown }
		local n = 0; for _ in pairs(s.rows) do n = n + 1 end; if n > F.EVENTS then return nil end
	end
	return s
end
function F.Message(q, actor, scope)
	if not F.MayAllocate() or not Mine(actor) or (scope ~= "*" and not Guild(scope)) then return nil end
	F.Reconcile(actor)
	local a = Actor(actor); if not a then return nil end
	local rows, total, cut = {}, 0, a.cut == true
	local head = ("GF~1~D~%.0f~%s~%s~%s~%d~%d~0~"):format(q, ns.FullName(actor), GetGuildInfo("player") or "", scope, a.rev, Clock())
	for _, r in ipairs(Rows(actor, scope)) do
		if not Int(r.inn) or not Int(r.out) or not Int(r.sent) then return nil end
		local word = ("%d/%s/%s/%d/%d/%d/%d/%d/%d/%d"):format(r.id, r.guild, r.purpose, r.at, r.inn, r.out, r.sent, r.corrected, r.verified, r.unknown)
		if #head + total + #word + #rows > F.ROOM then cut = true; break end
		rows[#rows + 1], total = word, total + #word
	end
	return head:gsub("~0~$", cut and "~1~" or "~0~") .. table.concat(rows, ";")
end
local function Shared(actor)
	return T.CanSend() == true and (Same(actor, ns.me) or (ns.db and ns.db.keeperShares and ns.db.keeperShares[ns.FullName(actor):lower()] == true)) or false
end
local function ShareState(a, actor)
	local on, guild = Shared(actor), GetGuildInfo("player") or ""
	if a.shared ~= on or a.senderGuild ~= guild then a.shared, a.senderGuild = on, guild; Rev(a) end
	return on
end
local function Keeper(sender, guild) return T.IsKeeperName(sender, guild) and not Off(sender, guild) end
local function Query(text)
	local q, scope, guild = tostring(text):match("^GF~1~Q~(%d+)~([^~]+)~([^~]*)$")
	q = tonumber(q)
	return q and Int(q, 9007199254740991) and (scope == "*" or Guild(scope)) and q, scope, guild
end
local function HeldRoom(s, key)
	if s.held[key] then return true end
	local n = 0; for _ in pairs(s.held) do n = n + 1 end
	return n < (T.MAX_KEEPERS + 3) * (F.EVENTS + 1)
end
function F.Ask(scope)
	if not F.MayView(scope) then return false end
	if scope ~= "*" and not Recognized(scope) then return false end
	local now = Clock()
	for key, p in pairs(pending) do if now - p.at > F.FRESH then pending[key] = nil end end
	for key, at in pairs(asked) do if now - at > F.FRESH then asked[key] = nil end end
	if asked[scope] and now - asked[scope] < F.GAP then return false end
	nextAsk = math.max(nextAsk + 1, now * 1000)
	local p = Identity(); p.id, p.scope, p.at = nextAsk, scope, now
	local names, seen = { ns.TreasurerFull(), (ns.KingFullName()) }, {}
	for _, name in ipairs(T.Keepers()) do names[#names + 1] = ns.FullName(name) end
	local any = false
	for _, name in ipairs(names) do
		if not Same(name, ns.me) and not seen[name] and #names <= T.MAX_KEEPERS + 3 then
			seen[name] = true
			pending[name .. "|" .. scope] = p
			local msg = ("GF~1~Q~%.0f~%s~%s"):format(p.id, scope, p.guild or "")
			any = T.Private(name, "GF", msg, "finance-query:" .. scope) or any
		end
	end
	asked[scope] = now
	return any
end
function F.Handle(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > F.ROOM then return false end
	sender = ns.FullName(sender)
	local q, scope, viewerGuild = Query(text)
	if q then
		if not F.MayAllocate() or not F.MayView(scope, sender) or (scope ~= "*" and not Recognized(scope))
			or (scope ~= "*" and not Crown(sender) and viewerGuild ~= scope) or q < (Clock() - F.WAIT) * 1000 or q > (Clock() + 30) * 1000 then return false end
		local key = sender .. "|" .. scope
		for name, r in pairs(replies) do if Clock() - r.at > F.FRESH then replies[name] = nil end end
		local n = 0; for _ in pairs(replies) do n = n + 1 end
		if not replies[key] and n >= 32 then return false end
		if replies[key] and Clock() - replies[key].at < F.GAP then return false end
		local reply = { identity = Identity(), scope = scope, to = sender, q = q, at = Clock(), messages = {} }; replies[key] = reply
		local s = Store(); local any = false
		for actor in pairs(s and s.actors or {}) do
			if Mine(actor) then
				local a = Actor(actor)
				local shared = a and ShareState(a, actor)
				local msg = a and (shared and F.Message(q, actor, scope) or ("GF~1~X~%.0f~%s~%s~%s~%d"):format(q, actor, GetGuildInfo("player") or "", scope, a.rev))
				if msg then reply.messages[actor] = msg; any = T.Private(sender, "GF", msg, "finance:" .. actor .. ":" .. scope) or any end
			end
		end
		return any
	end
	local xq, actor, guild, xscope, rev = text:match("^GF~1~X~(%d+)~([^~]+)~([^~]*)~([^~]+)~(%d+)$")
	if xq then
		xq, rev, actor = tonumber(xq), tonumber(rev), ns.FullName(actor)
		local p = pending[sender .. "|" .. xscope]
		if not Int(xq, 9007199254740991) or not Int(rev) or not SameIdentity(p) or p.id ~= xq or not F.MayView(xscope)
			or Clock() - p.at < 0 or Clock() - p.at > F.WAIT or not Keeper(sender, guild) or (not Same(actor, sender) and not (ns.IsTreasurer(sender, guild) and ns.IsTreasurerMail(actor))) then return false end
		local s = Store(); local key = actor .. "|" .. xscope; local old = s and s.held[key]
		if not s or not HeldRoom(s, key) or (old and rev < old.rev) then return false end
		s.held[key] = { rev = rev, revoked = true }
		Changed(); return true
	end
	local data = Parse(text); if not data then return false, "shape" end
	if not F.MayView(data.scope) or not Keeper(sender, data.senderGuild) then return false, "authority" end
	if not Same(data.actor, sender) and not (ns.IsTreasurer(sender, data.senderGuild) and ns.IsTreasurerMail(data.actor)) then return false end
	local p = pending[sender .. "|" .. data.scope]
	if not SameIdentity(p) or p.id ~= data.q or Clock() - p.at < 0 or Clock() - p.at > F.WAIT or data.at < p.at - 60 then return false, "request" end
	local s = Store(); if not s then return false end
	local key = data.actor .. "|" .. data.scope
	local old = s.held[key]
	if not HeldRoom(s, key) then return false end
	if old and data.rev < old.rev then return false end
	-- Same-revision disagreements are unknown, not an additive second book. Remove the
	-- transport nonce/time from the fingerprint so a harmless later retransmit agrees.
	if old and old.revoked and data.rev <= old.rev then return false end
	if old and data.rev == old.rev and old.fingerprint ~= data.fingerprint then
		if not old.conflict then old.conflict = true; Changed() end
		return false
	end
	if old and data.rev == old.rev and old.conflict then return false end
	data.identity, data.heard, data.from = Identity(), Clock(), sender
	data.identity.store = nil -- never persist a cyclic SavedVariables reference
	s.held[key] = data
	Changed()
	return true
end
function F.Held(scope)
	if not F.MayView(scope) then return {} end
	local s, out = Store(), {}
	for _, data in pairs(s and s.held or {}) do
		if data.scope == scope and SameViewer(data.identity) and not data.conflict and not data.revoked and Keeper(data.from, data.senderGuild)
			and (Same(data.actor, data.from) or (ns.IsTreasurer(data.from, data.senderGuild) and ns.IsTreasurerMail(data.actor))) then out[#out + 1] = data end
	end
	return out
end
-- Called only after Treasury authenticates its existing TX withdrawal. A primary's no
-- also ends its forwarded mail-character snapshots; preserve each revision floor so an
-- in-flight old private answer cannot bring the withdrawn data back.
function F.Withdrawn(sender)
	local s, changed = Store(), false
	for key, data in pairs(s and s.held or {}) do
		if Same(data.actor, sender) or Same(data.from, sender) then
			s.held[key], changed = { rev = data.rev, revoked = true }, true
		end
	end
	return changed
end
local function Peer(sender)
	if not F.Visible() or type(sender) ~= "string" then return false end
	if T.KeeperByName(sender) then
		for key, p in pairs(pending) do
			if key == ns.FullName(sender) .. "|" .. p.scope and SameIdentity(p) and Clock() - p.at >= 0 and Clock() - p.at <= F.WAIT then return true end
		end
	end
	if not F.MayAllocate() then return false end
	if Crown(sender) or Lord(sender, GetGuildInfo("player")) then return true end
	for guild in pairs(ns.rdb and ns.rdb.guilds or {}) do if Lord(sender, guild) then return true end end
	return false
end
T.OnPrivate("GF", {
	piece = function(piece)
		local id, i, n, body = piece:match("^C(%w+):(%d+):(%d+):(.*)$")
		i, n = tonumber(i), tonumber(n)
		return id ~= nil and #id <= 8 and Int(i, ns.Codec.MAX_CHUNKS) and i >= 1 and Int(n, math.ceil(F.ROOM / ns.Codec.CHUNK)) and n >= i and #body <= ns.Codec.CHUNK
	end,
	-- Only solicited keeper replies or a current independently verified viewer can even
	-- enter the shared bounded assembler. The complete request rechecks its exact guild.
	from = Peer,
	to = F.Visible,
	send = function(to, text)
		local q, scope = Query(text)
		if q then
			local p = pending[ns.FullName(to) .. "|" .. scope]
			return SameIdentity(p) and p.id == q and F.MayView(scope) and T.KeeperByName(to) and Clock() - p.at >= 0 and Clock() - p.at <= F.WAIT
		end
		local xq, actor, _, xscope, rev = text:match("^GF~1~X~(%d+)~([^~]+)~([^~]*)~([^~]+)~(%d+)$")
		if xq then
			local r, a = replies[ns.FullName(to) .. "|" .. xscope], Actor(actor)
			return r ~= nil and a ~= nil and r.messages[actor] == text and SameIdentity(r.identity) and F.MayAllocate() and not Shared(actor)
				and F.MayView(xscope, to) and Mine(actor) and a.rev == tonumber(rev) and Clock() - r.at >= 0 and Clock() - r.at <= F.WAIT
		end
		local data = Parse(text); if not data then return false end
		local r = replies[ns.FullName(to) .. "|" .. data.scope]
		local a = Actor(data.actor)
		return r ~= nil and r.messages[data.actor] == text and SameIdentity(r.identity) and F.MayAllocate() and Shared(data.actor)
			and F.MayView(data.scope, to) and Mine(data.actor) and a ~= nil and a.rev == data.rev and Clock() - r.at >= 0 and Clock() - r.at <= F.WAIT
	end,
	handle = F.Handle,
})
function F.Open()
	if not F.Visible() then return false end
	T.Show("guild-finance")
	if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("treasury") end
	return true
end
function F.Link()
	return F.Visible() and { text = "> " .. Word("GFIN_LINK", "Guild income and event spending"), onClick = F.Open, gapAfter = true } or nil
end
function F.Build(q)
	local lines = { { text = "< " .. Word("TREASURY_TITLE", "Treasury"), onClick = function() T.Show("summary") end },
		{ header = true, text = Word("GFIN_LINK", "Guild income and event spending") } }
	if not F.Visible() then return lines, L.TAB_TREASURY, Word("GFIN_PRIVATE", "Private authorized aggregates only") end
	lines[#lines + 1] = { text = Word("GFIN_NOTE", "Explicit native copper attributions, not guild balances. Mail spending is sent, not proof of recipient arrival. Missing/offline sources are unknown; item gold values are never guessed."), wrap = true }
	local scope = Crown(ns.me) and "*" or GetGuildInfo("player")
	if F.MayView(scope) then F.Ask(scope) end
	local snapshots, mine = F.Held(scope), {}
	if F.MayAllocate() then
		for actor in pairs(Store() and Store().actors or {}) do if Mine(actor) then
			F.Reconcile(actor)
			local a = Actor(actor)
			if a then snapshots[#snapshots + 1] = { actor = actor, at = Clock(), rows = Rows(actor, "*"), cut = a.cut, localBook = true }; mine[actor] = true end
		end end
		lines[#lines + 1] = { text = "+ " .. Word("GFIN_NEW", "Name a guild event/purpose"), onClick = function() F.PromptEvent() end }
	end
	local totals = {}
	for _, s in ipairs(snapshots) do
		if s.localBook or not mine[s.actor] then
			for _, r in pairs(s.rows) do
				if not q or q == "" or ns.Holds(q, r.guild, r.purpose) then
					local g = totals[r.guild] or { inn = 0, out = 0 }; totals[r.guild] = g
					g.inn, g.out = g.inn + r.inn, g.out + r.out
					lines[#lines + 1] = { text = "<" .. r.guild .. "> " .. r.purpose, right = T.Coins(r.inn) .. " / " .. T.Coins(r.out),
						tooltip = function(tt) tt:AddLine(s.actor .. " #" .. r.id .. " · " .. date("%d/%m", r.at)); tt:AddLine(Word("GFIN_SOURCE", "Client-observed attribution; private source, not server certification."), 1, 1, 1, true) end }
					lines[#lines + 1] = { indent = 1, text = Word("GFIN_AGE", "Source age: %s"):format(ns.Ago(s.at)) .. (Clock() - s.at > F.FRESH and " · " .. Word("GFIN_STALE", "stale") or "")
						.. (s.cut and " · " .. Word("GFIN_CAPPED", "partial/capped") or ""), right = Word("GFIN_SENT", "Mail sent: %s"):format(T.Coins(r.sent)) }
					if r.corrected > 0 then lines[#lines + 1] = { indent = 1, text = Word("GFIN_CORRECTED", "Book corrections/unknown returns: %d"):format(r.corrected) } end
					if r.unknown > 0 then lines[#lines + 1] = { indent = 1, text = Word("GFIN_RETURN_UNKNOWN", "Ambiguous returned-mail attribution (unknown, excluded from spending): %s"):format(T.Coins(r.unknown)) } end
					lines[#lines + 1] = { indent = 1, text = Word("GFIN_VERIFIED", "Income guild observed by the game: %s; remainder is note-attributed, not membership/payment proof."):format(T.Coins(r.verified)) }
				end
			end
		end
	end
	for guild, row in pairs(totals) do lines[#lines + 1] = { header = true, text = "<" .. guild .. "> " .. Word("GFIN_TOTAL", "Allocated income / spending"), right = T.Coins(row.inn) .. " / " .. T.Coins(row.out) } end
	if #snapshots == 0 then lines[#lines + 1] = { text = Word("GFIN_EMPTY", "No authorized source snapshot received. This does not mean zero income or spending.") } end
	if F.MayAllocate() then
		local shown = 0
		local unknown = 0
		for actor in pairs(Store() and Store().actors or {}) do if Mine(actor) then
			local a = Actor(actor)
			for id, r in pairs(a and a.receipts or {}) do
				if not r.out and not r.guild and r.valid and not r.event then unknown = unknown + r.money end
				if not r.event and r.valid and (r.out or r.guild) and shown < 15 then
				shown = shown + 1
				lines[#lines + 1] = { text = Word("GFIN_ASSIGN", "Assign receipt #%d (%s)"):format(id, T.Coins(r.money)), right = r.out and Word("GFIN_OUT", "spending") or r.guild,
					onClick = function() F.PromptAssign(id, actor) end }
			end end
		end end
		if unknown > 0 then lines[#lines + 1] = { text = Word("GFIN_UNATTRIBUTED", "Native income with unknown guild (unattributed)"), right = T.Coins(unknown) } end
	end
	return lines, L.TAB_TREASURY, Word("GFIN_PRIVATE", "Private authorized aggregates only")
end
local function EditShow(self) local box = self.editBox or self.EditBox; if box then box:SetText(""); box:SetFocus() end end
StaticPopupDialogs.OLYMPUS_GFIN_EVENT = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, OnShow = EditShow,
	OnAccept = function(self) local box = self.editBox or self.EditBox; if not F.CreateEvent(box and box:GetText()) then ns.Print(Word("GFIN_EVENT_USAGE", "Guild | event/purpose. A current keeper assigns real receipts; no gold moves.")) end end,
	EditBoxOnEnterPressed = function(self) if not F.CreateEvent(self:GetText()) then ns.Print(Word("GFIN_EVENT_USAGE", "Guild | event/purpose. A current keeper assigns real receipts; no gold moves.")) end self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
StaticPopupDialogs.OLYMPUS_GFIN_ASSIGN = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, OnShow = EditShow,
	OnAccept = function(self, data) local d, box = data or self.data, self.editBox or self.EditBox; if d then F.AssignText(d, box and box:GetText()) end end,
	EditBoxOnEnterPressed = function(self) local d = self:GetParent().data; if d then F.AssignText(d, self:GetText()) end self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
function F.PromptEvent() if F.MayAllocate() then ns.ShowDialog("OLYMPUS_GFIN_EVENT", Word("GFIN_EVENT_USAGE", "Guild | event/purpose. A current keeper assigns real receipts; no gold moves.")) end end
function F.AssignText(d, text)
	if type(d) ~= "table" or not F.MayAllocate() or not Mine(d.actor) then return false end
	local id = tonumber(text)
	if not id then id = F.CreateEvent(text, d.actor) end
	return id and F.Allocate(d.id, id, d.actor) or false
end
function F.PromptAssign(id, actor)
	if not F.MayAllocate() or not Mine(actor) then return false end
	local a = Actor(actor); if not a then return false end
	local names = {}; for event, e in pairs(a.events) do names[#names + 1] = event .. ": <" .. e.guild .. "> " .. e.purpose end
	table.sort(names)
	ns.ShowDialog("OLYMPUS_GFIN_ASSIGN", Word("GFIN_ASSIGN_USAGE", "Type an event number, or Guild | purpose to create one. Each native receipt can be assigned once. Nothing sends or moves gold.") .. "\n" .. table.concat(names, "\n"), nil, { id = id, actor = actor })
	return true
end
ns.On("TREASURY_RECEIPT", F.Received)
ns.On("TREASURY_CHANGED", function()
	F.Reconcile()
	-- Observe consent transitions even when no viewer happened to ask during the no.
	-- A subsequent yes is a new revision, never a resurrection of a queued old answer.
	for actor in pairs(Store() and Store().actors or {}) do
		if Mine(actor) then local a = Actor(actor); if a then ShareState(a, actor) end end
	end
end)
