local ADDON, ns = ...
local L, D, T = ns.L, ns.Dues, ns.Treasury

-- Aggregate history only. Existing dues arithmetic and payment authority are untouched.
-- Reset snapshots contain no payer names; old paid figures never use today's roster or links.
local History = {}
ns.DuesHistory = History
History.WEEKS, History.GUILDS, History.WIRE_GUILDS = 5, 150, 30
History.BOUNDARY, History.FRESH, History.ASK_GAP = 90, 600, 180
History.REPLY_WAIT, History.ROOM = 180, 6000
local observed, pending, received
local replies = {}
local nextId, lastAsk, answered = 0, -math.huge, {}
local function Clock() return math.floor((GetServerTime and GetServerTime()) or ns.Now()) end
local function Integer(n, limit)
	return type(n) == "number" and n == n and n % 1 == 0 and n >= 0 and n <= limit
end
local function Guild(name)
	return type(name) == "string" and #name <= 72 and not name:find("[~|%c;=/,:]")
		and (name == "" or (not ns.Codec.LongGuild(name) and ns.IsFederation(name)))
end
local function B(n) return n == nil and "-" or ns.Codec.Base36(n) end
local function N(text, limit)
	if text == "-" then return nil, true end
	if type(text) ~= "string" or #text > 8 or not text:find("^[0-9a-z]+$") then return nil, false end
	local n = tonumber(text, 36)
	return n, Integer(n, limit)
end
function History.IsTreasurer()
	return D.Available() and T.TreasurerPin(ns.me) == 1 and ns.IsTreasurer(ns.me, GetGuildInfo("player")) == true
end
function History.IsKing() return D.Available() and ns.King.IsKing() and ns.IsKingCharacter(ns.me) end
function History.Sees() return History.IsTreasurer() or History.IsKing() end
local function KingPeer(name)
	if not ns.IsKingCharacter(name) then return false end
	local guild = ns.KingGuildName()
	if guild == GetGuildInfo("player") and not ns.Roster.Fresh() then return false end
	local rank, source, support = ns.Data.AuthorizedRank(name, guild)
	return rank == 0 and (source == "roster" or source == "pinned" or source == "signed"
		or (source == "census" and (support or 0) >= 2 and not ns.Data.Dispute(ns.Data.Guild(guild))))
end
local function Identity()
	return { me = ns.me, guild = GetGuildInfo("player"), store = ns.rdb, faction = ns.faction, realm = ns.realm }
end
local function SameIdentity(x)
	return x and x.me == ns.me and x.guild == GetGuildInfo("player") and x.store == ns.rdb
		and x.faction == ns.faction and x.realm == ns.realm and D.Available()
end
local function Store()
	local s = ns.rdb.duesHistory
	if type(s) ~= "table" or s.version ~= 1 or type(s.weeks) ~= "table" then
		s = { version = 1, weeks = {} }; ns.rdb.duesHistory = s
	end
	local week = D.Week()
	for w in pairs(s.weeks) do if not Integer(w, 1000000) or w < week - 4 or w > week then s.weeks[w] = nil end end
	return s.weeks
end
local function Books()
	local out, pins = {}, {}
	T.Migrate()
	for _, b in pairs(ns.rdb.treasuryBooks or {}) do
		local pin = type(b) == "table" and T.TreasurerPin(b.name)
		if pin and b.epoch == T.EPOCH and type(b.lines) == "table" then
			out[#out + 1], pins[pin] = b, true
		end
	end
	return out, pins
end
local function Complete(books, pins, week)
	for i in ipairs(ns.TREASURER_CHARACTERS) do if not pins[i] then return false end end
	for _, b in ipairs(books) do
		local opened = tonumber(b.openedAt or b.opened)
		if not opened or opened > D.WeekStart(week) then return false end
	end
	return #books > 0
end
-- Receipt placement comes from that week's book, never a current roster or another week's guild.
function History.Raw(week)
	if not History.IsTreasurer() or not Integer(week, 1000000) or week > D.Week() or week < D.Week() - 4 then return nil end
	local books, pins = Books()
	local people, digest = {}, {}
	for _, book in ipairs(books) do
		local sums = T.SumsOf(book)
		for key, p in pairs(sums.weeks and sums.weeks[week] or {}) do
			if type(key) == "string" and type(p) == "table" and Integer(p.c, T.MAX_COPPER) and p.c > 0 then
				local x = people[key] or { copper = 0, t = 0 }; people[key] = x
				x.copper = math.min(T.MAX_COPPER, x.copper + p.c)
				if Guild(p.g) and p.g ~= "" and (not x.guild or (p.gv and not x.gv) or (p.gv == x.gv and (p.t or 0) >= x.t)) then
					x.guild, x.gv, x.t = p.g, p.gv, tonumber(p.t) or 0
				end
			end
		end
	end
	local rows = {}
	for key, x in pairs(people) do
		local gk = (x.guild or ""):lower()
		local r = rows[gk] or { name = x.guild or "", copper = 0, payers = 0 }; rows[gk] = r
		r.copper, r.payers = math.min(T.MAX_COPPER, r.copper + x.copper), r.payers + 1
		digest[#digest + 1] = key .. ":" .. x.copper .. ":" .. gk
	end
	table.sort(digest)
	return { rows = rows, digest = ns.Comm.Hash36(table.concat(digest, ";")), complete = Complete(books, pins, week) }
end
local function Members()
	local rows, own = {}, GetGuildInfo("player")
	local count = #ns.Roster.members
	if ns.Roster.Fresh(History.BOUNDARY) and Integer(count, ns.Codec.GUILD_CAP) and count > 0 then
		rows[own:lower()] = { name = own, n = count }
	end
	for _, e in ipairs(ns.Data.Summary().guilds) do
		local g, name = e.g, e.name
		if name ~= own and Guild(name) and not g.mine and Integer(g.total, ns.Codec.GUILD_CAP) and g.total > 0
			and ns.Now() - (g.t or 0) >= 0 and ns.Now() - (g.t or 0) <= History.BOUNDARY and not ns.Data.Dispute(g) then
			local leader = ns.FullName(g.leader, g.realm)
			local rank = ns.Data.AuthorizedRank(leader, name)
			local fresh = 0
			for reporter, v in pairs(g.vouch or {}) do
				if type(v) == "table" and ns.Now() - (v.t or 0) >= 0 and ns.Now() - (v.t or 0) <= History.BOUNDARY
					and type(reporter) == "string" and v.n == g.total and v.ranks and v.ranks[leader] == 0 then fresh = fresh + 1 end
			end
			if rank == 0 and fresh >= 2 then rows[name:lower()] = { name = name, n = g.total } end
		end
	end
	local names = {}; for name in pairs(rows) do names[#names + 1] = name end; table.sort(names)
	for i = History.GUILDS + 1, #names do rows[names[i]] = nil end
	return rows, #names > History.GUILDS
end
-- A reset must actually cross between two uninterrupted observations in this login.
-- Login, an offline gap, stale roster/census and a later visit cannot invent an old denominator.
function History.Observe()
	if not History.IsTreasurer() then observed = nil; return false end
	local now, week = Clock(), D.Week()
	local ledger = D.Ledger(week)
	local raw = History.Raw(week)
	local sample = Identity()
	sample.at, sample.week, sample.raw, sample.rows, sample.amount = now, week, raw, {}, ledger.amount
	for key, row in pairs(ledger.guilds) do
		if Guild(row.name or "") then sample.rows[key] = { name = row.name or "", paid = row.paid, copper = row.copper, payers = row.payers } end
	end
	local previous = observed
	observed = sample
	if not previous or not SameIdentity(previous) or previous.week + 1 ~= week
		or now - previous.at < 0 or now - previous.at > History.BOUNDARY or now - D.WeekStart(week) > History.BOUNDARY then return false end
	local weeks = Store()
	local old = weeks[previous.week] or {}; weeks[previous.week] = old
	old.closed = { at = previous.at, amount = previous.amount, rows = previous.rows,
		digest = previous.raw.digest, complete = previous.raw.complete }
	if not weeks[week] then
		local members, cut = Members()
		weeks[week] = { at = now, members = members, cut = cut }
	end
	ns.Fire("TREASURY_CHANGED")
	return true
end
function History.Data()
	if not History.IsTreasurer() then return nil end
	local week, weeks, guilds, cut = D.Week(), Store(), {}, false
	local current = D.Ledger(week)
	for offset = 0, 4 do
		local w = week - offset
		local raw, saved = History.Raw(w), weeks[w]
		cut = cut or (saved and saved.cut == true) or false
		local closed = saved and saved.closed
		local rows = offset == 0 and current.guilds or raw.rows
		local names = {}; for key, r in pairs(rows) do names[key] = r.name or "" end
		for key, r in pairs(saved and saved.members or {}) do names[key] = r.name end
		for key, name in pairs(names) do
			local r = rows[key] or { copper = 0, payers = 0 }
			local g = guilds[key] or { name = name, weeks = {} }; guilds[key] = g
			local captured = closed and closed.rows[key]
			local known = offset == 0 or (closed and closed.complete and closed.digest == raw.digest
				and (not captured or (captured.copper == r.copper and captured.payers <= r.payers)))
			local member = saved and saved.members and saved.members[key]
			g.weeks[offset + 1] = { members = member and member.n, paid = raw.complete and known and (offset == 0 and r.paid or (captured and captured.paid or 0)) or nil,
				copper = r.copper, payers = r.payers, amount = offset == 0 and current.amount or (closed and closed.amount),
				state = raw.complete and known and (offset == 0 and "l" or "s") or "p" }
		end
	end
	local keys = {}; for key in pairs(guilds) do keys[#keys + 1] = key end
	table.sort(keys)
	for i = History.GUILDS + 1, #keys do guilds[keys[i]] = nil end
	return { week = week, at = Clock(), guilds = guilds, cut = cut or #keys > History.GUILDS }
end
local function Cell(r)
	r = r or { copper = 0, payers = 0, state = "p" }
	return table.concat({ B(r.members), B(r.paid), B(r.copper), B(r.payers), B(r.amount), r.state }, "/")
end
function History.Message(id)
	local data = History.Data(); if not data then return nil end
	local list = {}; for _, g in pairs(data.guilds) do list[#list + 1] = g end
	table.sort(list, function(a, b) return a.name < b.name end)
	local rows, cut = {}, data.cut == true
	local head = ("DH~1~D~%.0f~%d~%d~0~"):format(id, data.week, data.at)
	for _, g in ipairs(list) do
		local cells = {}; for i = 1, 5 do cells[i] = Cell(g.weeks[i]) end
		local row = g.name .. "=" .. table.concat(cells, ",")
		if #rows >= History.WIRE_GUILDS or #head + #table.concat(rows, ";") + #row + 1 > History.ROOM then cut = true; break end
		rows[#rows + 1] = row
	end
	return ("DH~1~D~%.0f~%d~%d~%d~"):format(id, data.week, data.at, cut and 1 or 0) .. table.concat(rows, ";")
end
local function Parse(text)
	if type(text) ~= "string" or #text > History.ROOM then return nil end
	local id, week, at, cut, body = text:match("^DH~1~D~(%d+)~(%d+)~(%d+)~([01])~([^~]*)$")
	id, week, at = tonumber(id), tonumber(week), tonumber(at)
	if not Integer(id, 9007199254740991) or not Integer(week, 1000000) or not Integer(at, 9007199254740991) then return nil end
	local data = { id = id, week = week, at = at, cut = cut == "1", guilds = {} }
	local count = 0
	for _, word in ipairs(body == "" and {} or ns.Codec.Split(body, ";")) do
		local name, cells = word:match("^([^=]*)=([^=]+)$")
		if not Guild(name) or data.guilds[name:lower()] then return nil end
		count = count + 1; if count > History.WIRE_GUILDS then return nil end
		local g, pieces = { name = name, weeks = {} }, ns.Codec.Split(cells, ",")
		if #pieces ~= 5 then return nil end
		for i, cell in ipairs(pieces) do
			local f = ns.Codec.Split(cell, "/"); if #f ~= 6 or not ({ s = true, l = true, p = true })[f[6]] then return nil end
			local m, mv = N(f[1], ns.Codec.GUILD_CAP); local p, pv = N(f[2], 10000)
			local c, cv = N(f[3], T.MAX_COPPER); local n, nv = N(f[4], 10000); local a, av = N(f[5], D.MAX_AMOUNT)
			if not (mv and pv and cv and nv and av and c and n) or (p and p > n) or (f[6] == "p" and p ~= nil)
				or (f[6] ~= "p" and (p == nil or a == nil))
				or (m == 0) or (a == 0) or (i > 1 and f[6] == "l") or (i == 1 and f[6] == "s") then return nil end
			g.weeks[i] = { members = m, paid = p, copper = c, payers = n, amount = a, state = f[6] }
		end
		data.guilds[name:lower()] = g
	end
	return data
end
function History.Ask()
	if not History.IsKing() or ns.Now() - lastAsk < History.ASK_GAP then return false end
	nextId = math.max(nextId + 1, Clock() * 1000)
	local p = Identity(); p.id, p.week, p.at = nextId, D.Week(), Clock()
	pending, lastAsk = p, ns.Now()
	local ok = T.Private(ns.FullName(ns.TREASURER, ns.TREASURER_REALM), "DH", ("DH~1~Q~%.0f~%d"):format(p.id, p.week), "dues history ask")
	if not ok then pending = nil end
	return ok
end
function History.Handle(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > History.ROOM then return false end
	local id, week = text:match("^DH~1~Q~(%d+)~(%d+)$")
	if id then
		id, week = tonumber(id), tonumber(week)
		if not History.IsTreasurer() or not T.CanSend() or not KingPeer(sender) or week ~= D.Week()
			or not Integer(id, 9007199254740991) or id < (Clock() - History.REPLY_WAIT) * 1000 or id > (Clock() + 30) * 1000 then return false end
		local key = ns.FullName(sender)
		if answered[key] and ns.Now() - answered[key] < History.ASK_GAP then return false end
		answered = { [key] = ns.Now() }
		local msg = History.Message(id)
		replies = { [key] = { identity = Identity(), msg = msg, at = Clock() } }
		return T.Private(sender, "DH", msg, "dues history answer")
	end
	if not History.IsKing() then pending, received = nil, nil; return false end
	if T.TreasurerPin(sender) ~= 1 or not pending then return false end
	if not SameIdentity(pending) then pending = nil; return false end
	local data = Parse(text)
	if not data or data.id ~= pending.id or data.week ~= pending.week or data.week ~= D.Week()
		or Clock() - pending.at > History.REPLY_WAIT or Clock() - pending.at < 0
		or data.at < pending.at - 30 or data.at > Clock() + 30 then return false end
	received, pending = data, nil
	received.heard, received.identity = Clock(), Identity(); ns.Fire("TREASURY_CHANGED")
	return true
end
function History.Held()
	if not History.IsKing() or not received or not SameIdentity(received.identity) or received.week ~= D.Week() or Clock() - received.heard < 0
		or Clock() - received.heard > History.FRESH then received = nil; return nil end
	return received
end
function History.Open()
	if not History.Sees() then return false end
	History.shown, D.shown = true, nil
	T.Show("dues"); return true
end
function History.Link()
	return History.Sees() and { text = L.DUESHISTORY_LINK, gapAfter = true, onClick = History.Open } or nil
end
-- Views renders fixed-height rows without wrapping, as on the ordinary dues page.
local function Para(lines, text, gapAfter)
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > 58 then
			lines[#lines + 1] = { text = row }; row = word
		else
			row = row == "" and word or (row .. " " .. word)
		end
	end
	if row ~= "" then lines[#lines + 1] = { text = row, gapAfter = gapAfter } end
end
function History.Build(q)
	if not History.Sees() then History.shown, received, pending = nil, nil, nil; return {}, L.TAB_TREASURY, L.DUESHISTORY_DETAIL end
	local lines = { { text = L.DUESHISTORY_BACK, onClick = function() History.shown = nil; D.Open() end, gapAfter = true },
		{ header = true, text = L.DUESHISTORY_TITLE } }
	Para(lines, L.DUESHISTORY_HINT)
	Para(lines, L.DUESHISTORY_BOOKS, true)
	local data = History.IsTreasurer() and History.Data() or History.Held()
	if History.IsKing() then History.Ask() end
	if not data then Para(lines, L.DUESHISTORY_WAIT); return lines, L.TAB_TREASURY, L.DUESHISTORY_DETAIL end
	if data.heard then Para(lines, L.DUESHISTORY_SOURCE:format(ns.Ago(data.heard))) end
	if data.cut then Para(lines, L.DUESHISTORY_CUT) end
	Para(lines, L.DUESHISTORY_PARTIAL, true)
	local list = {}; for _, g in pairs(data.guilds) do list[#list + 1] = g end
	table.sort(list, function(a, b) return a.name < b.name end)
	for _, g in ipairs(list) do
		if not q or ns.Holds(q, g.name) then
			lines[#lines + 1] = { header = true, text = g.name ~= "" and ("<" .. g.name .. ">") or L.DUESHISTORY_NO_GUILD, right = L.DUESHISTORY_COLS }
			for i = 1, 5 do
				local r = g.weeks[i] or { copper = 0, state = "p" }
				local average = r.members and r.state ~= "p" and T.GoldText(math.floor(r.copper / r.members)) or "?"
				lines[#lines + 1] = { indent = 1, text = D.DateLabel(data.week - i + 1),
					right = L.DUESHISTORY_ROW:format(tostring(r.members or "?"), tostring(r.paid or "?"), T.GoldText(r.copper), average) }
			end
			Para(lines, L.DUESHISTORY_CURRENT, true)
		end
	end
	if #list == 0 then Para(lines, L.DUESHISTORY_NONE) end
	return lines, L.TAB_TREASURY, L.DUESHISTORY_DETAIL
end
function History.Reset()
	observed, pending, received, History.shown = nil, nil, nil, nil
	lastAsk, answered, replies = -math.huge, {}, {}
	T.CancelPrivate(function(o) return o.kind == "DH" end)
end
T.OnPrivate("DH", {
	piece = function(piece)
		local id, i, n, body = piece:match("^C(%w+):(%d+):(%d+):(.*)$")
		i, n = tonumber(i), tonumber(n)
		return id ~= nil and #id <= 8 and Integer(i, ns.Codec.MAX_CHUNKS) and i >= 1
			and Integer(n, math.ceil(History.ROOM / ns.Codec.CHUNK)) and n >= i and #body <= ns.Codec.CHUNK
	end,
	from = function(s) return (History.IsKing() and T.TreasurerPin(s) == 1) or (History.IsTreasurer() and KingPeer(s)) end,
	to = History.Sees,
	send = function(to, msg)
		local id, week = msg:match("^DH~1~Q~(%d+)~(%d+)$")
		if id then return History.IsKing() and T.TreasurerPin(to) == 1 and SameIdentity(pending) and pending.id == tonumber(id)
			and pending.week == tonumber(week) and pending.week == D.Week() and Clock() - pending.at >= 0
			and Clock() - pending.at <= History.REPLY_WAIT end
		local data = Parse(msg)
		local reply = replies[ns.FullName(to)]
		return data ~= nil and reply ~= nil and reply.msg == msg and SameIdentity(reply.identity)
			and History.IsTreasurer() and T.CanSend() and KingPeer(to) and data.week == D.Week()
			and Clock() - data.at >= 0 and Clock() - data.at <= History.REPLY_WAIT
	end,
	handle = History.Handle,
})
ns.On("LOGIN", function() observed = nil; ns.Every(60, "dues history reset", History.Observe) end)
